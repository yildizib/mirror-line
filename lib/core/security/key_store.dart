import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _peerKeyKey = 'peer_aes_key';
  static const _peerIdKey = 'peer_id';

  // Ed25519 device identity keypair. A single secure-storage value is an
  // atomic identity snapshot even when another isolate creates it concurrently.
  static const _deviceKeyPairKey = 'device_ed25519';
  static const _devicePrivateKeyKey = 'device_ed25519_private';
  static const _devicePublicKeyKey = 'device_ed25519_public';
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
    final record = await _storage.read(key: _deviceKeyPairKey);
    if (record != null) {
      final stored = await _readDeviceKeyPair();
      if (stored != null) return stored.publicKey;
      throw StateError('Device identity is corrupt');
    }

    final legacy = await _readLegacyDeviceKeyPair();
    if (legacy != null) {
      await _writeDeviceKeyPair(legacy);
      await _deleteLegacyDeviceKeyPair();
      return (await _readDeviceKeyPair())!.publicKey;
    }

    final legacyPrivate = await _storage.read(key: _devicePrivateKeyKey);
    final legacyPublic = await _storage.read(key: _devicePublicKeyKey);
    if (legacyPrivate != null || legacyPublic != null) {
      throw StateError('Device identity is incomplete');
    }

    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    await _writeDeviceKeyPair(
      _DeviceKeyPair(base64Encode(privBytes), base64Encode(pubKey.bytes)),
    );
    // A concurrent worker can replace a complete record, but can never expose
    // a half-written identity. Return the persisted identity, not ours.
    return (await _readDeviceKeyPair())!.publicKey;
  }

  static Future<String?> getDevicePublicKey() async {
    return (await _readDeviceKeyPair())?.publicKey;
  }

  static Future<SimpleKeyPair?> getDeviceKeyPair() async {
    final stored = await _readDeviceKeyPair();
    if (stored == null) return null;
    try {
      return Ed25519().newKeyPairFromSeed(base64Decode(stored.privateKey));
    } catch (_) {
      return null;
    }
  }

  static Future<_DeviceKeyPair?> _readDeviceKeyPair() async {
    final encoded = await _storage.read(key: _deviceKeyPairKey);
    if (encoded == null) return _readLegacyDeviceKeyPair();
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      if (json['version'] != 1 ||
          json['privateKey'] is! String ||
          json['publicKey'] is! String) {
        return null;
      }
      final pair = _DeviceKeyPair(
        json['privateKey'] as String,
        json['publicKey'] as String,
      );
      return await _matchesPublicKey(pair.privateKey, pair.publicKey)
          ? pair
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<_DeviceKeyPair?> _readLegacyDeviceKeyPair() async {
    final privateKey = await _storage.read(key: _devicePrivateKeyKey);
    final publicKey = await _storage.read(key: _devicePublicKeyKey);
    if (privateKey == null || publicKey == null) return null;
    return await _matchesPublicKey(privateKey, publicKey)
        ? _DeviceKeyPair(privateKey, publicKey)
        : null;
  }

  static Future<void> _writeDeviceKeyPair(_DeviceKeyPair pair) {
    return _storage.write(
      key: _deviceKeyPairKey,
      value: jsonEncode({
        'version': 1,
        'privateKey': pair.privateKey,
        'publicKey': pair.publicKey,
      }),
    );
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
    await _storage.delete(key: _deviceKeyPairKey);
    await _deleteLegacyDeviceKeyPair();
  }

  static Future<void> _deleteLegacyDeviceKeyPair() async {
    await _storage.delete(key: _devicePrivateKeyKey);
    await _storage.delete(key: _devicePublicKeyKey);
  }

  static Future<void> clearAll() async {
    await clearPeerId();
    await clearPeerKey();
    await clearDeviceKeyPair();
    await clearSelfIdentity();
  }
}

class _DeviceKeyPair {
  const _DeviceKeyPair(this.privateKey, this.publicKey);

  final String privateKey;
  final String publicKey;
}
