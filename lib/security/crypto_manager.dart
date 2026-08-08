import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoManager {
  static final AesGcm _algorithm = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static SecretKey generateKey() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return SecretKey(bytes);
  }

  static Future<String> encrypt(SecretKey key, String plainText) async {
    final nonceBytes = Uint8List(12);
    for (var i = 0; i < nonceBytes.length; i++) {
      nonceBytes[i] = _random.nextInt(256);
    }

    final secretBox = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: key,
      nonce: nonceBytes,
    );

    final combined = Uint8List(nonceBytes.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    combined.setAll(0, nonceBytes);
    combined.setAll(nonceBytes.length, secretBox.cipherText);
    combined.setAll(nonceBytes.length + secretBox.cipherText.length, secretBox.mac.bytes);

    return base64Encode(combined);
  }

  static Future<String?> decrypt(SecretKey key, String encryptedBase64) async {
    try {
      final combined = base64Decode(encryptedBase64);
      if (combined.length < 28) return null;

      final nonce = combined.sublist(0, 12);
      final macStart = combined.length - 16;
      final cipherText = combined.sublist(12, macStart);
      final macBytes = combined.sublist(macStart);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decrypted = await _algorithm.decrypt(secretBox, secretKey: key);
      return utf8.decode(decrypted);
    } catch (e) {
      return null;
    }
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
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// Reconstructs a SimplePublicKey from a base64 string.
  static SimplePublicKey publicKeyFromBase64(String base64) {
    return SimplePublicKey(base64Decode(base64), type: KeyPairType.ed25519);
  }
}
