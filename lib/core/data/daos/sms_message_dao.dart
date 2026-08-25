import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite/sqflite.dart';

class SmsMessageDao {
  final AppDatabase _db = AppDatabase.instance;
  Database? _testDb;

  SmsMessageDao();

  @visibleForTesting
  SmsMessageDao.forDatabase(Database db) : _testDb = db;

  Future<Database> get _database async => _testDb ?? await _db.database;

  Future<void> insert(SmsMessage message) async {
    final db = await _database;
    final values = await LocalStorageCrypto.encryptFields(
      await KeyStore.ensureLocalDatabaseKey(),
      message.toJson(),
      const ['thread_id', 'address', 'contact_name', 'body'],
    );
    await db.insert(
      'sms_message',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SmsMessage>> getAll() async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    return Future.wait(maps.map(_fromStorage));
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
    return Future.wait(maps.map(_fromStorage));
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
    return Future.wait(maps.map(_fromStorage));
  }

  Future<List<SmsMessage>> getByThread(String threadId) async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp ASC');
    final messages = await Future.wait(maps.map(_fromStorage));
    return messages.where((message) => message.threadId == threadId).toList();
  }

  Future<List<SmsMessage>> getRecentByThread({
    required String threadId,
    required int limit,
  }) async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    final result = (await Future.wait(
      maps.map(_fromStorage),
    )).where((message) => message.threadId == threadId).take(limit).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getRecentByAddress({
    required String address,
    required int limit,
  }) async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    final result = (await Future.wait(
      maps.map(_fromStorage),
    )).where((message) => message.address == address).take(limit).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getOlderByThread({
    required String threadId,
    required int limit,
    required int offset,
  }) async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    final result = (await Future.wait(maps.map(_fromStorage)))
        .where((message) => message.threadId == threadId)
        .skip(offset)
        .take(limit)
        .toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<List<SmsMessage>> getOlderByAddress({
    required String address,
    required int limit,
    required int offset,
  }) async {
    final db = await _database;
    final maps = await db.query('sms_message', orderBy: 'timestamp DESC');
    final result = (await Future.wait(maps.map(_fromStorage)))
        .where((message) => message.address == address)
        .skip(offset)
        .take(limit)
        .toList();
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

  Future<SmsMessage> _fromStorage(Map<String, Object?> row) async {
    final values = await LocalStorageCrypto.decryptFields(
      KeyStore.ensureLocalDatabaseKey,
      Map<String, dynamic>.from(row),
      const ['thread_id', 'address', 'contact_name', 'body'],
    );
    return SmsMessage.fromJson(values);
  }
}
