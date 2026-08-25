import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/security/security_constants.dart';

void main() {
  group('MirrorMessage', () {
    test('encode/decode round trip', () {
      final message = MirrorMessage(
        type: MessageTypes.smsIncoming,
        id: '12345',
        timestamp: 1700000000000,
        payload: 'YmFzZTY0cGF5bG9hZA==',
      );

      final decoded = MirrorMessage.decode(message.encode());
      expect(decoded.type, MessageTypes.smsIncoming);
      expect(decoded.id, '12345');
      expect(decoded.timestamp, 1700000000000);
      expect(decoded.payload, 'YmFzZTY0cGF5bG9hZA==');
    });

    test('decode throws on invalid json', () {
      expect(() => MirrorMessage.decode('not json'), throwsA(anything));
    });

    test('decode rejects oversized JSON', () {
      final raw = 'x' * (SecurityConstants.maxJsonBytes + 1);
      expect(() => MirrorMessage.decode(raw), throwsA(anything));
    });

    test('decode rejects oversized encrypted payload', () {
      final message = MirrorMessage(
        type: MessageTypes.smsIncoming,
        id: 'large',
        timestamp: 1700000000000,
        payload: base64Encode(
          List<int>.filled(SecurityConstants.maxPayloadBytes + 1, 0),
        ),
      );
      expect(() => MirrorMessage.decode(message.encode()), throwsA(anything));
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
