import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

void main() {
  test('AES-GCM AAD round trip succeeds with matching metadata', () async {
    final key = CryptoManager.generateKey();
    final aad = CryptoManager.messageMetadataAad(
      version: 1,
      type: 'sms_incoming',
      id: 'message-1',
      timestamp: 123,
    );

    final encrypted = await CryptoManager.encryptWithAad(
      key,
      'sensitive body',
      aad: aad,
    );

    expect(
      await CryptoManager.decryptWithAad(key, encrypted, aad: aad),
      'sensitive body',
    );
  });

  test('AES-GCM AAD rejects changed metadata', () async {
    final key = CryptoManager.generateKey();
    final encrypted = await CryptoManager.encryptWithAad(
      key,
      'sensitive body',
      aad: CryptoManager.messageMetadataAad(
        version: 1,
        type: 'sms_incoming',
        id: 'message-1',
        timestamp: 123,
      ),
    );

    final changedAad = CryptoManager.messageMetadataAad(
      version: 1,
      type: 'sms_outgoing',
      id: 'message-1',
      timestamp: 123,
    );

    expect(
      await CryptoManager.decryptWithAad(key, encrypted, aad: changedAad),
      isNull,
    );
  });

  test('keyed lookup digest is stable and key-dependent', () async {
    final key = CryptoManager.generateKey();
    final otherKey = CryptoManager.generateKey();

    final first = await CryptoManager.keyedLookupDigest(key, '+905551112233');
    final second = await CryptoManager.keyedLookupDigest(key, '+905551112233');
    final differentKey = await CryptoManager.keyedLookupDigest(
      otherKey,
      '+905551112233',
    );

    expect(first, second);
    expect(first, isNot(differentKey));
    expect(first.length, 64);
  });

  test('message metadata canonicalization is deterministic', () {
    final first = CryptoManager.canonicalMessageMetadata(
      version: 1,
      type: 'sms_incoming',
      id: 'message-1',
      timestamp: 123,
    );
    final second = CryptoManager.canonicalMessageMetadata(
      version: 1,
      type: 'sms_incoming',
      id: 'message-1',
      timestamp: 123,
    );

    expect(first, second);
    expect(jsonDecode(first), {
      'version': 1,
      'type': 'sms_incoming',
      'id': 'message-1',
      'timestamp': 123,
    });
  });

  test('AAD decryption safely rejects malformed ciphertext', () async {
    final key = CryptoManager.generateKey();
    expect(
      await CryptoManager.decryptWithAad(key, 'not-base64', aad: const []),
      isNull,
    );
  });
}
