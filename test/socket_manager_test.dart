import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

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
    expect(client.isPairingMode, isTrue);

    await client.sendMessage('sms_incoming', {
      'id': 'msg-1',
      'address': '+905551112233',
      'body': 'Merhaba',
    });

    await completer.future.timeout(const Duration(seconds: 5));
    expect(server.isPairingMode, isTrue);
    expect(received, hasLength(1));
    expect(received.first.type, 'sms_incoming');

    // The payload must decrypt back to the original content.
    final metadata = CryptoManager.canonicalMessageMetadata(
      version: received.first.protocolVersion,
      type: received.first.type,
      id: received.first.id,
      timestamp: received.first.timestamp,
    );
    final decrypted = await CryptoManager.decryptWithAad(
      key,
      received.first.payload,
      aad: utf8.encode(metadata),
    );
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

    final c1 = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    expect(await c1.connect('127.0.0.1', 45904, key), isTrue);
    await c1.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final c2 = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    expect(await c2.connect('127.0.0.1', 45904, key), isTrue);

    await c2.disconnect();
    await server.disconnect();
  });

  test(
    'stale socket data, completion, and error preserve replacement client',
    () async {
      final key = CryptoManager.generateKey();
      final received = Completer<void>();
      final callbacks =
          <
            ({
              void Function(List<int>) onData,
              void Function() onDone,
              void Function(Object) onError,
            })
          >[];
      var disconnectCount = 0;
      final server = SocketManager(
        onMessage: (_) {
          if (!received.isCompleted) received.complete();
        },
        onConnected: () {},
        onDisconnected: () => disconnectCount++,
        socketStreamListener: (socket, onData, onError, onDone) {
          callbacks.add((onData: onData, onDone: onDone, onError: onError));
          return socket.listen(
            onData,
            onError: onError,
            onDone: onDone,
            cancelOnError: true,
          );
        },
      );
      await server.startServer(45909, key);

      final c1 = SocketManager(
        onMessage: (_) {},
        onConnected: () {},
        onDisconnected: () {},
      );
      expect(await c1.connect('127.0.0.1', 45909, key), isTrue);

      final c2 = SocketManager(
        onMessage: (_) {},
        onConnected: () {},
        onDisconnected: () {},
      );
      expect(await c2.connect('127.0.0.1', 45909, key), isTrue);
      expect(callbacks, hasLength(2));

      final disconnectsAfterReplacement = disconnectCount;
      callbacks.first.onData([123]);
      callbacks.first.onDone();
      callbacks.first.onError(const SocketException('stale socket error'));
      expect(server.isConnected, isTrue);
      expect(disconnectCount, disconnectsAfterReplacement);
      expect(await c2.sendMessage('replacement_probe', {}), isTrue);
      await received.future.timeout(const Duration(seconds: 5));

      await c1.disconnect();
      await c2.disconnect();
      await server.disconnect();
    },
  );

  test('socket diagnostics include endpoints and transport mode', () async {
    final key = CryptoManager.generateKey();
    final output = _TestLogOutput();
    final logger = Logger(printer: SimplePrinter(), output: output);
    final serverConnected = Completer<void>();
    final server = SocketManager(
      onMessage: (_) {},
      onConnected: serverConnected.complete,
      logger: logger,
    );
    await server.startServer(45910, key);

    final client = SocketManager(onMessage: (_) {}, logger: logger);
    expect(await client.connect('127.0.0.1', 45910, key), isTrue);
    await serverConnected.future.timeout(const Duration(seconds: 5));

    final logs = output.lines.join('\n');
    expect(
      logs,
      contains(
        'Outgoing socket: target=127.0.0.1:45910, '
        'transport=qr-bootstrap',
      ),
    );
    expect(logs, contains('Incoming socket: remote=127.0.0.1:'));
    expect(logs, contains('transport=qr-bootstrap'));

    await client.disconnect();
    await server.disconnect();
  });

  test('server-mode manager is not reused for outbound connections', () async {
    final key = CryptoManager.generateKey();
    final manager = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );

    await manager.startServer(45906, key);
    expect(manager.isServerMode, isTrue);

    expect(await manager.connect('127.0.0.1', 45906, key), isFalse);
    expect(manager.isServerMode, isTrue);

    await manager.disconnect();
    expect(manager.isServerMode, isFalse);
  });

  test(
    'required client identity fails closed when key pair is missing',
    () async {
      final key = CryptoManager.generateKey();
      final server = SocketManager(
        onMessage: (_) {},
        onConnected: () {},
        onDisconnected: () {},
      );
      await server.startServer(45907, key);

      final client = SocketManager(
        onMessage: (_) {},
        onConnected: () {},
        onDisconnected: () {},
      )..requireAuthIdentity();

      expect(await client.connect('127.0.0.1', 45907, key), isFalse);
      expect(client.isConnected, isFalse);
      expect(client.isPairingMode, isFalse);

      await client.disconnect();
      await server.disconnect();
    },
  );

  test('required server identity never falls back to pairing mode', () async {
    final key = CryptoManager.generateKey();
    final disconnected = Completer<void>();
    final server = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {
        if (!disconnected.isCompleted) disconnected.complete();
      },
    )..requireAuthIdentity();
    await server.startServer(45908, key);

    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    await client.connect('127.0.0.1', 45908, key);
    await disconnected.future.timeout(const Duration(seconds: 5));

    expect(server.isConnected, isFalse);
    expect(server.isPairingMode, isFalse);

    await client.disconnect();
    await server.disconnect();
  });

  test(
    'authenticated handshake: both sides only report connected after mutual ack',
    () async {
      final key = CryptoManager.generateKey();
      final ed25519 = Ed25519();
      final serverKeyPair = await ed25519.newKeyPair();
      final clientKeyPair = await ed25519.newKeyPair();
      final serverPub = base64Encode(
        (await serverKeyPair.extractPublicKey()).bytes,
      );
      final clientPub = base64Encode(
        (await clientKeyPair.extractPublicKey()).bytes,
      );

      final serverConnected = Completer<void>();
      final received = <MirrorMessage>[];
      final server = SocketManager(
        onMessage: received.add,
        onConnected: () => serverConnected.complete(),
        onDisconnected: () {},
      );
      server.setAuthIdentity(
        peerPublicKeyBase64: clientPub,
        localKeyPair: serverKeyPair,
      );
      await server.startServer(45905, key);

      final clientConnected = Completer<void>();
      final client = SocketManager(
        onMessage: (_) {},
        onConnected: () => clientConnected.complete(),
        onDisconnected: () {},
      );
      client.setAuthIdentity(
        peerPublicKeyBase64: serverPub,
        localKeyPair: clientKeyPair,
      );

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

      expect(
        await client.sendMessage(MessageTypes.smsIncoming, {'body': 'x'}),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isNotEmpty);
      expect(received.single.sessionId, isNotEmpty);
      expect(received.single.sequence, 1);

      await client.disconnect();
      await server.disconnect();
    },
  );
}

class _TestLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}
