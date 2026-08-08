import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/peer.dart';

class PeerDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> insert(Peer peer) async {
    final db = await _database;
    await db.insert('peer', peer.toJson(), conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.update('peer', peer.toJson(), where: 'id = ?', whereArgs: [peer.id]);
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