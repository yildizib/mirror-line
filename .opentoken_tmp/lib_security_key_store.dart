import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static const _peerKeyKey = 'peer_aes_key';
  static const _peerIdKey = 'peer_id';

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

  static Future<void> clearAll() async {
    await clearPeerId();
    await clearPeerKey();
  }
}
