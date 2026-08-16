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

  Future<String?> payload(String operationId) async {
    final db = await _database;
    final rows = await db.query(
      'platform_operation',
      columns: ['payload'],
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['payload'] as String;
  }

  /// Advances an operation only from one of [from] states. Terminal states
  /// are consequently monotonic: delayed callbacks cannot overwrite them.
  Future<bool> transition(
    String operationId, {
    required Iterable<String> from,
    required String to,
  }) async {
    final db = await _database;
    return transitionOn(db, operationId, from: from, to: to);
  }

  Future<bool> transitionOn(
    DatabaseExecutor db,
    String operationId, {
    required Iterable<String> from,
    required String to,
  }) async {
    final states = from.toList(growable: false);
    if (states.isEmpty) return false;
    final changed = await db.update(
      'platform_operation',
      {'state': to, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where:
          'operation_id = ? AND state IN (${List.filled(states.length, '?').join(', ')})',
      whereArgs: [operationId, ...states],
    );
    return changed == 1;
  }

  Future<List<PlatformOperation>> list({
    required String kind,
    required Iterable<String> states,
  }) async {
    final db = await _database;
    final requestedStates = states.toList(growable: false);
    if (requestedStates.isEmpty) return [];
    final rows = await db.query(
      'platform_operation',
      where:
          'kind = ? AND state IN (${List.filled(requestedStates.length, '?').join(', ')})',
      whereArgs: [kind, ...requestedStates],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => PlatformOperation(
            id: row['operation_id'] as String,
            kind: row['kind'] as String,
            state: row['state'] as String,
            payload: row['payload'] as String,
          ),
        )
        .toList();
  }

  /// Recovers legacy executions which never reached a platform boundary.
  Future<int> recoverExecuting({String? kind}) async {
    final db = await _database;
    final where = kind == null ? 'state = ?' : 'state = ? AND kind = ?';
    final args = kind == null ? ['executing'] : ['executing', kind];
    return db.update(
      'platform_operation',
      {
        'state': 'received',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: where,
      whereArgs: args,
    );
  }

  /// Marks pre-boundary commands indeterminate when their platform cannot
  /// durably identify whether it accepted the command after a process death.
  Future<int> failReady({required String kind}) async {
    final db = await _database;
    return db.update(
      'platform_operation',
      {'state': 'failed', 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'state = ? AND kind = ?',
      whereArgs: ['ready', kind],
    );
  }
}

class PlatformOperation {
  const PlatformOperation({
    required this.id,
    required this.kind,
    required this.state,
    required this.payload,
  });

  final String id;
  final String kind;
  final String state;
  final String payload;
}
