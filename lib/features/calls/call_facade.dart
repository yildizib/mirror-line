import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:uuid/uuid.dart';

final callFacadeProvider =
    StateNotifierProvider<CallFacade, List<CallEvent>>((ref) {
      final connectionFacade = ref.read(connectionFacadeProvider.notifier);
      return CallFacade(
        ref: ref,
        logger: Logger(),
        isSource: () => connectionFacade.isSource,
        sendOrQueue: connectionFacade.sendOrQueue,
        notify: connectionFacade.notify,
      );
    });

/// Derived provider: O(1) lookup by call ID instead of linear search.
final callEventMapProvider = Provider<Map<String, CallEvent>>((ref) {
  final calls = ref.watch(callFacadeProvider);
  return {for (final call in calls) call.id: call};
});

/// Merges the old CallListNotifier (state + DAO ops) and CallEventHandler
/// (native/peer message handling) into one Facade, per issue #39's F1 --
/// they were only ever split because the pre-#39 architecture had no
/// Facade layer to put them in together. Pure delegation, no behavior
/// change: still the same native events, peer messages and send/notify
/// callbacks as before.
class CallFacade extends StateNotifier<List<CallEvent>> {
  final CallEventDao _dao = CallEventDao();
  final Ref _ref;
  final Logger _logger;
  final bool Function() _isSource;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;

  // The Dart-generated id of the call currently ringing (or, once
  // answered, still ongoing) on this Source device. Native reports state
  // *transitions* without an id, so this is how they get matched back to
  // the right CallEvent.
  String? _activeCallId;

  CallFacade({
    required this._ref,
    required this._logger,
    required this._isSource,
    required this._sendOrQueue,
    required this._notify,
  }) : super([]) {
    load();
  }

  // -----------------------------------------------------------------------
  // State (formerly CallListNotifier)
  // -----------------------------------------------------------------------

  Future<void> load() async {
    state = await _dao.getAll();
  }

  /// Upsert: replaces the existing entry if [event.id] is already present
  /// instead of appending a duplicate. Native call events can legitimately
  /// fire more than once for what is logically the same call (see
  /// MirrorLineService's RINGING de-duplication) -- this keeps a stray
  /// repeat from ever showing up as two list entries.
  Future<void> add(CallEvent event) async {
    await _dao.insert(event);
    final exists = state.any((e) => e.id == event.id);
    state = exists
        ? state.map((e) => e.id == event.id ? event : e).toList()
        : [...state, event];
  }

  Future<void> updateStatus(String id, String status) async {
    await _dao.updateStatus(id, status);
    state = state
        .map((e) => e.id == id ? e.copyWith(status: status) : e)
        .toList();
  }

  /// Patches the caller's number/contact name on an already-tracked call
  /// (see RINGING_UPDATE) without treating it as a new event.
  Future<void> updateCallerInfo(
    String id, {
    String? number,
    String? contactName,
  }) async {
    await _dao.updateCallerInfo(id, number: number, contactName: contactName);
    state = state
        .map(
          (e) => e.id == id
              ? e.copyWith(number: number, contactName: contactName)
              : e,
        )
        .toList();
  }

  Future<void> remove(String id) async {
    await _dao.delete(id);
    state = state.where((e) => e.id != id).toList();
  }

