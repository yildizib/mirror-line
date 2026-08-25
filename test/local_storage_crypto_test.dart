import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';

void main() {
  late SecretKey key;

  setUp(() {
    key = CryptoManager.generateKey();
  });

  test('encrypts values with the versioned same-column prefix', () async {
    final stored = await LocalStorageCrypto.encrypt(key, 'private value');

    expect(stored, startsWith(LocalStorageCrypto.currentPrefix));
    expect(LocalStorageCrypto.isEncrypted(stored), isTrue);
    expect(LocalStorageCrypto.isLegacyPlaintext(stored), isFalse);
  });

  test('decrypts a versioned value back to the original plaintext', () async {
    final stored = await LocalStorageCrypto.encrypt(key, 'private value');

    expect(await LocalStorageCrypto.decrypt(key, stored), 'private value');
  });

  test('empty values remain empty without encryption overhead', () async {
    final stored = await LocalStorageCrypto.encrypt(key, '');

    expect(stored, isEmpty);
    expect(LocalStorageCrypto.isEncrypted(stored), isFalse);
    expect(await LocalStorageCrypto.decrypt(key, stored), isEmpty);
  });

  test(
    'legacy plaintext is identified and never returned as decrypted data',
    () async {
      const legacy = 'legacy plaintext value';

      expect(LocalStorageCrypto.isLegacyPlaintext(legacy), isTrue);
      expect(LocalStorageCrypto.isEncrypted(legacy), isFalse);
      expect(await LocalStorageCrypto.decrypt(key, legacy), isNull);
    },
  );

  test('malformed versioned ciphertext fails safely', () async {
    const malformed = '${LocalStorageCrypto.currentPrefix}not-ciphertext';

    expect(LocalStorageCrypto.isEncrypted(malformed), isTrue);
    expect(await LocalStorageCrypto.decrypt(key, malformed), isNull);
  });

  test(
    'unsupported storage versions are not treated as current ciphertext',
    () async {
      const futureValue = 'v2:future-ciphertext';

      expect(LocalStorageCrypto.isEncrypted(futureValue), isFalse);
      expect(LocalStorageCrypto.isLegacyPlaintext(futureValue), isTrue);
      expect(await LocalStorageCrypto.decrypt(key, futureValue), isNull);
    },
  );
}
