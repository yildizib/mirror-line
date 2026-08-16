import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _peerKeyKey = 'peer_aes_key';
  static const _peerIdKey = 'peer_id';

  // Ed25519 device identity keypair
  static const _devicePrivateKeyKey = 'device_ed25519_private';
  static const _devicePublicKeyKey = 'device_ed25519_public';
  static const _deviceKeyPairPendingKey = 'device_ed25519_pending';
  static Future<String>? _ensureDeviceKeyPairInFlight;

  // This device's own identity (id + display name), set once at role
  // selection time and never overwritten by pairing. The `peer` table row
  // is repurposed by pairing to represent the *other* device, so anything
  // that needs to know "who am I" (e.g. the beacon broadcaster advertising
  // itself, or the Settings "Bu Cihaz" card) must read from here instead.
  static const _selfIdKey = 'self_peer_id';
  static const _selfDeviceNameKey = 'self_device_name';

  static Future<String?> getPeerId() => _storage.read(key: _peerIdKey);

  static Future<void> setPeerId(String id) =>
      _storage.write(key: _peerIdKey, value: id);

  static Future<void> clearPeerId() => _storage.delete(key: _peerIdKey);

  static Future<void> setSelfIdentity({
    required String id,
    required String deviceName,
  }) async {
    await _storage.write(key: _selfIdKey, value: id);
    await _storage.write(key: _selfDeviceNameKey, value: deviceName);
  }

  static Future<String?> getSelfId() => _storage.read(key: _selfIdKey);

  static Future<String?> getSelfDeviceName() =>
      _storage.read(key: _selfDeviceNameKey);

  static Future<void> clearSelfIdentity() async {
    await _storage.delete(key: _selfIdKey);
    await _storage.delete(key: _selfDeviceNameKey);
  }

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
    final running = _ensureDeviceKeyPairInFlight;
    if (running != null) return running;

    final future = _ensureDeviceKeyPair();
    _ensureDeviceKeyPairInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_ensureDeviceKeyPairInFlight, future)) {
        _ensureDeviceKeyPairInFlight = null;
      }
    }
  }

  static Future<String> _ensureDeviceKeyPair() async {
    final publicB64 = await _storage.read(key: _devicePublicKeyKey);
    final privateB64 = await _storage.read(key: _devicePrivateKeyKey);
    final pending = await _storage.read(key: _deviceKeyPairPendingKey);
    if (pending != null ||
        publicB64 == null ||
        privateB64 == null ||
        !await _matchesPublicKey(privateB64, publicB64)) {
      await clearDeviceKeyPair();
    } else {
      return publicB64;
    }

    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubBytes = pubKey.bytes;

    // Secure storage has no transaction primitive. The marker makes a
    // partially written pair observable and therefore never usable.
    await _storage.write(key: _deviceKeyPairPendingKey, value: '1');
    await _storage.write(
      key: _devicePrivateKeyKey,
      value: base64Encode(privBytes),
    );
    await _storage.write(
      key: _devicePublicKeyKey,
      value: base64Encode(pubBytes),
    );
    await _storage.delete(key: _deviceKeyPairPendingKey);

    return base64Encode(pubBytes);
  }

  static Future<String?> getDevicePublicKey() async {
    if (await _storage.read(key: _deviceKeyPairPendingKey) != null) {
      return null;
    }
    final publicB64 = await _storage.read(key: _devicePublicKeyKey);
    final privateB64 = await _storage.read(key: _devicePrivateKeyKey);
    if (publicB64 == null || privateB64 == null) return null;
    return await _matchesPublicKey(privateB64, publicB64) ? publicB64 : null;
  }

  static Future<SimpleKeyPair?> getDeviceKeyPair() async {
    if (await _storage.read(key: _deviceKeyPairPendingKey) != null) {
      return null;
    }
    final privB64 = await _storage.read(key: _devicePrivateKeyKey);
    final pubB64 = await _storage.read(key: _devicePublicKeyKey);
    if (privB64 == null || pubB64 == null) return null;
    if (!await _matchesPublicKey(privB64, pubB64)) return null;
    try {
      final privBytes = base64Decode(privB64);
      return Ed25519().newKeyPairFromSeed(privBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _matchesPublicKey(
    String privateB64,
    String publicB64,
  ) async {
    try {
      final keyPair = await Ed25519().newKeyPairFromSeed(
        base64Decode(privateB64),
      );
      final derived = await keyPair.extractPublicKey();
      return base64Encode(derived.bytes) == publicB64;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearDeviceKeyPair() async {
    await _storage.delete(key: _devicePrivateKeyKey);
    await _storage.delete(key: _devicePublicKeyKey);
    await _storage.delete(key: _deviceKeyPairPendingKey);
  }

  static Future<void> clearAll() async {
    await clearPeerId();
    await clearPeerKey();
    await clearDeviceKeyPair();
    await clearSelfIdentity();
  }
}