  /// Permanently deletes every call in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    for (final id in idSet) {
      await _dao.delete(id);
    }
    state = state.where((e) => !idSet.contains(e.id)).toList();
  }

  /// Permanently deletes all calls (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await _dao.deleteAll();
    state = [];
  }

  // -----------------------------------------------------------------------
  // Native events (Source device only) -- formerly CallEventHandler
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    final callState = (data['state'] as String?) ?? 'RINGING';

    if (callState == 'RINGING') {
      final number = (data['number'] as String?) ?? '';
      final contactName = (data['contactName'] as String?) ?? '';
      final event = CallEvent(
        id: id,
        direction: 'incoming',
        number: number,
        contactName: contactName,
        timestamp: now,
        encrypted: '',
        status: 'ringing',
        createdAt: now,
      );
      _activeCallId = id;
      await add(event);
      await sendCallNotification(number, id: id, contactName: contactName);
      return;
    }

    if (callState == 'RINGING_UPDATE') {
      // Same call, e.g. the number/contact only resolved on a later
      // broadcast -- patch the existing entry, don't create a new one.
      final callId = _activeCallId;
      if (callId == null) return;
      final number = data['number'] as String?;
      final contactName = data['contactName'] as String?;
      await updateCallerInfo(callId, number: number, contactName: contactName);
      await _sendOrQueue(MessageTypes.callInfo, {
        'id': callId,
        'number': ?number,
        'contact_name': ?contactName,
      });
      return;
    }

    // ANSWERED / MISSED / ENDED: a state change for whichever call is
    // currently active, not a new call.
    final callId = _activeCallId;
    if (callId == null) return;
    final newStatus = switch (callState) {
      'ANSWERED' => 'answered',
      'MISSED' => 'missed',
      'ENDED' => 'ended',
      _ => null,
    };
    if (newStatus == null) return;

    final current = _findCall(callId);
    // Don't override a status we already know locally -- e.g. we just
    // rejected this call ourselves, and the resulting RINGING->IDLE
    // transition would otherwise relabel it "missed".
    if (current == null || current.status == 'rejected') return;

    // MISSED/ENDED can arrive with caller info the live broadcast never
    // resolved (see MirrorLineService.enrichFromCallLogThenNotify) --
    // CallEvent.copyWith only ever improves on what's already known, so
    // applying this unconditionally is safe even when it's empty/unchanged.
    final number = data['number'] as String?;
    final contactName = data['contactName'] as String?;
    if (number != null || contactName != null) {
      await updateCallerInfo(callId, number: number, contactName: contactName);
      await _sendOrQueue(MessageTypes.callInfo, {
        'id': callId,
        'number': ?number,
        'contact_name': ?contactName,
      });
    }

    await updateStatus(callId, newStatus);
    await _sendOrQueue(MessageTypes.callStatus, {
      'id': callId,
      'status': newStatus,
    });
    if (callState != 'ANSWERED') {
      _activeCallId = null;
    }
  }

  // -----------------------------------------------------------------------
  // Incoming peer messages (either device)
  // -----------------------------------------------------------------------

  Future<void> handleIncomingMessage(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now,
  ) async {
    switch (type) {
      case MessageTypes.callIncoming:
        final number = payload['number'] as String? ?? '';
        var contactName = payload['contact_name'] as String? ?? '';
        final id = payload['id'] as String? ?? message.id;
        // The Source device's address book may not have this contact even
        // if this (Main) device's does -- try locally before giving up on
        // a name and showing the bare number.
        if (contactName.isEmpty) {
          contactName = await TelephonyChannel.resolveContactName(number) ?? '';
        }
        final event = CallEvent(
          id: id,
          direction: 'incoming',
          number: number,
          contactName: contactName,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            payload['timestamp'] as int? ?? now.millisecondsSinceEpoch,
          ),
          encrypted: message.payload,
          status: 'ringing',
          createdAt: now,
        );
        await add(event);
        final l = appL10n(_ref);
        await _notify(
          id: int.tryParse(id) ?? 1,
          title: event.displayName(l),
          body: event.statusLabel(l),
          payload: NotificationPayload(type: 'call', id: id),
        );
        break;

      case MessageTypes.callRejected:
        final id = payload['id'] as String?;
        // Only actually end the call if it's still the one ringing --
        // guards against a reject command arriving after the call was
        // already answered/missed/ended, which would otherwise hang up
        // an unrelated live call instead of rejecting a ringing one.
        if (_isSource() && id != null && id == _activeCallId) {
          await TelephonyChannel.rejectCall();
          _activeCallId = null;
        }
        if (id != null) {
          await updateStatus(id, 'rejected');
        }
        break;

      case MessageTypes.callStatus:
        final id = payload['id'] as String?;
        final status = payload['status'] as String? ?? 'ended';
        if (id != null) {
          await updateStatus(id, status);
          // Update the existing call notification in place (same id) so it
          // reflects the live status (Cevaplandı/Cevapsız/Sonlandı) instead
          // of just sitting there saying "Çalıyor" forever.
          final updated = _findCall(id);
          if (updated != null) {
            final l = appL10n(_ref);
            await _notify(
              id: int.tryParse(id) ?? 1,
              title: updated.displayName(l),
              body: updated.statusLabel(l),
              payload: NotificationPayload(type: 'call', id: id),
            );
          }
        }
        break;

      case MessageTypes.callInfo:
        final id = payload['id'] as String?;
        if (id == null) break;
        await updateCallerInfo(
          id,
          number: payload['number'] as String?,
          contactName: payload['contact_name'] as String?,
        );
        final enriched = _findCall(id);
        if (enriched != null) {
          final l = appL10n(_ref);
          await _notify(
            id: int.tryParse(id) ?? 1,
            title: enriched.displayName(l),
            body: enriched.statusLabel(l),
            payload: NotificationPayload(type: 'call', id: id),
          );
        }
        break;

      default:
        _logger.i('CallFacade: unhandled message type $type');
    }
  }

  CallEvent? _findCall(String id) {
    final callMap = _ref.read(callEventMapProvider);
    return callMap[id];
  }

  // -----------------------------------------------------------------------
  // Outgoing (with offline queue, via the injected sendOrQueue)
  // -----------------------------------------------------------------------

  Future<bool> sendCallNotification(
    String number, {
    String? id,
    String? contactName,
  }) {
    final callId = id ?? const Uuid().v4();
    return _sendOrQueue(MessageTypes.callIncoming, {
      'id': callId,
      'number': number,
      if (contactName != null && contactName.isNotEmpty)
        'contact_name': contactName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendCallRejected(String callId) {
    return _sendOrQueue(MessageTypes.callRejected, {
      'id': callId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
