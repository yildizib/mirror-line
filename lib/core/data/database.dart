import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  static Database? _database;
  static const int schemaVersion = 5;

  AppDatabase._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'mirrorline.db');

    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: createTables,
      onUpgrade: upgradeTables,
    );
  }

  /// Exposed (not private) so migration tests can exercise the exact same
  /// upgrade path a real device would go through -- see
  /// test/database_migration_test.dart.
  @visibleForTesting
  Future<void> upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE peer ADD COLUMN device_name TEXT NOT NULL DEFAULT "";');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE peer ADD COLUMN public_key TEXT NOT NULL DEFAULT "";');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE call_event ADD COLUMN contact_name TEXT NOT NULL DEFAULT "";');
      await db.execute('ALTER TABLE sms_message ADD COLUMN contact_name TEXT NOT NULL DEFAULT "";');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE known_network (
          peer_id TEXT NOT NULL,
          subnet_prefix TEXT NOT NULL,
          ip TEXT NOT NULL,
          port INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL,
          PRIMARY KEY (peer_id, subnet_prefix)
        )
      ''');
    }
  }

  /// Exposed (not private) so tests can create a fresh-install schema
  /// directly -- see test/database_migration_test.dart.
  @visibleForTesting
  Future<void> createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE peer (
        id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL DEFAULT "",
        role TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        key TEXT NOT NULL,
        public_key TEXT NOT NULL DEFAULT "",
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE call_event (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        number TEXT NOT NULL,
        contact_name TEXT NOT NULL DEFAULT "",
        timestamp INTEGER NOT NULL,
        encrypted TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sms_message (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        address TEXT NOT NULL,
        contact_name TEXT NOT NULL DEFAULT "",
        body TEXT NOT NULL,
        encrypted TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE known_network (
        peer_id TEXT NOT NULL,
        subnet_prefix TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        PRIMARY KEY (peer_id, subnet_prefix)
      )
    ''');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> reset() async {
    final db = await database;
    await db.delete('peer');
    await db.delete('call_event');
    await db.delete('sms_message');
    await db.delete('offline_queue');
    await db.delete('known_network');
  }
}
