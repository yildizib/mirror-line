import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/sms_message.dart';

class SmsMessageDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(SmsMessage message) async {
    final db = await _database;
    await db.insert('sms_message', message.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SmsMessage>> getAll() async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
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

  Future<void> updateStatus(String id, String status) async {
    final db = await _database;
    await db.update('sms_message', {'status': status}, where: 'id = ?', whereArgs: [id]);
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
