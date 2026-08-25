import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _peerKeyKey = 'peer_aes_key';
  static const _peerIdKey = 'peer_id';
  static const _localDatabaseKeyKey = 'local_database_key';
  static const _localStorageMigrationStateKey = 'local_storage_migration_state';
  static const _localStorageMigrationCheckpointKey =
      'local_storage_migration_checkpoint';

  // Ed25519 device identity keypair
  static const _devicePrivateKeyKey = 'device_ed25519_private';
  static const _devicePublicKeyKey = 'device_ed25519_public';

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

  /// Returns the key used to protect sensitive values stored locally.
  ///
  /// This key is intentionally separate from [_peerKeyKey]. A peer network
  /// key authenticates one remote device, while this key protects data at rest
  /// on this device and must never be persisted in SQLite.
  static Future<SecretKey?> getLocalDatabaseKey() async {
    final encoded = await _storage.read(key: _localDatabaseKeyKey);
    if (encoded == null) return null;

    final bytes = base64Decode(encoded);
    if (bytes.length != 32) {
      throw StateError('Invalid local database key length.');
    }
    return SecretKey(bytes);
  }

  /// Returns the existing local database key or creates it on first use.
  static Future<SecretKey> ensureLocalDatabaseKey() async {
    final existing = await getLocalDatabaseKey();
    if (existing != null) return existing;

    final key = CryptoManager.generateKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _localDatabaseKeyKey, value: base64Encode(bytes));
    return key;
  }

  static Future<void> clearLocalDatabaseKey() =>
      _storage.delete(key: _localDatabaseKeyKey);

  static Future<String?> getLocalStorageMigrationState() =>
      _storage.read(key: _localStorageMigrationStateKey);

  static Future<void> setLocalStorageMigrationState(String state) =>
      _storage.write(key: _localStorageMigrationStateKey, value: state);

  static Future<String?> getLocalStorageMigrationCheckpoint() =>
      _storage.read(key: _localStorageMigrationCheckpointKey);

  static Future<void> setLocalStorageMigrationCheckpoint(String checkpoint) =>
      _storage.write(
        key: _localStorageMigrationCheckpointKey,
        value: checkpoint,
      );

  static Future<void> clearLocalStorageMigration() async {
    await _storage.delete(key: _localStorageMigrationStateKey);
    await _storage.delete(key: _localStorageMigrationCheckpointKey);
  }

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
      key: _devicePrivateKeyKey,
      value: base64Encode(privBytes),
    );
    await _storage.write(
      key: _devicePublicKeyKey,
      value: base64Encode(pubBytes),
    );

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
    await clearLocalDatabaseKey();
    await clearLocalStorageMigration();
    await clearDeviceKeyPair();
    await clearSelfIdentity();
  }
}
