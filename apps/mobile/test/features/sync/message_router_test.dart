import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/sync/base/legacy_lan/message_protocol.dart';
import 'package:mirrorline/features/sync/facade/message_router.dart';

void main() {
  test('routes product messages to the owning feature contract', () async {
    final routedTypes = <String>[];
    final router = MessageRouter(
      onCall: (type, payload, message, receivedAt) async {
        routedTypes.add('call:$type');
      },
      onSms: (type, payload, message, receivedAt) async {
        routedTypes.add('sms:$type');
      },
      onNotification: (type, payload, message, receivedAt) async {
        routedTypes.add('notification:$type');
      },
      onPairingRequest: (payload, {liveRemoteAddress}) async {
        routedTypes.add('pairing:$liveRemoteAddress');
      },
      onPairingAck: (_) => routedTypes.add('pairing-ack'),
      onAck: (_) => routedTypes.add('ack'),
      onUnknown: (_) => routedTypes.add('unknown'),
    );

    for (final type in [
      MessageTypes.callIncoming,
      MessageTypes.smsIncoming,
      MessageTypes.notificationMirrored,
      MessageTypes.pairingRequest,
      MessageTypes.pairingAck,
      MessageTypes.ack,
      'future-message',
    ]) {
      await router.route(
        message: MirrorMessage(type: type, id: type, timestamp: 1, payload: ''),
        payload: const {},
        receivedAt: DateTime.utc(2026),
        liveRemoteAddress: '192.0.2.10',
      );
    }

    expect(routedTypes, [
      'call:${MessageTypes.callIncoming}',
      'sms:${MessageTypes.smsIncoming}',
      'notification:${MessageTypes.notificationMirrored}',
      'pairing:192.0.2.10',
      'pairing-ack',
      'ack',
      'unknown',
    ]);
  });
}
