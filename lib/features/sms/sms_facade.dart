import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
import 'package:mirrorline/core/data/daos/platform_operation_dao.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

final smsFacadeProvider = StateNotifierProvider<SmsFacade, List<SmsMessage>>((
  ref,
) {
  final connectionFacade = ref.read(connectionFacadeProvider.notifier);
  return SmsFacade(
    ref: ref,
    logger: Logger(),
    isSource: () => connectionFacade.isSource,
    sendOrQueue: connectionFacade.sendOrQueue,
    sendOrQueueWithMutation: connectionFacade.sendOrQueueWithMutation,
    notify: connectionFacade.notify,
  );
});

/// Merges the old SmsListNotifier (state + DAO ops) and SmsEventHandler
/// (native/peer message handling) into one Facade, per issue #39's F1 --
/// same reasoning as CallFacade. Pure delegation, no behavior change.
class SmsFacade extends StateNotifier<List<SmsMessage>> {
  final SmsMessageDao _dao;
  final PlatformOperationDao _operations = PlatformOperationDao();
  final Ref _ref;
  final Logger _logger;
  final bool Function() _isSource;
  final SendOrQueue _sendOrQueue;
  final Future<bool> Function(String, Map<String, dynamic>, DomainMutation)?
  _sendOrQueueWithMutation;
  final ShowNotification _notify;
  final Map<String, String> _pendingStatuses = {};
  late final Future<void> _initialized;

  SmsFacade({
    required this._ref,
    required this._logger,
    required this._isSource,
    required this._sendOrQueue,
    this._sendOrQueueWithMutation,
    required this._notify,
    SmsMessageDao? dao,
  }) : _dao = dao ?? SmsMessageDao(),
       super([]) {
    _initialized = load();
  }

  Future<void> get initialized => _initialized;

  // -----------------------------------------------------------------------
  // State (formerly SmsListNotifier)
  // -----------------------------------------------------------------------

  Future<void> load() async {
    state = await _dao.getAll();
  }

  Future<List<SmsMessage>> loadRecent({
    required int limit,
    DateTime? since,
  }) async {
    return _dao.getRecent(limit: limit, since: since);
  }

  Future<List<SmsMessage>> loadOlder({
    required int limit,
    required int offset,
    DateTime? before,
  }) async {
    return _dao.getOlder(limit: limit, offset: offset, before: before);
  }

  Future<List<SmsMessage>> loadRecentByThread({
    required String threadId,
    required int limit,
  }) async {
    return _dao.getRecentByThread(threadId: threadId, limit: limit);
  }

  Future<List<SmsMessage>> loadOlderByThread({
    required String threadId,
    required int limit,
    required int offset,
  }) async {
    return _dao.getOlderByThread(
      threadId: threadId,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<SmsMessage>> loadRecentByAddress({
    required String address,
    required int limit,
  }) async {
    return _dao.getRecentByAddress(address: address, limit: limit);
  }

  Future<List<SmsMessage>> loadOlderByAddress({
    required String address,
    required int limit,
    required int offset,
  }) async {
    return _dao.getOlderByAddress(
      address: address,
      limit: limit,
      offset: offset,
    );
  }

  /// Upsert: replaces the existing entry if [message.id] is already
  /// present instead of appending a duplicate (see CallFacade.add for why
  /// this matters -- native events can repeat for what is logically the
  /// same message).
  Future<void> add(SmsMessage message) async {
    await initialized;
    await _persistMessage(message);
  }

  Future<void> _persistMessage(
    SmsMessage message, {
    DatabaseExecutor? transaction,
  }) async {
    final pendingStatus = _pendingStatuses.remove(message.id);
    final effectiveMessage = pendingStatus == null
        ? message
        : message.copyWith(status: pendingStatus);
    if (transaction == null) {
      await _dao.insert(effectiveMessage);
    } else {
      await _dao.insertOn(transaction, effectiveMessage);
    }
    final exists = state.any((m) => m.id == message.id);
    state = exists
        ? state.map((m) => m.id == message.id ? effectiveMessage : m).toList()
        : [effectiveMessage, ...state];
  }

  Future<void> updateStatus(String id, String status) async {
    await initialized;
    if (!state.any((message) => message.id == id)) {
      _pendingStatuses[id] = status;
      return;
    }
    await _dao.updateStatus(id, status);
    state = state
        .map((m) => m.id == id ? m.copyWith(status: status) : m)
        .toList();
  }

  Future<void> updateDeliveryStatus(String id, String status) async {
    await initialized;
    if (!state.any((message) => message.id == id)) return;
    await _dao.updateDeliveryStatus(id, status);
    state = state
        .map((m) => m.id == id ? m.copyWith(deliveryStatus: status) : m)
        .toList();
  }

  /// Marks any outgoing SMS still stuck on 'pending' as 'failed' once
  /// older than [threshold] -- its sms_status ack was lost mid-flight, or
  /// the peer never reconnected long enough for the queued ack to retry.
  /// Independent of the offline queue's own retry count, which only
  /// advances when the connection actually comes back up: without this,
  /// a message could otherwise show "Gönderiliyor" forever.
  Future<void> failStalePending(Duration threshold) async {
    await initialized;
    final cutoff = DateTime.now().subtract(threshold);
    final stale = state.where(
      (m) =>
          m.status == 'pending' &&
          m.direction == 'outgoing' &&
          m.timestamp.isBefore(cutoff),
    );
    for (final m in stale) {
      await updateStatus(m.id, 'failed');
    }
  }

  Future<void> remove(String id) async {
    await initialized;
    _pendingStatuses.remove(id);
    await _dao.delete(id);
    state = state.where((m) => m.id != id).toList();
  }

  /// Permanently deletes every message in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    await initialized;
    final idSet = ids.toSet();
    _pendingStatuses.removeWhere((id, _) => idSet.contains(id));
    for (final id in idSet) {
      await _dao.delete(id);
    }
    state = state.where((m) => !idSet.contains(m.id)).toList();
  }

  /// Deletes every message exchanged with [address] -- i.e. an entire
  /// thread, used from the SMS list's per-thread swipe-to-delete.
  Future<void> removeThread(String address) async {
    await initialized;
    final toRemove = state
        .where((m) => m.address == address)
        .map((m) => m.id)
        .toSet();
    if (toRemove.isEmpty) return;
    for (final id in toRemove) {
      await _dao.delete(id);
    }
    state = state.where((m) => !toRemove.contains(m.id)).toList();
  }

  /// Permanently deletes all messages (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await initialized;
    _pendingStatuses.clear();
    await _dao.deleteAll();
    state = [];
  }

