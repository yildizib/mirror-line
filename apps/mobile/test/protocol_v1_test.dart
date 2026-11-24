import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_crypto.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_error.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/signed_envelope.dart';

void main() {
  final fixture =
      jsonDecode(_fixtureFile().readAsStringSync()) as Map<String, dynamic>;
  final envelope = SignedEnvelope.decode(jsonEncode(fixture['envelope']));

  test('matches protocol v1 cross-runtime golden vector', () async {
    expect(
      envelope.encode(),
      fixture['canonicalUnsigned'].replaceFirst(
        '}',
        ',"signature":"${envelope.signature}"}',
      ),
    );
    expect(utf8.decode(envelope.authenticatedMetadataBytes()), fixture['aad']);

    final sharedSecret = SecretKey(_hex(fixture['x25519SharedSecretHex']));
    final key = await ProtocolCrypto.deriveDirectionalKey(
      sharedSecret: sharedSecret,
      senderUserId: envelope.senderUserId,
      senderDeviceId: envelope.senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      recipientDeviceId: envelope.recipientDeviceId,
      senderKeyVersion: envelope.senderKeyVersion,
      recipientKeyVersion: envelope.recipientKeyVersion,
      messageId: envelope.messageId,
    );
    expect(_hexString(await key.extractBytes()), fixture['derivedKeyHex']);
    final changedKeyVersion = await ProtocolCrypto.deriveDirectionalKey(
      sharedSecret: sharedSecret,
      senderUserId: envelope.senderUserId,
      senderDeviceId: envelope.senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      recipientDeviceId: envelope.recipientDeviceId,
      senderKeyVersion: envelope.senderKeyVersion + 1,
      recipientKeyVersion: envelope.recipientKeyVersion,
      messageId: envelope.messageId,
    );
    final changedMessageId = await ProtocolCrypto.deriveDirectionalKey(
      sharedSecret: sharedSecret,
      senderUserId: envelope.senderUserId,
      senderDeviceId: envelope.senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      recipientDeviceId: envelope.recipientDeviceId,
      senderKeyVersion: envelope.senderKeyVersion,
      recipientKeyVersion: envelope.recipientKeyVersion,
      messageId: 'other-message',
    );
    expect(
      await changedKeyVersion.extractBytes(),
      isNot(await key.extractBytes()),
    );
    expect(
      await changedMessageId.extractBytes(),
      isNot(await key.extractBytes()),
    );

    final alice = await X25519().newKeyPairFromSeed(
      _hex(fixture['x25519AlicePrivateKeyHex']),
    );
    final secret = await ProtocolCrypto.x25519SharedSecret(
      alice,
      SimplePublicKey(
        _hex(fixture['x25519BobPublicKeyHex']),
        type: KeyPairType.x25519,
      ),
    );
    expect(
      _hexString(await secret.extractBytes()),
      fixture['x25519SharedSecretHex'],
    );

    final encrypted = await ProtocolCrypto.encryptAesGcm(
      key: key,
      plaintext: utf8.encode(fixture['plaintext'] as String),
      envelope: envelope,
    );
    expect(
      base64Encode([...encrypted.ciphertext, ...encrypted.tag]),
      (fixture['envelope'] as Map<String, dynamic>)['ciphertext'],
    );
    expect(
      utf8.decode(
        await ProtocolCrypto.decryptAesGcm(key: key, envelope: envelope),
      ),
      fixture['plaintext'],
    );

    final signed = await ProtocolCrypto.signEnvelope(
      envelope.withSignature(''),
      await Ed25519().newKeyPairFromSeed(_hex(fixture['ed25519PrivateKeyHex'])),
    );
    expect(signed.signature, envelope.signature);
    expect(
      await ProtocolCrypto.verifyEnvelope(
        envelope,
        SimplePublicKey(
          _hex(fixture['ed25519PublicKeyHex']),
          type: KeyPairType.ed25519,
        ),
      ),
      isTrue,
    );
  });

  test('rejects altered envelope values with typed failures', () async {
    final key = SecretKey(_hex(fixture['derivedKeyHex']));
    final publicKey = SimplePublicKey(
      _hex(fixture['ed25519PublicKeyHex']),
      type: KeyPairType.ed25519,
    );
    final altered = [
      envelope.withSignature('${envelope.signature.substring(0, 87)}A'),
      envelope.changed(senderUserId: 'other-user'),
      envelope.changed(senderDeviceId: 'other-device'),
      envelope.changed(recipientUserId: 'other-user'),
      envelope.changed(recipientDeviceId: 'other-device'),
      envelope.changed(senderKeyVersion: envelope.senderKeyVersion + 1),
      envelope.changed(recipientKeyVersion: envelope.recipientKeyVersion + 1),
      envelope.changed(createdAt: envelope.createdAt + 1),
      envelope.changed(messageId: 'other-message'),
      envelope.changed(nonce: 'AAECAwQFBgcICQoM'),
      envelope.changed(
        ciphertext: 'AttAwGcWtZTX1IdggN0ouSZ4e2c95qRZykiZqdvsLCmOVr4=',
      ),
    ];

    for (final value in altered) {
      expect(await ProtocolCrypto.verifyEnvelope(value, publicKey), isFalse);
      await expectLater(
        ProtocolCrypto.decryptAesGcm(key: key, envelope: value),
        throwsA(isA<ProtocolException>()),
      );
    }
  });

  test('rejects unsupported, malformed, and oversized encodings', () {
    expect(
      () => SignedEnvelope.decode(envelope.copyWithVersion(2).encode()),
      throwsA(
        isA<ProtocolException>().having(
          (value) => value.code,
          'code',
          ProtocolErrorCode.unsupportedVersion,
        ),
      ),
    );
    expect(
      () => SignedEnvelope.decode(
        envelope.encode().replaceFirst(envelope.nonce, '!!!'),
      ),
      throwsA(isA<ProtocolException>()),
    );
    expect(
      () => SignedEnvelope.decode(
        '${envelope.encode()}${List.filled(SignedEnvelope.maxEncodedSize, ' ').join()}',
      ),
      throwsA(
        isA<ProtocolException>().having(
          (value) => value.code,
          'code',
          ProtocolErrorCode.oversizedInput,
        ),
      ),
    );
  });
}

