import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/network/message_protocol.dart';
import 'package:mirrorline/network/socket_manager.dart';
import 'package:mirrorline/security/crypto_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server/client encrypted message round trip', () async {
    final key = CryptoManager.generateKey();
    final received = <MirrorMessage>[];
    final completer = Completer<void>();

    final server = SocketManager(
      onMessage: (m) {
        received.add(m);
        completer.complete();
      },
      onConnected: () {},
      onDisconnected: () {},
    );

    await server.startServer(45901, key);

    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );

    final ok = await client.connect('127.0.0.1', 45901, key);
    expect(ok, isTrue);

    await client.sendMessage('sms_incoming', {
      'id': 'msg-1',
      'address': '+905551112233',
      'body': 'Merhaba',
    });

    await completer.future.timeout(const Duration(seconds: 5));
    expect(received, hasLength(1));
    expect(received.first.type, 'sms_incoming');

    // The payload must decrypt back to the original content.
    final decrypted = await CryptoManager.decrypt(key, received.first.payload);
    expect(decrypted, contains('"address":"+905551112233"'));
    expect(decrypted, contains('"body":"Merhaba"'));

    await client.disconnect();
    await server.disconnect();
  });

  test('sendMessage returns false when not connected', () async {
    final manager = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    expect(await manager.sendMessage('sms_incoming', {}), isFalse);
    await manager.disconnect();
  });

  test('connect to a dead port fails gracefully', () async {
    final key = CryptoManager.generateKey();
    final manager = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    // Port 45902 has no listener -> connect must fail and return false.
    final ok = await manager.connect('127.0.0.1', 45902, key);
    expect(ok, isFalse);
    expect(manager.isConnected, isFalse);
    await manager.disconnect();
  });

  test('ping is answered with pong and not forwarded to onMessage', () async {
    final key = CryptoManager.generateKey();
    final completer = Completer<void>();
    final serverMessages = <String>[];

    final server = SocketManager(
      onMessage: (m) => serverMessages.add(m.type),
      onConnected: () {},
      onDisconnected: () {},
    );
    await server.startServer(45903, key);

    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () => completer.complete(),
      onDisconnected: () {},
    );
    await client.connect('127.0.0.1', 45903, key);
    await completer.future.timeout(const Duration(seconds: 5));

    // Client sends ping; server should auto-answer pong (internal),
    // never surfacing ping/pong through onMessage.
    await client.sendMessage('ping', {});

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(serverMessages, isEmpty);

    await client.disconnect();
    await server.disconnect();
  });

  test('server accepts a new client after previous disconnect', () async {
    final key = CryptoManager.generateKey();
    final server = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    await server.startServer(45904, key);

    final c1 = SocketManager(onMessage: (_) {}, onConnected: () {}, onDisconnected: () {});
    expect(await c1.connect('127.0.0.1', 45904, key), isTrue);
    await c1.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final c2 = SocketManager(onMessage: (_) {}, onConnected: () {}, onDisconnected: () {});
    expect(await c2.connect('127.0.0.1', 45904, key), isTrue);

    await c2.disconnect();
    await server.disconnect();
  });

  test('authenticated handshake: both sides only report connected after mutual ack', () async {
    final key = CryptoManager.generateKey();
    final ed25519 = Ed25519();
    final serverKeyPair = await ed25519.newKeyPair();
    final clientKeyPair = await ed25519.newKeyPair();
    final serverPub = base64Encode((await serverKeyPair.extractPublicKey()).bytes);
    final clientPub = base64Encode((await clientKeyPair.extractPublicKey()).bytes);

    final serverConnected = Completer<void>();
    final server = SocketManager(
      onMessage: (_) {},
      onConnected: () => serverConnected.complete(),
      onDisconnected: () {},
    );
    server.setAuthIdentity(peerPublicKeyBase64: clientPub, localKeyPair: serverKeyPair);
    await server.startServer(45905, key);

    final clientConnected = Completer<void>();
    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () => clientConnected.complete(),
      onDisconnected: () {},
    );
    client.setAuthIdentity(peerPublicKeyBase64: serverPub, localKeyPair: clientKeyPair);

    final ok = await client.connect('127.0.0.1', 45905, key);
    expect(ok, isTrue);

    // Both sides must independently confirm the connection -- the server
    // only after receiving the client's ack of authOk, not merely after
    // sending it (regression test for the "server believes connected but
    // client already gave up" asymmetry).
    await clientConnected.future.timeout(const Duration(seconds: 5));
    await serverConnected.future.timeout(const Duration(seconds: 5));
    expect(client.isAuthed, isTrue);
    expect(server.isAuthed, isTrue);

    await client.disconnect();
    await server.disconnect();
  });
}
