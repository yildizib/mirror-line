import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/network/message_protocol.dart' show MessageTypes, MirrorMessage;
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/connection/call_event_handler.dart' show SendOrQueue, ShowNotification;
import 'package:mirrorline/features/sms/sms_list_provider.dart';

/// Everything about interpreting native SMS events (on the Source device)
/// and incoming sms_* peer messages (sms_incoming/sms_outgoing/sms_status),
/// extracted out of ConnectionNotifier for the same reason as
/// CallEventHandler. Pure delegation, no behavior change.
class SmsEventHandler {
  final Ref _ref;
  final Logger _logger;
  final bool Function() _isSource;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;
  // sms_outgoing needs to reply with sms_status over the live socket
  // directly (not queued) -- ConnectionNotifier owns the SocketManager, so
  // this reads it fresh each time rather than the handler holding a
  // possibly-stale reference.
  final SocketManager? Function() _socketManager;

  SmsEventHandler({
    required this._ref,
    required this._logger,
    required this._isSource,
    required this._sendOrQueue,
    required this._notify,
    required this._socketManager,
  });

  // -----------------------------------------------------------------------
  // Native events (Source device only)
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    final address = (data['address'] as String?) ?? 'unknown';
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
    await _ref.read(smsListProvider.notifier).add(message);
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
    DateTime now,
  ) async {
    switch (type) {
      case MessageTypes.smsIncoming:
        final address = payload['address'] as String? ?? 'unknown';
        var contactName = payload['contact_name'] as String? ?? '';
        if (contactName.isEmpty) {
          contactName = await TelephonyChannel.resolveContactName(address) ?? '';
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
              payload['timestamp'] as int? ?? now.millisecondsSinceEpoch),
          createdAt: now,
        );
        await _ref.read(smsListProvider.notifier).add(smsEvent);
        await _notify(
          id: int.tryParse(id) ?? 2,
          title: smsEvent.displayName,
          body: body,
          payload: message.id,
        );
        break;

      case MessageTypes.smsOutgoing:
        if (_isSource()) {
          final address = payload['address'] as String? ?? '';
          final body = payload['body'] as String? ?? '';
          final id = payload['id'] as String? ?? message.id;
          var status = 'sent';
          try {
            await TelephonyChannel.sendSms(address, body);
          } catch (e) {
            _logger.e('SMS send failed: $e');
            status = 'failed';
          }
          await _ref.read(smsListProvider.notifier).add(SmsMessage(
                id: id,
                threadId: payload['thread_id'] as String? ?? '',
                address: address,
                body: body,
                encrypted: message.payload,
                direction: 'outgoing',
                status: status,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    payload['timestamp'] as int? ?? now.millisecondsSinceEpoch),
                createdAt: now,
              ));
          await _socketManager()?.sendMessage(MessageTypes.smsStatus, {
            'id': id,
            'status': status,
          });
        }
        break;

      case MessageTypes.smsStatus:
        final id = payload['id'] as String?;
        final status = payload['status'] as String? ?? 'sent';
        if (id != null) {
          await _ref.read(smsListProvider.notifier).updateStatus(id, status);
        }
        break;

      default:
        _logger.i('SmsEventHandler: unhandled message type $type');
    }
  }

  // -----------------------------------------------------------------------
  // Outgoing (with offline queue, via the injected sendOrQueue)
  // -----------------------------------------------------------------------

  Future<bool> sendSmsNotification(String address, String body, {String? id}) {
    final smsId = id ?? '${DateTime.now().millisecondsSinceEpoch}';
    return _sendOrQueue(MessageTypes.smsIncoming, {
      'id': smsId,
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendReplySms(String address, String body, {String? id}) {
    final smsId = id ?? '${DateTime.now().millisecondsSinceEpoch}';
    return _sendOrQueue(MessageTypes.smsOutgoing, {
      'id': smsId,
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
