import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:sqflite/sqflite.dart';

class PlatformOperationDao {
  final AppDatabase _db = AppDatabase.instance;
  Database? _testDb;

  PlatformOperationDao();

  @visibleForTesting
  PlatformOperationDao.forDatabase(Database db) : _testDb = db;

  Future<Database> get _database async => _testDb ?? await _db.database;

  Future<bool> claim({
    required String operationId,
    required String kind,
    required String payload,
  }) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rowId = await db.insert('platform_operation', {
      'operation_id': operationId,
      'kind': kind,
      'state': 'received',
      'payload': payload,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return rowId != 0;
  }

  Future<bool> claimOn(
    DatabaseExecutor db, {
    required String operationId,
    required String kind,
    required String payload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rowId = await db.insert('platform_operation', {
      'operation_id': operationId,
      'kind': kind,
      'state': 'received',
      'payload': payload,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return rowId != 0;
  }

  Future<String?> state(String operationId) async {
    final db = await _database;
    return stateOn(db, operationId);
  }

  Future<String?> stateOn(DatabaseExecutor db, String operationId) async {
    final rows = await db.query(
      'platform_operation',
      columns: ['state'],
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['state'] as String;
  }

  Future<void> updateState(String operationId, String state) async {
    final db = await _database;
    await db.update(
      'platform_operation',
      {'state': state, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> updateStateOn(
    DatabaseExecutor db,
    String operationId,
    String state,
  ) async {
    await db.update(
      'platform_operation',
      {'state': state, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }
}
