import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static const _peerKeyKey = 'peer_aes_key';
  static const _peerIdKey = 'peer_id';

  // Ed25519 device identity keypair
  static const _devicePrivateKeyKey = 'device_ed25519_private';
  static const _devicePublicKeyKey = 'device_ed25519_public';

  static Future<String?> getPeerId() => _storage.read(key: _peerIdKey);

  static Future<void> setPeerId(String id) =>
      _storage.write(key: _peerIdKey, value: id);

  static Future<void> clearPeerId() => _storage.delete(key: _peerIdKey);

  static Future<SecretKey?> getPeerKey() async {
    final encoded = await _storage.read(key: _peerKeyKey);
    if (encoded == null) return null;
    final bytes = base64Decode(encoded);
    return SecretKey(bytes);
  }

  static Future<void> setPeerKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    await _storage.write(key: _peerKeyKey, value: base64Encode(bytes));
  }

  static Future<void> clearPeerKey() => _storage.delete(key: _peerKeyKey);

  // ---- Ed25519 device identity -----------------------------------------

  /// Generates a new Ed25519 keypair and stores it. Returns the public key
  /// as a base64 string. If a keypair already exists, it is returned without
  /// regeneration.
  static Future<String> ensureDeviceKeyPair() async {
    final existing = await getDevicePublicKey();
    if (existing != null) return existing;

    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubBytes = pubKey.bytes;

    await _storage.write(
        key: _devicePrivateKeyKey, value: base64Encode(privBytes));
    await _storage.write(
        key: _devicePublicKeyKey, value: base64Encode(pubBytes));

    return base64Encode(pubBytes);
  }

  static Future<String?> getDevicePublicKey() async {
    return _storage.read(key: _devicePublicKeyKey);
  }

  static Future<SimpleKeyPair?> getDeviceKeyPair() async {
    final privB64 = await _storage.read(key: _devicePrivateKeyKey);
    if (privB64 == null) return null;
    final privBytes = base64Decode(privB64);
    // Reconstruct a SimpleKeyPair from the private key bytes.
    final algorithm = Ed25519();
    return algorithm.newKeyPairFromSeed(privBytes);
  }

  static Future<void> clearDeviceKeyPair() async {
    await _storage.delete(key: _devicePrivateKeyKey);
    await _storage.delete(key: _devicePublicKeyKey);
  }

  static Future<void> clearAll() async {
    await clearPeerId();
    await clearPeerKey();
    await clearDeviceKeyPair();
  }
}
