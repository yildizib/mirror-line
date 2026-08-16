import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server/client encrypted message round trip', () async {
    final key = CryptoManager.generateKey();
    final received = <MirrorMessage>[];
    final completer = Completer<void>();
    final serverConnected = Completer<void>();

    final server = SocketManager(
      onMessage: (m) {
        received.add(m);
        completer.complete();
      },
      onConnected: () {
        if (!serverConnected.isCompleted) serverConnected.complete();
      },
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
    await serverConnected.future.timeout(const Duration(seconds: 2));
    final firstSessionId = server.sessionId;
    expect(firstSessionId, isNotNull);

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
    final secondClient = SocketManager(onMessage: (_) {});
    expect(await secondClient.connect('127.0.0.1', 45901, key), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.sessionId, isNot(firstSessionId));
    await secondClient.disconnect();
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

  test('stale socket close cannot tear down its replacement', () async {
    final key = CryptoManager.generateKey();
    final received = Completer<void>();
    final server = SocketManager(
      onMessage: (message) {
        if (message.type == 'replacement_message' && !received.isCompleted) {
          received.complete();
        }
      },
      onConnected: () {},
      onDisconnected: () {},
    );
    await server.startServer(45906, key);

    final firstClient = SocketManager(onMessage: (_) {});
    final secondClient = SocketManager(onMessage: (_) {});
    expect(await firstClient.connect('127.0.0.1', 45906, key), isTrue);

    // The server replaces the first socket. Its delayed onDone callback must
    // remain scoped to that old session rather than closing the replacement.
    expect(await secondClient.connect('127.0.0.1', 45906, key), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.isConnected, isTrue);
    expect(await secondClient.sendMessage('replacement_message', {}), isTrue);
    await received.future.timeout(const Duration(seconds: 5));
    expect(server.isConnected, isTrue);

    await firstClient.disconnect();
    await secondClient.disconnect();
    await server.disconnect();
  });

  test('async message handlers complete in wire order', () async {
    final key = CryptoManager.generateKey();
    final completed = <String>[];
    final bothHandled = Completer<void>();
    final server = SocketManager(
      onMessage: (message) async {
        if (message.type == 'first') {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        completed.add(message.type);
        if (completed.length == 2) bothHandled.complete();
      },
    );
    await server.startServer(45907, key);

    final client = SocketManager(onMessage: (_) {});
    expect(await client.connect('127.0.0.1', 45907, key), isTrue);
    expect(await client.sendMessage('first', {}), isTrue);
    expect(await client.sendMessage('second', {}), isTrue);

    await bothHandled.future.timeout(const Duration(seconds: 5));
    expect(completed, ['first', 'second']);

    await client.disconnect();
    await server.disconnect();
  });

  test('superseded auth timeout cannot close a newer connection', () async {
    final key = CryptoManager.generateKey();
    final ed25519 = Ed25519();
    final serverKeyPair = await ed25519.newKeyPair();
    final clientKeyPair = await ed25519.newKeyPair();
    final serverPub = base64Encode(
      (await serverKeyPair.extractPublicKey()).bytes,
    );

    // The first server accepts TCP but never starts authentication.
    final silentSockets = <Socket>[];
    final silentServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      45908,
    );
    final silentSubscription = silentServer.listen(silentSockets.add);

    final client = SocketManager(
      onMessage: (_) {},
      authTimeout: const Duration(milliseconds: 800),
    );
    client.setAuthIdentity(
      peerPublicKeyBase64: serverPub,
      localKeyPair: clientKeyPair,
    );
    final staleAttempt = client.connect('127.0.0.1', 45908, key);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await client.disconnectClient();

    // Delay the replacement challenge until after the first session timer
    // would have fired, but before the replacement session timeout.
    final replacementSockets = <Socket>[];
    final replacementSocketSubscriptions = <StreamSubscription<String>>[];
    final replacementAck = Completer<void>();
    final replacementServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      45909,
    );
    final replacementServerSubscription = replacementServer.listen((socket) {
      replacementSockets.add(socket);
      replacementSocketSubscriptions.add(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) async {
              final message = MirrorMessage.decode(line);
              if (message.type == MessageTypes.authResponse) {
                final encrypted = await CryptoManager.encrypt(key, '{}');
                final authOk = MirrorMessage(
                  type: MessageTypes.authOk,
                  id: 'replacement-auth-ok',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  payload: encrypted,
                );
                socket.write('${authOk.encode()}\n');
                await socket.flush();
              } else if (message.type == MessageTypes.authAck &&
                  !replacementAck.isCompleted) {
                replacementAck.complete();
              }
            }),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 650), () async {
          final nonce = CryptoManager.generateNonce();
          final signature = await CryptoManager.sign(serverKeyPair, nonce);
          final encrypted = await CryptoManager.encrypt(
            key,
            jsonEncode({'nonce': nonce, 'signature': signature}),
          );
          final challenge = MirrorMessage(
            type: MessageTypes.authChallenge,
            id: 'replacement-challenge',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            payload: encrypted,
          );
          socket.write('${challenge.encode()}\n');
          await socket.flush();
        }),
      );
    });

    expect(await staleAttempt, isFalse);
    expect(await client.connect('127.0.0.1', 45909, key), isTrue);
    await replacementAck.future.timeout(const Duration(seconds: 2));
    expect(client.isAuthed, isTrue);

    await client.disconnect();
    await replacementServerSubscription.cancel();
    for (final subscription in replacementSocketSubscriptions) {
      await subscription.cancel();
    }
    for (final socket in replacementSockets) {
      socket.destroy();
    }
    await replacementServer.close();
    await silentSubscription.cancel();
    for (final socket in silentSockets) {
      socket.destroy();
    }
    await silentServer.close();
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
      final server = SocketManager(
        onMessage: (_) {},
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

      await client.disconnect();
      await server.disconnect();
    },
  );

  test(
    'server rejects an authentication response with the wrong nonce',
    () async {
      final key = CryptoManager.generateKey();
      final ed25519 = Ed25519();
      final serverKeyPair = await ed25519.newKeyPair();
      final clientKeyPair = await ed25519.newKeyPair();
      final clientPub = base64Encode(
        (await clientKeyPair.extractPublicKey()).bytes,
      );
      final server = SocketManager(
        onMessage: (_) {},
        onConnected: () {},
        onDisconnected: () {},
        authTimeout: const Duration(seconds: 2),
      );
      server.setAuthIdentity(
        peerPublicKeyBase64: clientPub,
        localKeyPair: serverKeyPair,
      );
      await server.startServer(45910, key);

      final closed = Completer<void>();
      final socket = await Socket.connect('127.0.0.1', 45910);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) async {
              final message = MirrorMessage.decode(line);
              if (message.type != MessageTypes.authChallenge) return;
              final wrongNonce = CryptoManager.generateNonce();
              final signature = await CryptoManager.sign(
                clientKeyPair,
                wrongNonce,
              );
              final encrypted = await CryptoManager.encrypt(
                key,
                jsonEncode({'nonce': wrongNonce, 'signature': signature}),
              );
              socket.write(
                '${MirrorMessage(type: MessageTypes.authResponse, id: 'wrong-nonce', timestamp: DateTime.now().millisecondsSinceEpoch, payload: encrypted).encode()}\n',
              );
              await socket.flush();
            },
            onDone: () {
              if (!closed.isCompleted) closed.complete();
            },
          );

      await closed.future.timeout(const Duration(seconds: 3));
      expect(server.isAuthed, isFalse);
      await socket.close();
      await server.disconnect();
    },
  );

  test('server rejects an auth ACK before the expected response', () async {
    final key = CryptoManager.generateKey();
    final ed25519 = Ed25519();
    final serverKeyPair = await ed25519.newKeyPair();
    final clientKeyPair = await ed25519.newKeyPair();
    final clientPub = base64Encode(
      (await clientKeyPair.extractPublicKey()).bytes,
    );
    final server = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
      authTimeout: const Duration(seconds: 2),
    );
    server.setAuthIdentity(
      peerPublicKeyBase64: clientPub,
      localKeyPair: serverKeyPair,
    );
    await server.startServer(45911, key);

    final closed = Completer<void>();
    final socket = await Socket.connect('127.0.0.1', 45911);
    final encrypted = await CryptoManager.encrypt(key, '{}');
    socket.write(
      '${MirrorMessage(type: MessageTypes.authAck, id: 'early-ack', timestamp: DateTime.now().millisecondsSinceEpoch, payload: encrypted).encode()}\n',
    );
    await socket.flush();
    socket.listen(
      null,
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );

    await closed.future.timeout(const Duration(seconds: 3));
    expect(server.isAuthed, isFalse);
    await socket.close();
    await server.disconnect();
  });

  test('client rejects a server challenge signed by the wrong key', () async {
    final key = CryptoManager.generateKey();
    final ed25519 = Ed25519();
    final trustedServerKeyPair = await ed25519.newKeyPair();
    final wrongServerKeyPair = await ed25519.newKeyPair();
    final clientKeyPair = await ed25519.newKeyPair();
    final trustedServerPub = base64Encode(
      (await trustedServerKeyPair.extractPublicKey()).bytes,
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 45912);
    final sockets = <Socket>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      unawaited(() async {
        final nonce = CryptoManager.generateNonce();
        final signature = await CryptoManager.sign(wrongServerKeyPair, nonce);
        final encrypted = await CryptoManager.encrypt(
          key,
          jsonEncode({'nonce': nonce, 'signature': signature}),
        );
        final challenge = MirrorMessage(
          type: MessageTypes.authChallenge,
          id: 'wrong-server-signature',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          payload: encrypted,
        );
        socket.write('${challenge.encode()}\n');
        await socket.flush();
      }());
    });

    final client = SocketManager(onMessage: (_) {});
    client.setAuthIdentity(
      peerPublicKeyBase64: trustedServerPub,
      localKeyPair: clientKeyPair,
    );
    expect(await client.connect('127.0.0.1', 45912, key), isFalse);

    await client.disconnect();
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  });
}
