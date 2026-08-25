import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite/sqflite.dart';

class NotificationEventDao {
  final AppDatabase _db = AppDatabase.instance;
  Database? _testDb;

  NotificationEventDao();

  @visibleForTesting
  NotificationEventDao.forDatabase(Database db) : _testDb = db;

  Future<Database> get _database async => _testDb ?? await _db.database;

  Future<void> insert(NotificationEvent event) async {
    final db = await _database;
    final values = await LocalStorageCrypto.encryptFields(
      await KeyStore.ensureLocalDatabaseKey(),
      event.toJson(),
      const ['native_id', 'package_name', 'app_name', 'title', 'text'],
    );
    await db.insert(
      'notification_event',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationEvent>> getAll() async {
    final db = await _database;
    final maps = await db.query(
      'notification_event',
      orderBy: 'timestamp DESC',
    );
    return Future.wait(maps.map(_fromStorage));
  }

  Future<List<NotificationEvent>> getRecent({
    required int limit,
    DateTime? since,
  }) async {
    final db = await _database;
    String? where;
    List<Object>? whereArgs;
    if (since != null) {
      where = 'timestamp >= ?';
      whereArgs = [since.millisecondsSinceEpoch];
    }
    final maps = await db.query(
      'notification_event',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return Future.wait(maps.map(_fromStorage));
  }

  Future<List<NotificationEvent>> getOlder({
    required int limit,
    required int offset,
    DateTime? before,
  }) async {
    final db = await _database;
    String? where;
    List<Object>? whereArgs;
    if (before != null) {
      where = 'timestamp < ?';
      whereArgs = [before.millisecondsSinceEpoch];
    }
    final maps = await db.query(
      'notification_event',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return Future.wait(maps.map(_fromStorage));
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('notification_event', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes by the native (source-device) key rather than our own [id] --
  /// used for dismissal sync, where the peer message only carries
  /// packageName/nativeId, not our locally-generated id.
  Future<void> deleteByNativeId(String packageName, String nativeId) async {
    final db = await _database;
    final rows = await db.query('notification_event');
    final events = await Future.wait(rows.map(_fromStorage));
    for (final event in events.where(
      (event) => event.packageName == packageName && event.nativeId == nativeId,
    )) {
      await db.delete(
        'notification_event',
        where: 'id = ?',
        whereArgs: [event.id],
      );
    }
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('notification_event');
  }

  Future<NotificationEvent> _fromStorage(Map<String, Object?> row) async {
    final values = await LocalStorageCrypto.decryptFields(
      KeyStore.ensureLocalDatabaseKey,
      Map<String, dynamic>.from(row),
      const ['native_id', 'package_name', 'app_name', 'title', 'text'],
    );
    return NotificationEvent.fromJson(values);
  }
}
