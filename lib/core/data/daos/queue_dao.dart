import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite/sqflite.dart';

class QueueDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(QueueItem item) async {
    final db = await _database;
    final values = await LocalStorageCrypto.encryptFields(
      await KeyStore.ensureLocalDatabaseKey(),
      item.toJson(),
      const ['payload'],
    );
    await db.insert('offline_queue', values);
  }

  Future<List<QueueItem>> getAll() async {
    final db = await _database;
    final maps = await db.query('offline_queue', orderBy: 'created_at ASC');
    return Future.wait(maps.map(_fromStorage));
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

  Future<QueueItem> _fromStorage(Map<String, Object?> row) async {
    final values = await LocalStorageCrypto.decryptFields(
      KeyStore.ensureLocalDatabaseKey,
      Map<String, dynamic>.from(row),
      const ['payload'],
    );
    return QueueItem.fromJson(values);
  }
}
