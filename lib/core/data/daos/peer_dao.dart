import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:sqflite/sqflite.dart';

class PeerDao {
  final AppDatabase _db = AppDatabase.instance;

  PeerDao();

  /// Optional override for tests: when provided, all operations run against
  /// this in-memory database instead of the singleton AppDatabase. See
  /// test/peer_persistence_test.dart.
  @visibleForTesting
  PeerDao.forDatabase(Database db) : _testDb = db;

  Database? _testDb;

  Future<Database> get _database async {
    if (_testDb != null) return _testDb!;
    return _db.database;
  }

  Future<void> insert(Peer peer) async {
    final db = await _database;
    await db.insert(
      'peer',
      peer.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Gets the first peer (legacy compatibility).
  Future<Peer?> getPeer() async {
    final db = await _database;
    final maps = await db.query('peer', orderBy: 'created_at DESC', limit: 1);
    if (maps.isEmpty) return null;
    return Peer.fromJson(maps.first);
  }

  /// Gets all paired peers.
  Future<List<Peer>> getAllPeers() async {
    final db = await _database;
    final maps = await db.query('peer', orderBy: 'created_at DESC');
    return maps.map(Peer.fromJson).toList();
  }

  Future<void> update(Peer peer) async {
    final db = await _database;
    await db.update(
      'peer',
      peer.toJson(),
      where: 'id = ?',
      whereArgs: [peer.id],
    );
  }

  /// Replaces the row keyed by [oldId] with [newPeer], which may have a
  /// different `id` (the primary key). `update()` can't do this since it
  /// filters by the *new* object's id, which won't match any existing row
  /// when the id itself is changing -- it would silently update 0 rows.
  /// Used when pairing completes and this device's peer row switches from
  /// representing itself to representing the newly paired other device.
  Future<void> replaceId(String oldId, Peer newPeer) async {
    final db = await _database;
    await db.transaction((txn) async {
      if (oldId != newPeer.id) {
        await txn.delete('peer', where: 'id = ?', whereArgs: [oldId]);
      }
      await txn.insert(
        'peer',
        newPeer.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('peer', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('peer');
  }
}
