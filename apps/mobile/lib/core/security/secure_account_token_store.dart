import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mirrorline/features/account/domain/account_models.dart';
import 'package:mirrorline/features/account/facade/account_token_store.dart';

/// Stores only opaque server-issued tokens. Never log values from this store.
class SecureAccountTokenStore implements AccountTokenStore {
  SecureAccountTokenStore({AccountSecureKeyValueStore? storage})
    : _storage =
          storage ??
          _FlutterSecureKeyValueStore(
            const FlutterSecureStorage(aOptions: AndroidOptions()),
          );

  static const _sessionRecordKey = 'account_session_record_v1';
  final AccountSecureKeyValueStore _storage;

  @override
  Future<AccountTokenSet?> read() async {
    final record = await _storage.read(_sessionRecordKey);
    if (record == null) return null;
    try {
      final value = jsonDecode(record);
      if (value is! Map<String, dynamic> || value['version'] != 1) {
        await clear();
        return null;
      }
      final accessToken = value['accessToken'];
      final refreshToken = value['refreshToken'];
      final userId = value['userId'];
      final deviceId = value['deviceId'];
      if (accessToken is! String ||
          refreshToken is! String ||
          userId is! String ||
          deviceId is! String) {
        await clear();
        return null;
      }
      return AccountTokenSet(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
        deviceId: deviceId,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AccountTokenSet tokens) async {
    await _storage.write(
      _sessionRecordKey,
      jsonEncode({
        'version': 1,
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'userId': tokens.userId,
        'deviceId': tokens.deviceId,
      }),
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(_sessionRecordKey);
  }
}

abstract interface class AccountSecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterSecureKeyValueStore implements AccountSecureKeyValueStore {
  _FlutterSecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
