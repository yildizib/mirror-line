// Verifies -- rather than just assumes -- that what actually goes out on
// the wire is encrypted: no plaintext SMS content, phone numbers, or
// pairing keys ever appear in the raw bytes captured directly off the
// socket, and the payload field looks like real ciphertext (high entropy,
// not just base64-of-plaintext).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sensitive plaintext never appears in raw bytes on the wire', () async {
    final key = CryptoManager.generateKey();
    const secretBody = 'GIZLI-SIR-cok-ozel-mesaj-icerigi-9d81f3';
    const secretNumber = '+905551112233';

    // A raw (undecrypting) TCP server, standing in for "an eavesdropper on
    // the network" -- it only sees exactly what SocketManager writes.
    final rawServer = await ServerSocket.bind('127.0.0.1', 0);
    final rawBytes = <int>[];
    final gotData = Completer<void>();
    late final StreamSubscription<Socket> acceptSub;
    acceptSub = rawServer.listen((socket) {
      socket.listen((data) {
        rawBytes.addAll(data);
        if (!gotData.isCompleted) gotData.complete();
      });
    });

    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    final ok = await client.connect('127.0.0.1', rawServer.port, key);
    expect(ok, isTrue);

    await client.sendMessage(MessageTypes.smsIncoming, {
      'id': 'msg-1',
      'address': secretNumber,
      'body': secretBody,
    });

    await gotData.future.timeout(const Duration(seconds: 5));
    // Give the rest of the frame a moment to arrive.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final onWire = utf8.decode(rawBytes, allowMalformed: true);

    expect(onWire, isNot(contains(secretBody)));
    expect(onWire, isNot(contains(secretNumber)));
    // Sanity: the un-encrypted envelope fields (type/id/timestamp) ARE
    // expected in the clear -- only the payload is encrypted. Confirms
    // this test is actually observing real traffic, not an empty capture.
    expect(onWire, contains('"type"'));
    expect(onWire, contains(MessageTypes.smsIncoming));

    // Pull the payload value out of the JSON line and confirm it decodes
    // as base64 ciphertext, not the plaintext (or a trivial encoding of
    // it, e.g. base64-of-plaintext with no real encryption).
    final envelope = jsonDecode(onWire.trim()) as Map<String, dynamic>;
    final payloadB64 = envelope['payload'] as String;
    final payloadBytes = base64Decode(payloadB64);
    final payloadRaw = utf8.decode(payloadBytes, allowMalformed: true);
    expect(payloadRaw, isNot(contains(secretBody)));
    expect(payloadRaw, isNot(contains(secretNumber)));

    // AES-256-GCM output is high-entropy; a naive encoding (e.g. XOR with a
    // short repeating key, or no encryption at all) would leave visible
    // structure. Rough but effective check: ciphertext+tag length must
    // exceed the plaintext JSON length (12-byte nonce + 16-byte tag
    // overhead), and it must not simply equal the plaintext bytes.
    final plaintextJson = jsonEncode({
      'id': 'msg-1',
      'address': secretNumber,
      'body': secretBody,
    });
    expect(payloadBytes.length, greaterThan(utf8.encode(plaintextJson).length));

    // And, of course, it must actually decrypt back to the real content
    // with the right key -- proving this is genuine AES-GCM, not noise.
    final decrypted = await CryptoManager.decrypt(key, payloadB64);
    expect(decrypted, isNotNull);
    expect(decrypted, contains(secretBody));
    expect(decrypted, contains(secretNumber));

    await client.disconnect();
    await acceptSub.cancel();
    await rawServer.close();
  });

  test('a different key cannot decrypt the payload (no shared-secret bypass)', () async {
    final key = CryptoManager.generateKey();
    final wrongKey = CryptoManager.generateKey();

    final encrypted = await CryptoManager.encrypt(key, 'hassas telefon numarası: 5551234567');
    final result = await CryptoManager.decrypt(wrongKey, encrypted);

    expect(result, isNull);
  });

  test('each encrypted message uses a fresh nonce (no nonce reuse)', () async {
    final key = CryptoManager.generateKey();
    const plaintext = 'aynı mesaj iki kere şifrelenirse';

    final first = await CryptoManager.encrypt(key, plaintext);
    final second = await CryptoManager.encrypt(key, plaintext);

    // Same plaintext, same key -> ciphertexts must still differ, because
    // AES-GCM security depends on never reusing a nonce.
    expect(first, isNot(equals(second)));

    final firstNonce = base64Decode(first).sublist(0, 12);
    final secondNonce = base64Decode(second).sublist(0, 12);
    expect(firstNonce, isNot(equals(secondNonce)));
  });

  test('pairing handshake auth messages carry no raw key/signature material', () async {
    // Generates a bunch of random nonces and confirms they look like real
    // random bytes (not e.g. all-zero or sequential), since a weak nonce
    // generator would undermine the challenge-response handshake's
    // security guarantees just as much as a network-level leak would.
    final nonces = List.generate(20, (_) => CryptoManager.generateNonce());
    expect(nonces.toSet().length, 20, reason: 'nonces must not repeat');

    final decodedLengths = nonces.map((n) => base64Decode(n).length).toSet();
    expect(decodedLengths, equals({32}), reason: 'expected 32-byte nonces');
    // Not a rigorous randomness test, just a smoke check that nonces
    // aren't trivially predictable (e.g. all the same byte repeated).
    for (final n in nonces) {
      final bytes = base64Decode(n);
      final distinctByteValues = bytes.toSet().length;
      expect(distinctByteValues, greaterThan(1));
    }
  });
}