  // -----------------------------------------------------------------------
  // Native events (Source device only) -- formerly SmsEventHandler
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    await initialized;
    final address = (data['address'] as String?) ?? '';
    final contactName = (data['contactName'] as String?) ?? '';
    final body = (data['body'] as String?) ?? '';
    final threadId = (data['threadId'] as String?) ?? '';
    final message = SmsMessage(
      id: id,
      threadId: threadId,
      address: address,
      contactName: contactName,
      body: body,
      encrypted: '',
      direction: 'incoming',
      status: 'received',
      timestamp: now,
      createdAt: now,
    );
    await add(message);
    await _sendOrQueue(MessageTypes.smsIncoming, {
      'id': id,
      'address': address,
      'contact_name': contactName,
      'body': body,
      'thread_id': threadId,
      'timestamp': now.millisecondsSinceEpoch,
    });
  }

  // -----------------------------------------------------------------------
  // Incoming peer messages (either device)
  // -----------------------------------------------------------------------

  Future<void> handleIncomingMessage(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now, {
    DatabaseExecutor? transaction,
  }) async {
    await initialized;
    switch (type) {
      case MessageTypes.smsIncoming:
        final address = payload['address'] as String? ?? '';
        var contactName = payload['contact_name'] as String? ?? '';
        if (contactName.isEmpty) {
          contactName =
              await TelephonyChannel.resolveContactName(address) ?? '';
        }
        final body = payload['body'] as String? ?? '';
        final id = payload['id'] as String? ?? message.id;
        final smsEvent = SmsMessage(
          id: id,
          threadId: payload['thread_id'] as String? ?? '',
          address: address,
          contactName: contactName,
          body: body,
          encrypted: message.payload,
          direction: 'incoming',
          status: 'received',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            payload['timestamp'] as int? ?? now.millisecondsSinceEpoch,
          ),
          createdAt: now,
        );
        await _persistMessage(smsEvent, transaction: transaction);
        await _notify(
          id: int.tryParse(id) ?? 2,
          title: smsEvent.displayName(appL10n(_ref)),
          body: body,
          payload: NotificationPayload(type: 'sms', id: id, address: address),
        );
        break;

      case MessageTypes.smsOutgoing:
        if (_isSource()) {
          final address = payload['address'] as String? ?? '';
          final body = payload['body'] as String? ?? '';
          final id = payload['id'] as String? ?? message.id;
          var status = 'pending';
          final operationPayload = jsonEncode({
            'messageId': id,
            'address': address,
            'body': body,
          });
          final claimed = transaction == null
              ? await _operations.claim(
                  operationId: message.id,
                  kind: 'sms_send',
                  payload: operationPayload,
                )
              : await _operations.claimOn(
                  transaction,
                  operationId: message.id,
                  kind: 'sms_send',
                  payload: operationPayload,
                );
          final existingState = claimed
              ? null
              : transaction == null
              ? await _operations.state(message.id)
              : await _operations.stateOn(transaction, message.id);
          if (existingState != 'succeeded' && existingState != 'executing') {
            if (transaction != null) {
              await _operations.updateStateOn(
                transaction,
                message.id,
                'executing',
              );
            } else {
              await _operations.updateState(message.id, 'executing');
            }
            // Submit to Android only after the Inbox transaction commits.
          }
          await _persistMessage(
            SmsMessage(
              id: id,
              threadId: payload['thread_id'] as String? ?? '',
              address: address,
              contactName: payload['contact_name'] as String? ?? '',
              body: body,
              encrypted: message.payload,
              direction: 'outgoing',
              status: status,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                payload['timestamp'] as int? ?? now.millisecondsSinceEpoch,
              ),
              createdAt: now,
            ),
            transaction: transaction,
          );
          // Queued (not fire-and-forget): if the connection drops between
          // sending the SMS and acking it, a direct socket write would be
          // silently lost, leaving the Main device's copy stuck on
          // 'pending' ("Gönderiliyor") forever with nothing left to ever
          // correct it. Queuing lets this retry once the connection is
          // back, same as every other outgoing message type.
          await _sendOrQueue(MessageTypes.smsStatus, {
            'id': id,
            'status': status,
          });
        }
        break;

      case MessageTypes.smsStatus:
        final id = payload['id'] as String?;
        final status = payload['status'] as String? ?? 'sent';
        if (id != null) {
          await updateStatus(id, status);
        }
        break;

      default:
        _logger.i('SmsFacade: unhandled message type $type');
    }
  }

  /// Submits a durably claimed operation after its Inbox transaction commits.
  /// Android reports the final sent result through the operation-ID callback.
  Future<void> executeOutgoingSms(
    Map<String, dynamic> payload,
    MirrorMessage message,
  ) async {
    if (!_isSource() || await _operations.state(message.id) != 'executing') {
      return;
    }
    try {
      await TelephonyChannel.sendSms(
        payload['address'] as String? ?? '',
        payload['body'] as String? ?? '',
        operationId: message.id,
      );
    } catch (error) {
      _logger.e('SMS submission failed: $error');
      await _operations.updateState(message.id, 'failed');
      await updateStatus(payload['id'] as String? ?? message.id, 'failed');
    }
  }

  Future<void> handleSmsResult(
    String operationId, {
    required bool sent,
    required bool success,
  }) async {
    final payload = await _operations.payload(operationId);
    if (payload == null) return;
    final messageId =
        (jsonDecode(payload) as Map<String, dynamic>)['messageId'] as String? ??
        operationId;
    if (sent) {
      final status = success ? 'sent' : 'failed';
      await _operations.updateState(
        operationId,
        success ? 'succeeded' : 'failed',
      );
      await updateStatus(messageId, status);
      await _sendOrQueue(MessageTypes.smsStatus, {
        'id': messageId,
        'status': status,
      });
    } else {
      await updateDeliveryStatus(messageId, success ? 'delivered' : 'failed');
    }
  }

  // -----------------------------------------------------------------------
  // Outgoing (with offline queue, via the injected sendOrQueue)
  // -----------------------------------------------------------------------

  Future<bool> sendSmsNotification(String address, String body, {String? id}) {
    final smsId = id ?? const Uuid().v4();
    return _sendOrQueue(MessageTypes.smsIncoming, {
      'id': smsId,
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendReplySms(
    String address,
    String body, {
    String? id,
    String? contactName,
    String? threadId,
    DateTime? timestamp,
  }) async {
    await initialized;
    final smsId = id ?? const Uuid().v4();
    final sentAt = timestamp ?? DateTime.now();
    final message = SmsMessage(
      id: smsId,
      threadId: threadId ?? '',
      address: address,
      contactName: contactName ?? '',
      body: body,
      encrypted: '',
      direction: 'outgoing',
      status: 'pending',
      timestamp: sentAt,
      createdAt: sentAt,
    );
    final payload = {
      'id': smsId,
      'address': address,
      'body': body,
      if (contactName != null && contactName.isNotEmpty)
        'contact_name': contactName,
      if (threadId != null && threadId.isNotEmpty) 'thread_id': threadId,
      'timestamp': sentAt.millisecondsSinceEpoch,
    };
    if (_sendOrQueueWithMutation != null) {
      final sent = await _sendOrQueueWithMutation(
        MessageTypes.smsOutgoing,
        payload,
        (database) => _dao.insertOn(database, message),
      );
      state = [message, ...state.where((item) => item.id != message.id)];
      return sent;
    }
    await add(message);
    return _sendOrQueue(MessageTypes.smsOutgoing, payload);
  }
}
