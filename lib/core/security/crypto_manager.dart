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

  /// Derives a key scoped to one authenticated connection. The pairing key
  /// remains a bootstrap secret; application frames use this derived key.
  static Future<SecretKey> deriveSessionKey(
    SecretKey sharedKey,
    String sessionId,
  ) async {
    final sharedBytes = await sharedKey.extractBytes();
    final digest = crypto.Hmac(
      crypto.sha256,
      sharedBytes,
    ).convert(utf8.encode('mirrorline/session/$sessionId'));
    return SecretKey(digest.bytes);
  }

  static Future<String> encrypt(
    SecretKey key,
    String plainText, {
    List<int> aad = const [],
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

  static Future<String?> decrypt(
    SecretKey key,
    String encryptedBase64, {
    List<int> aad = const [],
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

  /// Generates a cryptographically sound 6-digit verification code from a
  /// shared key and peer ID. Used to derive a code for manual verification
  /// during pairing that's deterministic and collision-resistant.
  static String verificationCodeFromKey(String keyBase64, String peerId) {
    final keyBytes = base64Decode(keyBase64);
    final peerBytes = utf8.encode(peerId);
    final combined = Uint8List(keyBytes.length + peerBytes.length)
      ..setAll(0, keyBytes)
      ..setAll(keyBytes.length, peerBytes);

    final hash = crypto.sha256.convert(combined).bytes;
    final value = (hash[0] << 16) | (hash[1] << 8) | hash[2];
    return (value % 1000000).toString().padLeft(6, '0');
  }
}
