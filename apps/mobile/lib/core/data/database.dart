import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mirrorline/core/services/local_storage_migration.dart';
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

    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: configureDatabase,
      onCreate: createTables,
      onUpgrade: upgradeTables,
    );
    await LocalStorageMigrationCoordinator().migrate(database);
    return database;
  }

  /// Keeps every database connection consistent with the production setup.
  ///
  /// The timeout and WAL journal mode allow independent readers/writers to
  /// reconcile idempotent admissions rather than leaking transient SQLite
  /// busy errors to sync callers.
  @visibleForTesting
  Future<void> configureDatabase(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA journal_mode = WAL');
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
      final queueTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'offline_queue'",
      );
      if (queueTable.isNotEmpty) {
        await db.execute(
          'ALTER TABLE offline_queue ADD COLUMN dedupe_key TEXT',
        );
      }
    }
    if (oldVersion < 8) await _createSyncPersistenceTables(db);
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
        dedupe_key TEXT,
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
    await _createSyncPersistenceTables(db);
  }

  Future<void> _createSyncPersistenceTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS server_identity (
      user_id TEXT NOT NULL, device_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, device_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS device_key_version (
      user_id TEXT NOT NULL, device_id TEXT NOT NULL, version INTEGER NOT NULL CHECK(version > 0),
      signing_public_key BLOB NOT NULL CHECK(length(signing_public_key) = 32),
      encryption_public_key BLOB NOT NULL CHECK(length(encryption_public_key) = 32),
      fingerprint BLOB NOT NULL CHECK(length(fingerprint) = 32),
      status TEXT NOT NULL CHECK(status IN ('pending','active','retiring','retired','revoked')),
      created_at INTEGER NOT NULL, activated_at INTEGER, retiring_at INTEGER, retired_at INTEGER, revoked_at INTEGER,
      PRIMARY KEY (user_id, device_id, version),
      FOREIGN KEY (user_id, device_id) REFERENCES server_identity(user_id, device_id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS one_active_device_key
      ON device_key_version(user_id, device_id) WHERE status = 'active' ''');
    await db.execute('''CREATE TABLE IF NOT EXISTS mailbox_cursor (
      user_id TEXT NOT NULL, device_id TEXT NOT NULL, cursor TEXT NOT NULL, sequence INTEGER NOT NULL CHECK(sequence >= 0),
      updated_at INTEGER NOT NULL, PRIMARY KEY (user_id, device_id),
      FOREIGN KEY (user_id, device_id) REFERENCES server_identity(user_id, device_id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS relay_envelope (
      id INTEGER PRIMARY KEY AUTOINCREMENT, direction TEXT NOT NULL CHECK(direction IN ('outbox','inbox')),
      message_id TEXT NOT NULL, protocol_version INTEGER NOT NULL CHECK(protocol_version = 1),
      message_type TEXT NOT NULL, sender_user_id TEXT NOT NULL, sender_device_id TEXT NOT NULL,
      recipient_user_id TEXT NOT NULL, recipient_device_id TEXT NOT NULL,
      sender_key_version INTEGER NOT NULL CHECK(sender_key_version > 0),
      recipient_key_version INTEGER NOT NULL CHECK(recipient_key_version > 0),
      nonce BLOB NOT NULL CHECK(length(nonce) = 12), ciphertext BLOB NOT NULL CHECK(length(ciphertext) >= 16),
      signature BLOB NOT NULL CHECK(length(signature) = 64), digest BLOB NOT NULL CHECK(length(digest) = 32),
      accepted_at INTEGER, expires_at INTEGER, acked_at INTEGER,
      replay_recorded_at INTEGER NOT NULL, created_at INTEGER NOT NULL,
      CHECK(sender_user_id = recipient_user_id),
      CHECK((accepted_at IS NULL AND expires_at IS NULL) OR
        (accepted_at IS NOT NULL AND expires_at IS NOT NULL AND
          expires_at = accepted_at + 604800000)),
      UNIQUE(sender_user_id, sender_device_id, message_id)
      ,FOREIGN KEY(sender_user_id, sender_device_id, sender_key_version)
        REFERENCES device_key_version(user_id, device_id, version)
      ,FOREIGN KEY(recipient_user_id, recipient_device_id, recipient_key_version)
        REFERENCES device_key_version(user_id, device_id, version)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS replay_tombstone (
      sender_user_id TEXT NOT NULL, sender_device_id TEXT NOT NULL, message_id TEXT NOT NULL,
      digest BLOB NOT NULL CHECK(length(digest) = 32), accepted_at INTEGER NOT NULL,
      PRIMARY KEY(sender_user_id, sender_device_id, message_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS local_history_policy (
      id INTEGER PRIMARY KEY CHECK(id = 1), retention_days INTEGER NOT NULL DEFAULT 30
      CHECK(retention_days IN (7, 30, 90, 180))
    )''');
    await db.execute(
      'INSERT OR IGNORE INTO local_history_policy(id, retention_days) VALUES (1, 30)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS local_history_entry (
      id INTEGER PRIMARY KEY AUTOINCREMENT, encrypted_payload TEXT NOT NULL, occurred_at INTEGER NOT NULL
    )''');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> reset() async {
    await resetDatabase(await database);
  }

  /// Clears user data and restores the default local-history retention.
  @visibleForTesting
  Future<void> resetDatabase(Database db) => db.transaction((txn) async {
    await txn.delete('relay_envelope');
    await txn.delete('replay_tombstone');
    await txn.delete('mailbox_cursor');
    await txn.delete('device_key_version');
    await txn.delete('server_identity');
    await txn.delete('local_history_entry');
    await txn.update('local_history_policy', {
      'retention_days': 30,
    }, where: 'id = 1');
    await txn.delete('peer');
    await txn.delete('call_event');
    await txn.delete('sms_message');
    await txn.delete('offline_queue');
    await txn.delete('known_network');
    await txn.delete('notification_event');
  });
}
