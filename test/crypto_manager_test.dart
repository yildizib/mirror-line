import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

void main() {
  group('CryptoManager', () {
    test('encrypt/decrypt round trip', () async {
      final key = CryptoManager.generateKey();
      const plainText = 'Merhaba MirrorLine! 🚀 {"json": true}';

      final encrypted = await CryptoManager.encrypt(key, plainText);
      expect(encrypted, isNot(plainText));

      final decrypted = await CryptoManager.decrypt(key, encrypted);
      expect(decrypted, plainText);
    });

    test('decrypt with wrong key returns null', () async {
      final key1 = CryptoManager.generateKey();
      final key2 = CryptoManager.generateKey();

      final encrypted = await CryptoManager.encrypt(key1, 'secret');
      final decrypted = await CryptoManager.decrypt(key2, encrypted);
      expect(decrypted, isNull);
    });

    test('decrypt of garbage returns null', () async {
      final key = CryptoManager.generateKey();
      expect(await CryptoManager.decrypt(key, 'not-base64!!!'), isNull);
      expect(await CryptoManager.decrypt(key, ''), isNull);
    });

    test(
      'same plaintext produces different ciphertexts (random nonce)',
      () async {
        final key = CryptoManager.generateKey();
        final a = await CryptoManager.encrypt(key, 'same');
        final b = await CryptoManager.encrypt(key, 'same');
        expect(a, isNot(b));
      },
    );

    test('verification code binds expected public-key identities', () async {
      final key = CryptoManager.generateKey();
      final keyBase64 = base64Encode(await key.extractBytes());

      final code = CryptoManager.verificationCodeFromKey(
        keyBase64,
        'peer-id',
        expectedPublicKeys: ['scanner-public-key', 'scanned-public-key'],
      );
      expect(
        CryptoManager.verificationCodeFromKey(
          keyBase64,
          'peer-id',
          expectedPublicKeys: ['scanned-public-key', 'scanner-public-key'],
        ),
        code,
      );
      expect(
        CryptoManager.verificationCodeFromKey(
          keyBase64,
          'peer-id',
          expectedPublicKeys: ['different-public-key', 'scanned-public-key'],
        ),
        isNot(code),
      );
    });
  });
}
