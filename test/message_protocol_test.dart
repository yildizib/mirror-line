import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/network/message_protocol.dart';

void main() {
  group('MirrorMessage', () {
    test('encode/decode round trip', () {
      final message = MirrorMessage(
        type: MessageTypes.smsIncoming,
        id: '12345',
        timestamp: 1700000000000,
        payload: 'base64payload==',
      );

      final decoded = MirrorMessage.decode(message.encode());
      expect(decoded.type, MessageTypes.smsIncoming);
      expect(decoded.id, '12345');
      expect(decoded.timestamp, 1700000000000);
      expect(decoded.payload, 'base64payload==');
    });

    test('decode throws on invalid json', () {
      expect(() => MirrorMessage.decode('not json'), throwsA(anything));
    });
  });

  group('MessageTypes', () {
    test('contains expected types', () {
      expect(MessageTypes.callIncoming, 'call_incoming');
      expect(MessageTypes.callRejected, 'call_rejected');
      expect(MessageTypes.smsIncoming, 'sms_incoming');
      expect(MessageTypes.smsOutgoing, 'sms_outgoing');
      expect(MessageTypes.ping, 'ping');
      expect(MessageTypes.pong, 'pong');
    });
  });
}
