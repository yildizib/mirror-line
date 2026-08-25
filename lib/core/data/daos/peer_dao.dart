import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
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
      await _toStorage(peer),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Gets the first peer (legacy compatibility).
  Future<Peer?> getPeer() async {
    final db = await _database;
    final maps = await db.query('peer', orderBy: 'created_at DESC', limit: 1);
    if (maps.isEmpty) return null;
    return _fromStorage(maps.first);
  }

  /// Gets all paired peers.
  Future<List<Peer>> getAllPeers() async {
    final db = await _database;
    final maps = await db.query('peer', orderBy: 'created_at DESC');
    return Future.wait(maps.map(_fromStorage));
  }

  Future<void> update(Peer peer) async {
    final db = await _database;
    await db.update(
      'peer',
      await _toStorage(peer),
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
    final values = await _toStorage(newPeer);
    await db.transaction((txn) async {
      if (oldId != newPeer.id) {
        await txn.delete('peer', where: 'id = ?', whereArgs: [oldId]);
      }
      await txn.insert(
        'peer',
        values,
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

  Future<Map<String, dynamic>> _toStorage(Peer peer) async {
    final localKey = await KeyStore.ensureLocalDatabaseKey();
    final values = await LocalStorageCrypto.encryptFields(
      localKey,
      peer.toJson(),
      const ['device_name', 'public_key'],
    );
    values['key'] = await LocalStorageCrypto.encrypt(localKey, peer.key);
    return values;
  }

  Future<Peer> _fromStorage(Map<String, Object?> row) async {
    final values = Map<String, dynamic>.from(row);
    final decryptedFields = await LocalStorageCrypto.decryptFields(
      KeyStore.ensureLocalDatabaseKey,
      values,
      const ['device_name', 'public_key'],
    );
    values
      ..clear()
      ..addAll(decryptedFields);
    final storedKey = values['key'] as String;
    if (LocalStorageCrypto.isEncrypted(storedKey)) {
      final localKey = await KeyStore.ensureLocalDatabaseKey();
      final decrypted = await LocalStorageCrypto.decrypt(localKey, storedKey);
      if (decrypted == null) {
        throw StateError('Cannot decrypt the stored peer network key.');
      }
      values['key'] = decrypted;
    }
    return Peer.fromJson(values);
  }
}