List<int> _hex(String value) => [
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
];

String _hexString(List<int> value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

File _fixtureFile() {
  var directory = Directory.current;
  while (directory.path != directory.parent.path) {
    final candidate = File(
      '${directory.path}/protocol-fixtures/v1-golden.json',
    );
    if (candidate.existsSync()) return candidate;
    directory = directory.parent;
  }
  throw StateError('Unable to find protocol-v1 golden fixtures.');
}

extension on SignedEnvelope {
  SignedEnvelope copyWithVersion(int protocolVersion) => SignedEnvelope(
    protocolVersion: protocolVersion,
    senderUserId: senderUserId,
    senderDeviceId: senderDeviceId,
    recipientUserId: recipientUserId,
    recipientDeviceId: recipientDeviceId,
    senderKeyVersion: senderKeyVersion,
    recipientKeyVersion: recipientKeyVersion,
    messageId: messageId,
    messageType: messageType,
    createdAt: createdAt,
    nonce: nonce,
    ciphertext: ciphertext,
    signature: signature,
  );

  SignedEnvelope changed({
    String? senderUserId,
    String? senderDeviceId,
    String? recipientUserId,
    String? recipientDeviceId,
    int? senderKeyVersion,
    int? recipientKeyVersion,
    int? createdAt,
    String? messageId,
    String? nonce,
    String? ciphertext,
  }) => SignedEnvelope(
    protocolVersion: protocolVersion,
    senderUserId: senderUserId ?? this.senderUserId,
    senderDeviceId: senderDeviceId ?? this.senderDeviceId,
    recipientUserId: recipientUserId ?? this.recipientUserId,
    recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
    senderKeyVersion: senderKeyVersion ?? this.senderKeyVersion,
    recipientKeyVersion: recipientKeyVersion ?? this.recipientKeyVersion,
    messageId: messageId ?? this.messageId,
    messageType: messageType,
    createdAt: createdAt ?? this.createdAt,
    nonce: nonce ?? this.nonce,
    ciphertext: ciphertext ?? this.ciphertext,
    signature: signature,
  );
}
