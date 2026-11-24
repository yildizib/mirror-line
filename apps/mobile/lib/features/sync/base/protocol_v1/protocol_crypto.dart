import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'package:mirrorline/features/sync/base/protocol_v1/canonical_json.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_error.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/signed_envelope.dart';

class ProtocolCiphertext {
  const ProtocolCiphertext({required this.ciphertext, required this.tag});

  final Uint8List ciphertext;
  final Uint8List tag;
}

/// Cryptographic primitives for protocol v1 only. Product flows must opt in
/// explicitly; this class does not alter the legacy LAN transport.
class ProtocolCrypto {
  static final _ed25519 = Ed25519();
  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();

  static Future<SignedEnvelope> signEnvelope(
    SignedEnvelope envelope,
    SimpleKeyPair keyPair,
  ) async {
    envelope.validate(requireSignature: false);
    final signature = await _ed25519.sign(
      envelope.signingBytes(),
      keyPair: keyPair,
    );
    return envelope.withSignature(base64Encode(signature.bytes));
  }

  static Future<bool> verifyEnvelope(
    SignedEnvelope envelope,
    SimplePublicKey publicKey,
  ) async {
    try {
      envelope.validate();
      return await _ed25519.verify(
        envelope.signingBytes(),
        signature: Signature(envelope.signatureBytes(), publicKey: publicKey),
      );
    } on ProtocolException {
      return false;
    }
  }

  static Future<SecretKey> x25519SharedSecret(
    SimpleKeyPair localKeyPair,
    SimplePublicKey remotePublicKey,
  ) => _x25519.sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: remotePublicKey,
  );

  /// RFC 5869 HKDF-SHA256. Direction, device identities, their shared
  /// key-version, and message ID bind the AEAD key to one envelope.
  static Future<SecretKey> deriveDirectionalKey({
    required SecretKey sharedSecret,
    required String senderUserId,
    required String senderDeviceId,
    required String recipientUserId,
    required String recipientDeviceId,
    required int senderKeyVersion,
    required int recipientKeyVersion,
    required String messageId,
  }) async {
    final input = await sharedSecret.extractBytes();
    if (input.length != 32) {
      throw const ProtocolException(
        ProtocolErrorCode.malformedInput,
        'X25519 shared secrets must be 32 bytes.',
      );
    }
    final info =
        utf8.encode('mirrorline.envelope.v1.hkdf\u0000') +
        CanonicalJson.utf8Bytes({
          'messageId': messageId,
          'recipientDeviceId': recipientDeviceId,
          'recipientKeyVersion': recipientKeyVersion,
          'recipientUserId': recipientUserId,
          'senderDeviceId': senderDeviceId,
          'senderKeyVersion': senderKeyVersion,
          'senderUserId': senderUserId,
        });
    final extract = crypto.Hmac(crypto.sha256, List<int>.filled(32, 0));
    final prk = extract.convert(input).bytes;
    final expanded = crypto.Hmac(
      crypto.sha256,
      prk,
    ).convert([...info, 1]).bytes;
    return SecretKey(expanded.sublist(0, 32));
  }

  static Future<ProtocolCiphertext> encryptAesGcm({
    required SecretKey key,
    required List<int> plaintext,
    required SignedEnvelope envelope,
  }) async {
    envelope.validate(requireSignature: false);
    final aesKey = await _aes256Key(key);
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: aesKey,
      nonce: envelope.nonceBytes(),
      aad: envelope.authenticatedMetadataBytes(),
    );
    return ProtocolCiphertext(
      ciphertext: Uint8List.fromList(box.cipherText),
      tag: Uint8List.fromList(box.mac.bytes),
    );
  }

  static Future<Uint8List> decryptAesGcm({
    required SecretKey key,
    required SignedEnvelope envelope,
  }) async {
    try {
      envelope.validate();
      final aesKey = await _aes256Key(key);
      final joined = envelope.ciphertextBytes();
      if (joined.length < 16) {
        throw const ProtocolException(
          ProtocolErrorCode.malformedInput,
          'Ciphertext is missing an authentication tag.',
        );
      }
      final split = joined.length - 16;
      final plaintext = await _aesGcm.decrypt(
        SecretBox(
          joined.sublist(0, split),
          nonce: envelope.nonceBytes(),
          mac: Mac(joined.sublist(split)),
        ),
        secretKey: aesKey,
        aad: envelope.authenticatedMetadataBytes(),
      );
      return Uint8List.fromList(plaintext);
    } on ProtocolException {
      rethrow;
    } catch (_) {
      throw const ProtocolException(
        ProtocolErrorCode.authenticationFailed,
        'Envelope authentication failed.',
      );
    }
  }

  static List<int> pairingTranscriptBytes(Map<String, Object?> payload) =>
      _domainSeparatedBytes('mirrorline.pairing.v1', payload);

  static List<int> keyRotationPayloadBytes(Map<String, Object?> payload) =>
      _domainSeparatedBytes('mirrorline.key-rotation.v1', payload);

  static List<int> _domainSeparatedBytes(
    String domain,
    Map<String, Object?> payload,
  ) => [...utf8.encode(domain), 0, ...CanonicalJson.utf8Bytes(payload)];

  static Future<SecretKey> _aes256Key(SecretKey key) async {
    final bytes = await key.extractBytes();
    if (bytes.length != 32) {
      throw const ProtocolException(
        ProtocolErrorCode.malformedInput,
        'AES-256 requires a 32-byte key.',
      );
    }
    return SecretKey(bytes);
  }
}
