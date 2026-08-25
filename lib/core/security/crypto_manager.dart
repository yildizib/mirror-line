import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

class CryptoManager {
  static final AesGcm _algorithm = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static SecretKey generateKey() {
    return SecretKey(_randomBytes(32));
  }

  static Future<String> encrypt(SecretKey key, String plainText) async {
    return encryptWithAad(key, plainText, aad: const []);
  }

  /// Encrypts [plainText] with AES-GCM and authenticates [aad] without
  /// encrypting it. The returned value contains nonce, ciphertext, and tag.
  static Future<String> encryptWithAad(
    SecretKey key,
    String plainText, {
    required List<int> aad,
  }) async {
    final nonceBytes = _randomBytes(12);

    final secretBox = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: key,
      nonce: nonceBytes,
      aad: aad,
    );

    final combined = Uint8List(
      nonceBytes.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    combined.setAll(0, nonceBytes);
    combined.setAll(nonceBytes.length, secretBox.cipherText);
    combined.setAll(
      nonceBytes.length + secretBox.cipherText.length,
      secretBox.mac.bytes,
    );

    return base64Encode(combined);
  }

  static Future<String?> decrypt(SecretKey key, String encryptedBase64) async {
    return decryptWithAad(key, encryptedBase64, aad: const []);
  }

  /// Decrypts an AES-GCM value and verifies its associated authenticated data.
  /// Returns null for malformed, unauthenticated, or undecryptable input.
  static Future<String?> decryptWithAad(
    SecretKey key,
    String encryptedBase64, {
    required List<int> aad,
  }) async {
    try {
      final combined = base64Decode(encryptedBase64);
      if (combined.length < 28) return null;

      final nonce = combined.sublist(0, 12);
      final macStart = combined.length - 16;
      final cipherText = combined.sublist(12, macStart);
      final macBytes = combined.sublist(macStart);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      final decrypted = await _algorithm.decrypt(
        secretBox,
        secretKey: key,
        aad: aad,
      );
      return utf8.decode(decrypted);
    } catch (e) {
      return null;
    }
  }

  /// Returns a keyed digest for equality lookups without storing the original
  /// value in the database. Callers should normalize values before hashing
  /// when their lookup semantics are case- or whitespace-insensitive.
  static Future<String> keyedLookupDigest(
    SecretKey key,
    String normalizedValue,
  ) async {
    final keyBytes = await key.extractBytes();
    final hmac = crypto.Hmac(crypto.sha256, keyBytes);
    return hmac.convert(utf8.encode(normalizedValue)).toString();
  }

  /// Creates the canonical metadata representation used as AES-GCM AAD.
  /// Map insertion order is deliberate: both peers must authenticate the same
  /// bytes for the same envelope values.
  static String canonicalMessageMetadata({
    required int version,
    required String type,
    required String id,
    required int timestamp,
  }) {
    return jsonEncode({
      'version': version,
      'type': type,
      'id': id,
      'timestamp': timestamp,
    });
  }

  static List<int> messageMetadataAad({
    required int version,
    required String type,
    required String id,
    required int timestamp,
  }) {
    return utf8.encode(
      canonicalMessageMetadata(
        version: version,
        type: type,
        id: id,
        timestamp: timestamp,
      ),
    );
  }

  // ---- Ed25519 signing ------------------------------------------------

  static final Ed25519 _ed25519 = Ed25519();

  /// Signs [message] with the device's Ed25519 private key.
  /// Returns the signature as a base64 string.
  static Future<String> sign(SimpleKeyPair keyPair, String message) async {
    final signature = await _ed25519.sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  /// Verifies a [signatureBase64] against [message] using [publicKeyBase64].
  static Future<bool> verifySignature({
    required String signatureBase64,
    required String message,
    required String publicKeyBase64,
  }) async {
    try {
      final sigBytes = base64Decode(signatureBase64);
      final pubBytes = base64Decode(publicKeyBase64);
      final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
      final ok = await _ed25519.verify(
        utf8.encode(message),
        signature: Signature(sigBytes, publicKey: publicKey),
      );
      return ok;
    } catch (e) {
      return false;
    }
  }

  /// Generates a random nonce as a base64 string (32 bytes).
  static String generateNonce() {
    return base64Encode(_randomBytes(32));
  }

  /// Reconstructs a SimplePublicKey from a base64 string.
  static SimplePublicKey publicKeyFromBase64(String base64) {
    return SimplePublicKey(base64Decode(base64), type: KeyPairType.ed25519);
  }

  /// Generates a deterministic verification code bound to the pairing
  /// transaction's expected Ed25519 identities.
  static String verificationCodeFromKey(
    String keyBase64,
    String peerId, {
    Iterable<String> expectedPublicKeys = const [],
  }) {
    final keyBytes = base64Decode(keyBase64);
    final identityBytes = utf8.encode(
      jsonEncode({
        'peerId': peerId,
        'publicKeys': expectedPublicKeys.toList()..sort(),
      }),
    );
    final combined = Uint8List(keyBytes.length + identityBytes.length)
      ..setAll(0, keyBytes)
      ..setAll(keyBytes.length, identityBytes);

    final hash = crypto.sha256.convert(combined).bytes;
    final value = (hash[0] << 16) | (hash[1] << 8) | hash[2];
    return (value % 1000000).toString().padLeft(6, '0');
  }
}
