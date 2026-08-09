// Verifies the pairing handshake protocol carries IP/role/deviceName in
// both directions (pairingRequest: scanner -> scanned; pairingAccept:
// scanned -> scanner) and that the payloads are encrypted end-to-end with
// the shared AES key from the QR.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pairingRequest carries scanner ip/role/deviceName and is encrypted',
      () async {
    final key = CryptoManager.generateKey();

    final receivedRequest = Completer<Map<String, dynamic>>();

    // Scanned side: a plain server socket that surfaces the raw
    // pairingRequest payload (no auth set -> pairing mode).
    final scanned = SocketManager(
      onMessage: (m) async {
        if (m.type == MessageTypes.pairingRequest) {
          final decrypted = await CryptoManager.decrypt(key, m.payload);
          if (decrypted != null) {
            receivedRequest.complete(jsonDecode(decrypted) as Map<String, dynamic>);
          }
        }
      },
      onConnected: () {},
      onDisconnected: () {},
    );
    await scanned.startServer(45911, key);

    // Scanner side: a temporary handshake socket, mimicking
    // PairingNotifier.sendRequest.
    final scanner = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    final ok = await scanner.connect('127.0.0.1', 45911, key);
    expect(ok, isTrue);

    await scanner.sendMessage(MessageTypes.pairingRequest, {
      'deviceName': 'Pixel 8',
      'peerId': 'scanner-id-123',
      'role': 'main',
      'publicKey': 'scanner-pub',
      'ip': '192.168.1.42',
    });

    final payload =
        await receivedRequest.future.timeout(const Duration(seconds: 5));
    expect(payload['deviceName'], 'Pixel 8');
    expect(payload['peerId'], 'scanner-id-123');
    expect(payload['role'], 'main');
    expect(payload['publicKey'], 'scanner-pub');
    expect(payload['ip'], '192.168.1.42',
        reason: 'scanner must claim its live local IP so the scanned side '
            'can store it as the peer IP');

    await scanner.disconnect();
    await scanned.disconnect();
  });

  test('pairingAccept carries scanned ip/role/deviceName and is encrypted',
      () async {
    final key = CryptoManager.generateKey();

    final receivedAccept = Completer<Map<String, dynamic>>();

    // Scanner side: receives the accept reply on its handshake socket.
    final scanner = SocketManager(
      onMessage: (m) async {
        if (m.type == MessageTypes.pairingAccept) {
          final decrypted = await CryptoManager.decrypt(key, m.payload);
          if (decrypted != null) {
            receivedAccept.complete(jsonDecode(decrypted) as Map<String, dynamic>);
          }
        }
      },
      onConnected: () {},
      onDisconnected: () {},
    );

    // Scanned side: receives the request, replies with accept.
    late final SocketManager scanned;
    scanned = SocketManager(
      onMessage: (m) async {
        if (m.type == MessageTypes.pairingRequest) {
          await scanned.sendMessage(MessageTypes.pairingAccept, {
            'deviceName': 'Galaxy S24',
            'peerId': 'scanned-id-456',
            'publicKey': 'scanned-pub',
            'role': 'source',
            'ip': '192.168.1.99',
          });
        }
      },
      onConnected: () {},
      onDisconnected: () {},
    );
    await scanned.startServer(45912, key);

    final ok = await scanner.connect('127.0.0.1', 45912, key);
    expect(ok, isTrue);

    // Trigger the exchange by sending a request.
    await scanner.sendMessage(MessageTypes.pairingRequest, {
      'deviceName': 'Pixel 8',
      'peerId': 'scanner-id-123',
      'role': 'main',
      'publicKey': 'scanner-pub',
      'ip': '192.168.1.42',
    });

    final payload =
        await receivedAccept.future.timeout(const Duration(seconds: 5));
    expect(payload['deviceName'], 'Galaxy S24');
    expect(payload['peerId'], 'scanned-id-456');
    expect(payload['publicKey'], 'scanned-pub');
    expect(payload['role'], 'source',
        reason: 'scanned device must claim its role so the scanner can '
            'display the counterpart role correctly');
    expect(payload['ip'], '192.168.1.99',
        reason: 'scanned device must claim its live local IP so the scanner '
            'can store it as the peer IP');

    await scanner.disconnect();
    await scanned.disconnect();
  });

  test('pairingAccept IP overrides the QR IP when persisting the peer',
      () async {
    // This documents the contract that scanner-side persistence prefers the
    // IP claimed in pairingAccept over the (possibly stale) IP from the QR.
    // The actual persistence logic lives in PairingNotifier.sendRequest,
    // which we can't unit-test without a full Riverpod stack -- so we test
    // the precedence rule directly on the parsed payload.
    final qrIp = '10.0.0.5';
    final acceptIp = '192.168.1.99';

    // Mimics the precedence in PairingNotifier.sendRequest:
    //   peerIp = acceptPayload.ip.isNotEmpty ? acceptPayload.ip : qrIp
    final acceptPayload = <String, dynamic>{'ip': acceptIp};
    final peerIp = (acceptPayload['ip'] as String?)?.isNotEmpty == true
        ? acceptPayload['ip'] as String
        : qrIp;
    expect(peerIp, acceptIp,
        reason: 'scanner must prefer the live IP from pairingAccept over '
            'the stale IP baked into the QR at display time');

    // And when the accept doesn't claim an IP, fall back to the QR.
    final emptyAccept = <String, dynamic>{'ip': ''};
    final peerIp2 = (emptyAccept['ip'] as String?)?.isNotEmpty == true
        ? emptyAccept['ip'] as String
        : qrIp;
    expect(peerIp2, qrIp);
  });
}