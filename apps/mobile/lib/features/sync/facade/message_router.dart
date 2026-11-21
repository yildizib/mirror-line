import 'package:mirrorline/features/sync/base/legacy_lan/message_protocol.dart';

typedef FeatureMessageHandler =
    Future<void> Function(
      String type,
      Map<String, dynamic> payload,
      MirrorMessage message,
      DateTime receivedAt,
    );
typedef PairingRequestHandler =
    Future<void> Function(
      Map<String, dynamic> payload, {
      String? liveRemoteAddress,
    });

/// Routes decrypted peer messages to feature facade contracts.
///
/// Decryption, replay protection and transport lifecycle remain SyncFacade
/// responsibilities; product-specific handling lives behind these callbacks.
final class MessageRouter {
  const MessageRouter({
    required this.onCall,
    required this.onSms,
    required this.onNotification,
    required this.onPairingRequest,
    required this.onPairingAck,
    required this.onAck,
    required this.onUnknown,
  });

  final FeatureMessageHandler onCall;
  final FeatureMessageHandler onSms;
  final FeatureMessageHandler onNotification;
  final PairingRequestHandler onPairingRequest;
  final void Function(Map<String, dynamic> payload) onPairingAck;
  final void Function(MirrorMessage message) onAck;
  final void Function(MirrorMessage message) onUnknown;

  Future<void> route({
    required MirrorMessage message,
    required Map<String, dynamic> payload,
    required DateTime receivedAt,
    String? liveRemoteAddress,
  }) async {
    switch (message.type) {
      case MessageTypes.callIncoming:
      case MessageTypes.callRejected:
      case MessageTypes.callStatus:
      case MessageTypes.callInfo:
        await onCall(message.type, payload, message, receivedAt);
      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
      case MessageTypes.smsStatus:
        await onSms(message.type, payload, message, receivedAt);
      case MessageTypes.notificationMirrored:
      case MessageTypes.notificationRemoved:
        await onNotification(message.type, payload, message, receivedAt);
      case MessageTypes.pairingRequest:
        await onPairingRequest(payload, liveRemoteAddress: liveRemoteAddress);
      case MessageTypes.pairingAck:
        onPairingAck(payload);
      case MessageTypes.ack:
        onAck(message);
      case MessageTypes.pairingAccept:
      case MessageTypes.pairingReject:
        // Scanner-side pairing owns these responses.
        break;
      default:
        onUnknown(message);
    }
  }
}
