import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:sqflite/sqflite.dart';

class NotificationEventDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(NotificationEvent event) async {
    final db = await _database;
    await db.insert(
      'notification_event',
      event.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationEvent>> getAll() async {
    final db = await _database;
    final maps = await db.query(
      'notification_event',
      orderBy: 'timestamp DESC',
    );
    return maps.map(NotificationEvent.fromJson).toList();
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
    return maps.map(NotificationEvent.fromJson).toList();
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
    return maps.map(NotificationEvent.fromJson).toList();
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
    await db.delete(
      'notification_event',
      where: 'package_name = ? AND native_id = ?',
      whereArgs: [packageName, nativeId],
    );
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('notification_event');
  }
}
