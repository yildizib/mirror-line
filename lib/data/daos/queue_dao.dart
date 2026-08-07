import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/queue_item.dart';

class QueueDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(QueueItem item) async {
    final db = await _database;
    await db.insert('offline_queue', item.toJson());
  }

  Future<List<QueueItem>> getAll() async {
    final db = await _database;
    final maps = await db.query('offline_queue', orderBy: 'created_at ASC');
    return maps.map(QueueItem.fromJson).toList();
  }

  Future<void> updateRetryCount(int id, int retryCount) async {
    final db = await _database;
    await db.update(
      'offline_queue',
      {'retry_count': retryCount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('offline_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('offline_queue');
  }
}
