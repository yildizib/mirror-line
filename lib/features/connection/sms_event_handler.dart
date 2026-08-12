import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/network/message_protocol.dart'
    show MessageTypes, MirrorMessage;
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/connection/call_event_handler.dart'
    show SendOrQueue, ShowNotification;
import 'package:mirrorline/features/sms/sms_list_provider.dart';
import 'package:uuid/uuid.dart';

/// Everything about interpreting native SMS events (on the Source device)
/// and incoming sms_* peer messages (sms_incoming/sms_outgoing/sms_status),
/// extracted out of ConnectionFacade for the same reason as
/// CallEventHandler. Pure delegation, no behavior change.
class SmsEventHandler {
  final Ref _ref;
  final Logger _logger;
  final bool Function() _isSource;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;

  SmsEventHandler({
    required this._ref,
    required this._logger,
    required this._isSource,
    required this._sendOrQueue,
    required this._notify,
  });

  // -----------------------------------------------------------------------
  // Native events (Source device only)
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
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
        await _ref.read(smsListProvider.notifier).add(smsEvent);
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
          var status = 'sent';
          try {
            await TelephonyChannel.sendSms(address, body);
          } catch (e) {
            _logger.e('SMS send failed: $e');
            status = 'failed';
          }
          await _ref
              .read(smsListProvider.notifier)
              .add(
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
  }) {
    final smsId = id ?? const Uuid().v4();
    return _sendOrQueue(MessageTypes.smsOutgoing, {
      'id': smsId,
      'address': address,
      'body': body,
      if (contactName != null && contactName.isNotEmpty)
        'contact_name': contactName,
      if (threadId != null && threadId.isNotEmpty) 'thread_id': threadId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
