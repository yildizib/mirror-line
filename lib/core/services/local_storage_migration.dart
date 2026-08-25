import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:sqflite/sqflite.dart';

enum LocalStorageMigrationState { notStarted, inProgress, completed }

class LocalStorageMigrationPreparation {
  final SecretKey localKey;
  final LocalStorageMigrationState state;
  final String? checkpoint;

  const LocalStorageMigrationPreparation({
    required this.localKey,
    required this.state,
    required this.checkpoint,
  });
}

/// Coordinates local-storage key recovery and resumable migration progress.
///
/// Record transformation is intentionally delegated to a later migration
/// task. This service owns only the durable key, phase, and checkpoint state so
/// an interrupted transformation can safely resume.
class LocalStorageMigrationCoordinator {
  static const _notStarted = 'not_started';
  static const _inProgress = 'in_progress';
  static const _completed = 'completed';

  Future<LocalStorageMigrationPreparation> prepare() async {
    final localKey = await KeyStore.ensureLocalDatabaseKey();
    final state = _decodeState(await KeyStore.getLocalStorageMigrationState());
    final checkpoint = await KeyStore.getLocalStorageMigrationCheckpoint();

    return LocalStorageMigrationPreparation(
      localKey: localKey,
      state: state,
      checkpoint: checkpoint,
    );
  }

  Future<void> begin() => KeyStore.setLocalStorageMigrationState(_inProgress);

  Future<void> saveCheckpoint(String checkpoint) async {
    if (checkpoint.isEmpty) {
      throw ArgumentError.value(checkpoint, 'checkpoint');
    }
    await KeyStore.setLocalStorageMigrationCheckpoint(checkpoint);
  }

  Future<void> complete() async {
    await KeyStore.setLocalStorageMigrationState(_completed);
    await KeyStore.setLocalStorageMigrationCheckpoint('complete');
  }

  Future<void> migrate(Database db, {int batchSize = 50}) async {
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize');
    }

    final preparation = await prepare();
    if (preparation.state == LocalStorageMigrationState.completed) return;

    final localKey = preparation.localKey;
    final peerKey = await KeyStore.getPeerKey();
    final authoritativePeerKey = peerKey == null
        ? null
        : base64Encode(await peerKey.extractBytes());
    await begin();
    final checkpoint = _decodeCheckpoint(preparation.checkpoint);

    for (var index = 0; index < _tables.length; index++) {
      final table = _tables[index];
      if (checkpoint != null && index < checkpoint.tableIndex) continue;

      var lastId = checkpoint?.tableIndex == index ? checkpoint!.lastId : null;
      while (true) {
        final rows = await _readBatch(
          db,
          table,
          lastId: lastId,
          batchSize: batchSize,
        );
        if (rows.isEmpty) break;

        await db.transaction((txn) async {
          for (final row in rows) {
            final values = await _encryptedValues(
              row,
              table,
              localKey,
              authoritativePeerKey,
            );
            if (values.isNotEmpty) {
              await txn.update(
                table.name,
                values,
                where: '${table.idColumn} = ?',
                whereArgs: [row[table.idColumn]],
              );
            }
          }
        });

        lastId = rows.last[table.idColumn].toString();
        await saveCheckpoint(
          jsonEncode({'tableIndex': index, 'lastId': lastId}),
        );
      }
    }

    await complete();
  }

  LocalStorageMigrationState _decodeState(String? state) {
    return switch (state) {
      null || _notStarted => LocalStorageMigrationState.notStarted,
      _inProgress => LocalStorageMigrationState.inProgress,
      _completed => LocalStorageMigrationState.completed,
      _ => throw StateError('Invalid local storage migration state.'),
    };
  }

  Future<List<Map<String, Object?>>> _readBatch(
    Database db,
    _MigrationTable table, {
    required String? lastId,
    required int batchSize,
  }) {
    return db.query(
      table.name,
      where: lastId == null ? null : '${table.idColumn} > ?',
      whereArgs: lastId == null ? null : [lastId],
      orderBy: '${table.idColumn} ASC',
      limit: batchSize,
    );
  }

  Future<Map<String, Object?>> _encryptedValues(
    Map<String, Object?> row,
    _MigrationTable table,
    SecretKey key,
    String? authoritativePeerKey,
  ) async {
    final values = <String, Object?>{};
    for (final field in table.fields) {
      final storedValue = row[field] as String;
      final value = table.name == 'peer' && field == 'key'
          ? authoritativePeerKey
          : storedValue;
      if (value == null) {
        throw StateError('Cannot migrate peer key without secure storage.');
      }
      if (value.isEmpty) continue;

      if (LocalStorageCrypto.isEncrypted(storedValue)) {
        final plaintext = await LocalStorageCrypto.decrypt(key, storedValue);
        if (plaintext == null) {
          throw StateError('Cannot verify encrypted value in $field.');
        }
        if (plaintext == value) continue;
      } else if (storedValue == value && table.name != 'peer') {
        // The value is still legacy plaintext and must be replaced below.
      }

      if (LocalStorageCrypto.isEncrypted(storedValue) && table.name != 'peer') {
        continue;
      }

      final encrypted = await LocalStorageCrypto.encrypt(key, value);
      final verified = await LocalStorageCrypto.decrypt(key, encrypted);
      if (verified != value) {
        throw StateError('Cannot verify migrated value in $field.');
      }
      values[field] = encrypted;
    }
    return values;
  }

  _MigrationCheckpoint? _decodeCheckpoint(String? checkpoint) {
    if (checkpoint == null || checkpoint == 'complete') return null;
    try {
      final json = jsonDecode(checkpoint) as Map<String, dynamic>;
      final tableIndex = json['tableIndex'] as int;
      final lastId = json['lastId'] as String;
      if (tableIndex < 0 || tableIndex >= _tables.length || lastId.isEmpty) {
        throw const FormatException();
      }
      return _MigrationCheckpoint(tableIndex, lastId);
    } on FormatException {
      throw StateError('Invalid local storage migration checkpoint.');
    } on TypeError {
      throw StateError('Invalid local storage migration checkpoint.');
    }
  }

  static const _tables = <_MigrationTable>[
    _MigrationTable('peer', 'id', ['device_name', 'public_key', 'key']),
    _MigrationTable('call_event', 'id', ['number', 'contact_name']),
    _MigrationTable('sms_message', 'id', [
      'thread_id',
      'address',
      'contact_name',
      'body',
    ]),
    _MigrationTable('notification_event', 'id', [
      'native_id',
      'package_name',
      'app_name',
      'title',
      'text',
    ]),
    _MigrationTable('offline_queue', 'id', ['payload']),
  ];
}

class _MigrationTable {
  final String name;
  final String idColumn;
  final List<String> fields;

  const _MigrationTable(this.name, this.idColumn, this.fields);
}

class _MigrationCheckpoint {
  final int tableIndex;
  final String lastId;

  const _MigrationCheckpoint(this.tableIndex, this.lastId);
}
