import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:sqflite/sqflite.dart';

class QueueDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<QueueItem> insert(QueueItem item) async {
    final db = await _database;
    final id = await db.insert('outbox', item.toJson());
    return item.copyWith(id: id);
  }

  Future<List<QueueItem>> getAll(String destinationPeerId) async {
    final db = await _database;
    final maps = await db.query(
      'outbox',
      where:
          'destination_peer_id = ? AND status = ? AND '
          '(next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [
        destinationPeerId,
        'pending',
        DateTime.now().millisecondsSinceEpoch,
      ],
      orderBy: 'created_at ASC',
    );
    return maps.map(QueueItem.fromJson).toList();
  }

  Future<void> updateRetryCount(int id, int retryCount) async {
    final db = await _database;
    await db.update(
      'outbox',
      {'attempt_count': retryCount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatus(int id, String status) async {
    final db = await _database;
    await db.update(
      'outbox',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
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
