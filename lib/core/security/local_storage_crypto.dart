import 'package:cryptography/cryptography.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

/// Defines the versioned ciphertext format used in existing SQLite columns.
///
/// Legacy plaintext values intentionally have no prefix. This lets the
/// migration coordinator identify values that still need encryption without
/// adding parallel encrypted columns to the schema.
abstract final class LocalStorageCrypto {
  static const String currentPrefix = 'v1:';

  static bool isEncrypted(String storedValue) =>
      storedValue.startsWith(currentPrefix) &&
      storedValue.length > currentPrefix.length;

  static bool isLegacyPlaintext(String storedValue) =>
      storedValue.isNotEmpty && !isEncrypted(storedValue);

  static Future<String> encrypt(SecretKey key, String plaintext) async {
    if (plaintext.isEmpty) return '';
    final ciphertext = await CryptoManager.encrypt(key, plaintext);
    return '$currentPrefix$ciphertext';
  }

  /// Decrypts a value in the current format. Empty values remain empty.
  /// Legacy plaintext and malformed ciphertext return null so callers cannot
  /// accidentally display or treat unverified storage data as decrypted.
  static Future<String?> decrypt(SecretKey key, String storedValue) async {
    if (storedValue.isEmpty) return '';
    if (!isEncrypted(storedValue)) return null;

    final ciphertext = storedValue.substring(currentPrefix.length);
    return CryptoManager.decrypt(key, ciphertext);
  }
}
