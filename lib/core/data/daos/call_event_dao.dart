import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:sqflite/sqflite.dart';

class CallEventDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(CallEvent event) async {
    final db = await _database;
    await insertOn(db, event);
  }

  Future<void> insertOn(DatabaseExecutor db, CallEvent event) async {
    await db.insert(
      'call_event',
      event.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CallEvent>> getAll() async {
    final db = await _database;
    final maps = await db.query('call_event', orderBy: 'timestamp DESC');
    return maps.map(CallEvent.fromJson).toList();
  }

  Future<List<CallEvent>> getRecent({
    required int limit,
    DateTime? since,
  }) async {
    final db = await _database;
    final where = since != null ? 'timestamp >= ?' : null;
    final whereArgs = since != null ? [since.millisecondsSinceEpoch] : null;
    final maps = await db.query(
      'call_event',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map(CallEvent.fromJson).toList();
  }

  Future<List<CallEvent>> getOlder({
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
      'call_event',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(CallEvent.fromJson).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _database;
    await db.update(
      'call_event',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateDeliveryStatus(String id, String status) async {
    final db = await _database;
    await db.update(
      'call_event',
      {'delivery_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Patches number/contact_name in place (see CallFacade.updateCallerInfo).
  Future<void> updateCallerInfo(
    String id, {
    String? number,
    String? contactName,
  }) async {
    final values = <String, Object?>{};
    if (number != null && number.isNotEmpty) values['number'] = number;
    if (contactName != null && contactName.isNotEmpty) {
      values['contact_name'] = contactName;
    }
    if (values.isEmpty) return;
    final db = await _database;
    await db.update('call_event', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('call_event', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('call_event');
  }
}
