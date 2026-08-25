import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite/sqflite.dart';

class CallEventDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(CallEvent event) async {
    final db = await _database;
    final values = await LocalStorageCrypto.encryptFields(
      await KeyStore.ensureLocalDatabaseKey(),
      event.toJson(),
      const ['number', 'contact_name'],
    );
    await db.insert(
      'call_event',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CallEvent>> getAll() async {
    final db = await _database;
    final maps = await db.query('call_event', orderBy: 'timestamp DESC');
    return Future.wait(maps.map(_fromStorage));
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
    return Future.wait(maps.map(_fromStorage));
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
    return Future.wait(maps.map(_fromStorage));
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
    final encrypted = await LocalStorageCrypto.encryptFields(
      await KeyStore.ensureLocalDatabaseKey(),
      values,
      const ['number', 'contact_name'],
    );
    await db.update('call_event', encrypted, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('call_event', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('call_event');
  }

  Future<CallEvent> _fromStorage(Map<String, Object?> row) async {
    final values = await LocalStorageCrypto.decryptFields(
      KeyStore.ensureLocalDatabaseKey,
      Map<String, dynamic>.from(row),
      const ['number', 'contact_name'],
    );
    return CallEvent.fromJson(values);
  }
}
