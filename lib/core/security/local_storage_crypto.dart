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

  static Future<Map<String, dynamic>> encryptFields(
    SecretKey key,
    Map<String, dynamic> values,
    Iterable<String> fields,
  ) async {
    final result = Map<String, dynamic>.from(values);
    for (final field in fields) {
      final value = result[field];
      if (value is String && value.isNotEmpty) {
        result[field] = await encrypt(key, value);
      }
    }
    return result;
  }

  static Future<Map<String, dynamic>> decryptFields(
    Future<SecretKey> Function() keyLoader,
    Map<String, dynamic> values,
    Iterable<String> fields,
  ) async {
    final result = Map<String, dynamic>.from(values);
    SecretKey? key;
    for (final field in fields) {
      final value = result[field];
      if (value is String && value.isNotEmpty && isEncrypted(value)) {
        key ??= await keyLoader();
        final decrypted = await decrypt(key, value);
        if (decrypted == null) {
          throw StateError('Cannot decrypt local storage field: $field.');
        }
        result[field] = decrypted;
      }
    }
    return result;
  }
}
