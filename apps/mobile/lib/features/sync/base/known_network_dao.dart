import 'package:mirrorline/core/data/database.dart';
import 'package:sqflite/sqflite.dart';

/// Reconnect fast-path cache: remembers which IP last worked for a given
/// peer on a given subnet (see subnetPrefixOf in subnet_scanner.dart), so
/// returning to a previously-seen network (home, office, a regular café)
/// can skip straight to a direct connect attempt instead of waiting on
/// beacon/subnet-scan discovery. A wrong/stale entry is harmless: it just
/// fails SocketManager.connect's existing timeout, after which the normal
/// discovery fallback runs exactly as if there had been no cache hit.
class KnownNetworkDao {
  final AppDatabase _db = AppDatabase.instance;

  Future<Database> get _database => _db.database;

  Future<void> recordSuccess({
    required String peerId,
    required String subnetPrefix,
    required String ip,
    required int port,
  }) async {
    final db = await _database;
    await db.insert('known_network', {
      'peer_id': peerId,
      'subnet_prefix': subnetPrefix,
      'ip': ip,
      'port': port,
      'last_seen_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> lookupIp({
    required String peerId,
    required String subnetPrefix,
  }) async {
    final db = await _database;
    final maps = await db.query(
      'known_network',
      where: 'peer_id = ? AND subnet_prefix = ?',
      whereArgs: [peerId, subnetPrefix],
    );
    if (maps.isEmpty) return null;
    return maps.first['ip'] as String;
  }
}
