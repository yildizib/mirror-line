import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/daos/platform_operation_dao.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

final callFacadeProvider = StateNotifierProvider<CallFacade, List<CallEvent>>((
  ref,
) {
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
  final CallEventDao _dao;
  final PlatformOperationDao _operations = PlatformOperationDao();
  final Ref _ref;
  final Logger _logger;
  final bool Function() _isSource;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;
  final Future<bool> Function() _rejectCall;
  late final Future<void> _initialized;

  final Map<String, String> _callIdByNativeSession = {};

  // The one call that can currently be rejected. Session mappings above
  // remain independently addressable after a newer call starts ringing.
  String? _activeCallId;
  String? _activeNativeCallSessionId;
  String? _legacyCallId;

  // Serializes native call events (Source side only): the previous event
  // must fully complete -- including its awaited `sendCallNotification` /
  // `call_status` peer message -- before the next one starts. Without this,
  // RINGING's `await sendCallNotification` yields to the event loop and the
  // MISSED handler can run re-entrantly, sending `call_status` to the peer
  // before `call_incoming` has actually been written -- leaving the Main
  // device with a call created from `call_incoming` and stuck on "ringing".
  Future<void>? _nativeEventQueue;

  // On the Main side a `call_status` peer message can arrive before the
  // matching `call_incoming` (queued + reordered by the offline queue, or
  // simply delivered out of order). `updateStatus` is a silent no-op when
  // the call id is unknown, and that final status would then be lost
  // forever -- leaving the call showing "ringing". Buffer it here and apply
  // it the moment `call_incoming` creates the call.
  final Map<String, String> _pendingCallStatuses = {};

  // Main-side self-healing watchdog: if a call is still `ringing` after
  // the Source's MISSED `call_status` was lost/delayed (socket died, queue
  // never flushed, the user swiped the ringing notification with no dismiss
  // callback wired), the timer auto-converts it to `missed` locally so the
  // notification isn't frozen on "Çalıyor" forever. Per-call timers, keyed
  // by call id, cancelled on every terminal transition. Local-only: never
  // sends anything to the Source (the Source's MISSED stays authoritative,
  // and a stray `call_rejected` would risk calling `rejectCall` there).
  final Map<String, Timer> _ringingWatchdogs = {};
  static const Duration _ringingWatchdogTimeout = Duration(seconds: 90);

  CallFacade({
    required this._ref,
    required this._logger,
    required this._isSource,
    required this._sendOrQueue,
    required this._notify,
    Future<bool> Function()? rejectCall,
    CallEventDao? dao,
  }) : _dao = dao ?? CallEventDao(),
       _rejectCall = rejectCall ?? TelephonyChannel.rejectCall,
       super([]) {
    _initialized = load();
  }

  Future<void> get initialized => _initialized;

  // -----------------------------------------------------------------------
  // State (formerly CallListNotifier)
  // -----------------------------------------------------------------------

  Future<void> load() async {
    state = await _dao.getAll();
  }

  Future<List<CallEvent>> loadRecent({
    required int limit,
    DateTime? since,
  }) async {
    return _dao.getRecent(limit: limit, since: since);
  }

  Future<List<CallEvent>> loadOlder({
    required int limit,
    required int offset,
    DateTime? before,
  }) async {
    return _dao.getOlder(limit: limit, offset: offset, before: before);
  }

  /// Upsert: replaces the existing entry if [event.id] is already present
  /// instead of appending a duplicate. Native call events can legitimately
  /// fire more than once for what is logically the same call (see
  /// MirrorLineService's RINGING de-duplication) -- this keeps a stray
  /// repeat from ever showing up as two list entries.
  Future<void> add(CallEvent event) async {
    await initialized;
    await _persistEvent(event);
  }

  Future<void> _persistEvent(
    CallEvent event, {
    DatabaseExecutor? transaction,
    bool write = true,
  }) async {
    if (!write) {
      // The database row was committed with its Inbox record already.
    } else if (transaction == null) {
      await _dao.insert(event);
    } else {
      await _dao.insertOn(transaction, event);
    }
    final exists = state.any((e) => e.id == event.id);
    state = exists
        ? state.map((e) => e.id == event.id ? event : e).toList()
        : [...state, event];
  }

  Future<void> updateStatus(String id, String status) async {
    await initialized;
    await _dao.updateStatus(id, status);
    state = state
        .map((e) => e.id == id ? e.copyWith(status: status) : e)
        .toList();
    // Any terminal transition cancels the watchdog -- only `ringing` calls
    // need self-healing; once answered/missed/rejected/ended it's decided.
    if (status != 'ringing') _cancelWatchdog(id);
  }

  Future<void> updateDeliveryStatus(String id, String status) async {
    await initialized;
    if (!state.any((event) => event.id == id)) return;
    await _dao.updateDeliveryStatus(id, status);
    state = state
        .map((e) => e.id == id ? e.copyWith(deliveryStatus: status) : e)
        .toList();
  }

  /// Patches the caller's number/contact name on an already-tracked call
  /// (see RINGING_UPDATE) without treating it as a new event.
  Future<void> updateCallerInfo(
    String id, {
    String? number,
    String? contactName,
  }) async {
    await initialized;
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
    await initialized;
    _cancelWatchdog(id);
    await _dao.delete(id);
    state = state.where((e) => e.id != id).toList();
  }

  /// Permanently deletes every call in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    await initialized;
    final idSet = ids.toSet();
    for (final id in idSet) {
      _cancelWatchdog(id);
      await _dao.delete(id);
    }
    state = state.where((e) => !idSet.contains(e.id)).toList();
  }

  /// Permanently deletes all calls (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await initialized;
    _cancelAllWatchdogs();
    await _dao.deleteAll();
    state = [];
  }

  // -----------------------------------------------------------------------
  // Native events (Source device only) -- formerly CallEventHandler
  // -----------------------------------------------------------------------

  /// Public entry point for native call events (Source device only).
  /// Serializes events so a previous transition (notably RINGING's
  /// awaited `sendCallNotification`) fully completes before the next one
  /// (e.g. MISSED) starts -- otherwise the two could interleave and emit
  /// `call_status` to the peer before `call_incoming`, leaving the Main
  /// device with a call stuck on "ringing". See `_nativeEventQueue`.
  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) {
    final previous = _nativeEventQueue;
    final completer = Completer<void>();
    _nativeEventQueue = completer.future;

    Future<void> run() async {
      if (previous != null) await previous;
      await initialized;
      await _handleNativeEventImpl(data, id: id, now: now);
    }

    return run()
        .then((_) {
          completer.complete();
        })
        .catchError((Object e, StackTrace st) {
          _logger.e('Native call event error: $e', stackTrace: st);
          completer.complete();
        });
  }

  Future<void> _handleNativeEventImpl(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    final callState = (data['state'] as String?) ?? 'RINGING';
    final nativeCallSessionId = data['callSessionId'] as String?;

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
      _activeNativeCallSessionId = nativeCallSessionId;
      if (nativeCallSessionId == null) {
        _legacyCallId = id;
      } else {
        _legacyCallId = null;
        _callIdByNativeSession[nativeCallSessionId] = id;
      }
      await add(event);
      await sendCallNotification(number, id: id, contactName: contactName);
      return;
    }

    if (callState == 'RINGING_UPDATE') {
      // Same call, e.g. the number/contact only resolved on a later
      // broadcast -- patch the existing entry, don't create a new one.
      final callId = _callIdForNativeSession(nativeCallSessionId);
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

    final callId = _callIdForNativeSession(nativeCallSessionId);
    if (callId == null) return;
    final newStatus = switch (callState) {
      'ANSWERED' => 'answered',
      'MISSED' => 'missed',
      'ENDED' => 'ended',
      _ => null,
    };
    if (newStatus == null) return;
    if (callState == 'ANSWERED') {
      _clearActiveIfCurrent(nativeCallSessionId, callId);
    } else {
      _removeNativeSession(nativeCallSessionId, callId);
    }

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
  }

  String? _callIdForNativeSession(String? nativeCallSessionId) {
    if (nativeCallSessionId == null) return _legacyCallId;
    return _callIdByNativeSession[nativeCallSessionId];
  }

  void _clearActiveIfCurrent(String? nativeCallSessionId, String callId) {
    if (_activeCallId != callId ||
        _activeNativeCallSessionId != nativeCallSessionId) {
      return;
    }
    _activeCallId = null;
    _activeNativeCallSessionId = null;
  }

  void _removeNativeSession(String? nativeCallSessionId, String callId) {
    if (nativeCallSessionId == null) {
      if (_legacyCallId == callId) _legacyCallId = null;
    } else {
      _callIdByNativeSession.remove(nativeCallSessionId);
    }
    _clearActiveIfCurrent(nativeCallSessionId, callId);
  }

  // -----------------------------------------------------------------------
  // Incoming peer messages (either device)
  // -----------------------------------------------------------------------

  Future<bool> handleIncomingMessage(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now, {
    DatabaseExecutor? transaction,
    bool alreadyPersisted = false,
  }) async {
    if (transaction != null) {
      await persistIncomingMessageOn(type, payload, message, now, transaction);
      return true;
    }
    await initialized;
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
        await _persistEvent(
          event,
          transaction: transaction,
          write: !alreadyPersisted,
        );
        // A `call_status` peer message may have arrived before this
        // `call_incoming` (re-entrancy on the Source side, or queue
        // reorder). If so, it was buffered in `_pendingCallStatuses` --
        // apply it now so the call doesn't stay on "ringing".
        final pendingStatus = _pendingCallStatuses.remove(id);
        if (pendingStatus != null) {
          await updateStatus(id, pendingStatus);
        }
        // Render the notification from the *current* state (which may now
        // be `missed` after the buffered status above) instead of the
        // immutable local `event` (still `ringing`), so the body shows the
        // live status, not a stale "Çalıyor".
        final current = _findCall(id) ?? event;
        await _notifyCall(current);
        // Arm the self-healing watchdog: if the Source's MISSED never
        // arrives (socket died, queue lost) and the call is still
        // `ringing` after the timeout, it'll be auto-converted to `missed`
        // locally. Cancelled by updateStatus/remove* on any terminal
        // transition, so already-decided calls aren't touched.
        if (current.status == 'ringing') _armWatchdog(id);
        break;

      case MessageTypes.callRejected:
        final id = payload['id'] as String?;
        // Only actually end the call if it's still the one ringing --
        // guards against a reject command arriving after the call was
        // already answered/missed/ended, which would otherwise hang up
        // an unrelated live call instead of rejecting a ringing one.
        if (!_isSource() || id == null || id != _activeCallId) return false;
        final claimed = transaction == null
            ? await _operations.claim(
                operationId: id,
                kind: 'call_reject',
                payload: '{}',
              )
            : await _operations.claimOn(
                transaction,
                operationId: id,
                kind: 'call_reject',
                payload: '{}',
              );
        final existingState = claimed
            ? null
            : transaction == null
            ? await _operations.state(id)
            : await _operations.stateOn(transaction, id);
        final rejected = existingState == 'succeeded' || await _rejectCall();
        if (!rejected) return false;
        if (transaction != null) {
          await _operations.updateStateOn(transaction, id, 'succeeded');
        } else {
          await _operations.updateState(id, 'succeeded');
        }
        _removeNativeSession(_activeNativeCallSessionId, id);
        await updateStatus(id, 'rejected');
        await _sendOrQueue(MessageTypes.callStatus, {
          'id': id,
          'status': 'rejected',
        });
        return true;

      case MessageTypes.callStatus:
        final id = payload['id'] as String?;
        final status = payload['status'] as String? ?? 'ended';
        if (id == null) break;
        final existing = _findCall(id);
        if (existing == null) {
          // The matching `call_incoming` hasn't been processed yet
          // (out-of-order delivery). Remember the status and apply it
          // once the call is created, so it doesn't stay on "ringing".
          _pendingCallStatuses[id] = status;
          break;
        }
        // Don't downgrade a terminal status the user already set: a
        // user-initiated reject on Main shouldn't be relabeled "missed"
        // when the Source's later IDLE/MISSED transition arrives.
        if (existing.status == 'rejected' && status != 'rejected') break;
        await updateStatus(id, status);
        // Update the existing call notification in place (same id) so it
        // reflects the live status (Cevaplandı/Cevapsız/Sonlandı) instead
        // of just sitting there saying "Çalıyor" forever.
        final updated = _findCall(id);
        if (updated != null) await _notifyCall(updated);
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
        if (enriched != null) await _notifyCall(enriched);
        break;

      default:
        _logger.i('CallFacade: unhandled message type $type');
    }
    return true;
  }

  /// Persists an Inbox message without native calls, notifications, or state.
  Future<void> persistIncomingMessageOn(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now,
    DatabaseExecutor transaction,
  ) async {
    switch (type) {
      case MessageTypes.callIncoming:
        final id = payload['id'] as String? ?? message.id;
        await _dao.insertOn(
          transaction,
          CallEvent(
            id: id,
            direction: 'incoming',
            number: payload['number'] as String? ?? '',
            contactName: payload['contact_name'] as String? ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              payload['timestamp'] as int? ?? now.millisecondsSinceEpoch,
            ),
            encrypted: message.payload,
            status: 'ringing',
            createdAt: now,
          ),
        );
        break;
      case MessageTypes.callRejected:
        final id = payload['id'] as String?;
        if (!_isSource() || id == null) break;
        final claimed = await _operations.claimOn(
          transaction,
          operationId: id,
          kind: 'call_reject',
          payload: '{}',
        );
        final existingState = claimed
            ? null
            : await _operations.stateOn(transaction, id);
        if (existingState != 'succeeded' && existingState != 'executing') {
          await _operations.updateStateOn(transaction, id, 'executing');
        }
        break;
      case MessageTypes.callStatus:
        final id = payload['id'] as String?;
        if (id != null) {
          await _dao.updateStatusOn(
            transaction,
            id,
            payload['status'] as String? ?? 'ended',
          );
        }
        break;
      case MessageTypes.callInfo:
        final id = payload['id'] as String?;
        if (id != null) {
          await _dao.updateCallerInfoOn(
            transaction,
            id,
            number: payload['number'] as String?,
            contactName: payload['contact_name'] as String?,
          );
        }
        break;
    }
  }

  CallEvent? _findCall(String id) => state.where((e) => e.id == id).firstOrNull;

  /// Renders (or replaces, by id) the call notification from [event]'s
  /// current state. Single source of truth for notification rendering --
  /// callers always pass the *post-update* event so the body reflects the
  /// live status (missed/answered/ended) instead of a stale snapshot.
  Future<void> _notifyCall(CallEvent event) async {
    final l = appL10n(_ref);
    await _notify(
      id: int.tryParse(event.id) ?? 1,
      title: event.displayName(l),
      body: event.statusLabel(l),
      payload: NotificationPayload(type: 'call', id: event.id),
    );
  }

  // -----------------------------------------------------------------------
  // Watchdog (Main side only) -- self-healing for stuck "ringing" calls
  // -----------------------------------------------------------------------

  /// Arms a one-shot watchdog for a newly created `ringing` call. If the
  /// Source's MISSED `call_status` never arrives within the timeout, the
  /// call is locally converted to `missed` and its notification re-rendered
  /// so it doesn't sit on "Çalıyor" forever. Cancelled on every terminal
  /// transition via [_cancelWatchdog].
  void _armWatchdog(String id) {
    _cancelWatchdog(id);
    _ringingWatchdogs[id] = Timer(_ringingWatchdogTimeout, () async {
      _ringingWatchdogs.remove(id);
      final current = _findCall(id);
      if (current == null || current.status != 'ringing') return;
      await updateStatus(id, 'missed');
      final missed = _findCall(id);
      if (missed != null) await _notifyCall(missed);
    });
  }

  /// Cancels the watchdog for [id] if one is armed, and discards it. Called
  /// on every terminal transition (updateStatus, remove, removeMany,
  /// removeAll) so already-decided calls are never touched.
  void _cancelWatchdog(String id) {
    final timer = _ringingWatchdogs.remove(id);
    timer?.cancel();
  }

  void _cancelAllWatchdogs() {
    for (final timer in _ringingWatchdogs.values) {
      timer.cancel();
    }
    _ringingWatchdogs.clear();
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

  @override
  void dispose() {
    _cancelAllWatchdogs();
    super.dispose();
  }
}
