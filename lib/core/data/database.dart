import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  static Database? _database;
  static const int schemaVersion = 8;

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
  Future<void> upgradeTables(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE peer ADD COLUMN device_name TEXT NOT NULL DEFAULT "";',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE peer ADD COLUMN public_key TEXT NOT NULL DEFAULT "";',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE call_event ADD COLUMN contact_name TEXT NOT NULL DEFAULT "";',
      );
      await db.execute(
        'ALTER TABLE sms_message ADD COLUMN contact_name TEXT NOT NULL DEFAULT "";',
      );
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
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE notification_event (
          id TEXT PRIMARY KEY,
          native_id TEXT NOT NULL,
          package_name TEXT NOT NULL,
          app_name TEXT NOT NULL DEFAULT "",
          title TEXT NOT NULL DEFAULT "",
          text TEXT NOT NULL DEFAULT "",
          encrypted TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE call_event ADD COLUMN delivery_status TEXT NOT NULL DEFAULT "none";',
      );
      await db.execute(
        'ALTER TABLE sms_message ADD COLUMN delivery_status TEXT NOT NULL DEFAULT "none";',
      );
      await db.execute('''
        DELETE FROM notification_event
        WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM notification_event
          GROUP BY package_name, native_id
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS notification_event_source_key '
        'ON notification_event(package_name, native_id);',
      );
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE outbox (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id TEXT NOT NULL UNIQUE,
          destination_peer_id TEXT NOT NULL,
          type TEXT NOT NULL,
          payload TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT "pending",
          attempt_count INTEGER NOT NULL DEFAULT 0,
          next_attempt_at INTEGER,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE offline_queue_quarantine (
          id INTEGER PRIMARY KEY,
          type TEXT NOT NULL,
          payload TEXT NOT NULL,
          retry_count INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          reason TEXT NOT NULL
        )
      ''');
      final legacyQueue = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'offline_queue'",
      );
      if (legacyQueue.isNotEmpty) {
        await db.execute('''
          INSERT INTO outbox
            (message_id, destination_peer_id, type, payload, attempt_count,
             created_at)
          SELECT 'legacy-' || id, (SELECT id FROM peer LIMIT 1), type, payload,
            retry_count, created_at
          FROM offline_queue
          WHERE EXISTS (SELECT 1 FROM peer)
        ''');
        await db.execute('''
          INSERT INTO offline_queue_quarantine
            (id, type, payload, retry_count, created_at, reason)
          SELECT id, type, payload, retry_count, created_at,
            'No destination peer was available during migration'
          FROM offline_queue
          WHERE NOT EXISTS (SELECT 1 FROM peer)
        ''');
        await db.execute('DROP TABLE offline_queue');
      }
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
        delivery_status TEXT NOT NULL DEFAULT "none",
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
        delivery_status TEXT NOT NULL DEFAULT "none",
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL UNIQUE,
        destination_peer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT "pending",
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER,
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

    await db.execute('''
      CREATE TABLE notification_event (
        id TEXT PRIMARY KEY,
        native_id TEXT NOT NULL,
        package_name TEXT NOT NULL,
        app_name TEXT NOT NULL DEFAULT "",
        title TEXT NOT NULL DEFAULT "",
        text TEXT NOT NULL DEFAULT "",
        encrypted TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX notification_event_source_key '
      'ON notification_event(package_name, native_id)',
    );
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
    await db.delete('outbox');
    await db.delete('known_network');
    await db.delete('notification_event');
  }
}
