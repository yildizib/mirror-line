import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class QueueDao {
  final AppDatabase _db = AppDatabase.instance;
  Database? _testDb;

  @visibleForTesting
  QueueDao.forDatabase(Database db) : _testDb = db;

  QueueDao();

  Future<Database> get _database async => _testDb ?? await _db.database;

  Future<QueueItem> insert(QueueItem item) async {
    final db = await _database;
    return insertOn(db, item);
  }

  Future<QueueItem> insertOn(DatabaseExecutor db, QueueItem item) async {
    final id = await db.insert('outbox', item.toJson());
    return item.copyWith(id: id);
  }

  Future<List<QueueItem>> getAll(String destinationPeerId) async {
    final db = await _database;
    final maps = await db.query(
      'outbox',
      where:
          "destination_peer_id = ? AND status IN ('pending', 'sent') AND "
          '(next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [destinationPeerId, DateTime.now().millisecondsSinceEpoch],
      orderBy: 'created_at ASC',
    );
    return maps.map(QueueItem.fromJson).toList();
  }

  Future<bool> updateRetryCount(int id, int retryCount) async {
    final db = await _database;
    final updated = await db.update(
      'outbox',
      {'attempt_count': retryCount},
      where: "id = ? AND status IN ('pending', 'sent')",
      whereArgs: [id],
    );
    return updated == 1;
  }

  Future<bool> updateRetry(
    int id,
    int retryCount,
    DateTime nextAttemptAt,
  ) async {
    final db = await _database;
    final updated = await db.update(
      'outbox',
      {
        'attempt_count': retryCount,
        'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
      },
      where: "id = ? AND status IN ('pending', 'sent')",
      whereArgs: [id],
    );
    return updated == 1;
  }

  Future<bool> markSent(int id, DateTime nextAttemptAt) async {
    final db = await _database;
    final updated = await db.update(
      'outbox',
      {
        'status': 'sent',
        'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
      },
      where: "id = ? AND status IN ('pending', 'sent')",
      whereArgs: [id],
    );
    return updated == 1;
  }

  Future<bool> markAcknowledged(
    String messageId, {
    String? destinationPeerId,
  }) async {
    final db = await _database;
    final where = StringBuffer(
      "message_id = ? AND status IN ('pending', 'sent')",
    );
    final whereArgs = <Object>[messageId];
    if (destinationPeerId != null) {
      where.write(' AND destination_peer_id = ?');
      whereArgs.add(destinationPeerId);
    }
    final updated = await db.update(
      'outbox',
      {'status': 'completed', 'next_attempt_at': null},
      where: where.toString(),
      whereArgs: whereArgs,
    );
    return updated == 1;
  }

  Future<bool> moveToDeadLetter(int id) async {
    final db = await _database;
    final updated = await db.update(
      'outbox',
      {'status': 'dead_letter', 'next_attempt_at': null},
      where: "id = ? AND status IN ('pending', 'sent')",
      whereArgs: [id],
    );
    return updated == 1;
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('outbox');
  }
}
