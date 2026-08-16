import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/inbox_record.dart';
import 'package:sqflite/sqflite.dart';

class InboxDao {
  final AppDatabase _db = AppDatabase.instance;
  Database? _testDb;

  InboxDao();

  @visibleForTesting
  InboxDao.forDatabase(Database db) : _testDb = db;

  Future<Database> get _database async => _testDb ?? await _db.database;

  Future<bool> insertIfAbsent(InboxRecord record) async {
    final db = await _database;
    final inserted = await db.insert(
      'inbox',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return inserted != 0;
  }

  Future<InboxRecord?> get(String sourcePeerId, String messageId) async {
    final db = await _database;
    final rows = await db.query(
      'inbox',
      where: 'source_peer_id = ? AND message_id = ?',
      whereArgs: [sourcePeerId, messageId],
      limit: 1,
    );
    return rows.isEmpty ? null : InboxRecord.fromJson(rows.single);
  }

  Future<void> updateState(
    String sourcePeerId,
    String messageId,
    String state,
  ) async {
    final db = await _database;
    await db.update(
      'inbox',
      {
        'processing_state': state,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'source_peer_id = ? AND message_id = ?',
      whereArgs: [sourcePeerId, messageId],
    );
  }

  Future<int> deleteOlderThan(DateTime cutoff) async {
    final db = await _database;
    return db.delete(
      'inbox',
      where: 'updated_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }
}
