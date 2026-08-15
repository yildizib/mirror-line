import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:sqflite/sqflite.dart';

class SmsMessageDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(SmsMessage message) async {
    final db = await _database;
    await db.insert(
      'sms_message',
      message.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SmsMessage>> getAll() async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    return maps.map(SmsMessage.fromJson).toList();
  }

  Future<List<SmsMessage>> getRecent({
    required int limit,
    DateTime? since,
  }) async {
    final db = await _database;
    final where = since != null ? 'timestamp >= ?' : null;
    final whereArgs = since != null ? [since.millisecondsSinceEpoch] : null;
    final maps = await db.query(
      'sms_message',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map(SmsMessage.fromJson).toList();
  }

  Future<List<SmsMessage>> getOlder({
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
      'sms_message',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(SmsMessage.fromJson).toList();
  }

  Future<List<SmsMessage>> getByThread(String threadId) async {
    final db = await _database;
    final maps = await db.query(
      'sms_message',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'timestamp ASC',
    );
    return maps.map(SmsMessage.fromJson).toList();
  }

  Future<List<SmsMessage>> getRecentByThread({
    required String threadId,
    required int limit,
  }) async {
    final db = await _database;
    final maps = await db.query(
      'sms_message',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    final result = maps.map(SmsMessage.fromJson).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getRecentByAddress({
    required String address,
    required int limit,
  }) async {
    final db = await _database;
    final maps = await db.query(
      'sms_message',
      where: 'address = ?',
      whereArgs: [address],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    final result = maps.map(SmsMessage.fromJson).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getOlderByThread({
    required String threadId,
    required int limit,
    required int offset,
  }) async {
    final db = await _database;
    final maps = await db.query(
      'sms_message',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    final result = maps.map(SmsMessage.fromJson).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getOlderByAddress({
    required String address,
    required int limit,
    required int offset,
  }) async {
    final db = await _database;
    final maps = await db.query(
      'sms_message',
      where: 'address = ?',
      whereArgs: [address],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    final result = maps.map(SmsMessage.fromJson).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _database;
    await db.update(
      'sms_message',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('sms_message', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('sms_message');
  }
}
