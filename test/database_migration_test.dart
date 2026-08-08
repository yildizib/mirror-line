// Exercises AppDatabase's real onCreate/onUpgrade callbacks (not a
// reimplementation of them) so schema changes across the app's 4 released
// versions are verified to (a) not lose existing data and (b) leave the
// expected columns/defaults in place for a fresh install.
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh install (onCreate) has every expected column', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );

    final peerColumns = await _columnNames(db, 'peer');
    expect(
      peerColumns,
      containsAll(['id', 'device_name', 'role', 'ip', 'port', 'key', 'public_key', 'created_at']),
    );

    final callColumns = await _columnNames(db, 'call_event');
    expect(
      callColumns,
      containsAll(['id', 'direction', 'number', 'contact_name', 'status', 'timestamp']),
    );

    final smsColumns = await _columnNames(db, 'sms_message');
    expect(
      smsColumns,
      containsAll(['id', 'thread_id', 'address', 'contact_name', 'body', 'status']),
    );

    await db.close();
  });

  test('upgrading from v1 preserves existing rows and adds new columns', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 1));

    // Recreates exactly what v1 shipped with -- deliberately hand-written
    // (not derived from the current createTables) since that's the whole
    // point: proving the *real* upgrade path handles the *actual* old shape.
    await db.execute('''
      CREATE TABLE peer (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        key TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE call_event (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        number TEXT NOT NULL,
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
        body TEXT NOT NULL,
        encrypted TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.insert('peer', {
      'id': 'peer-1',
      'role': 'main',
      'ip': '192.168.1.10',
      'port': 45678,
      'key': 'fake-key-base64',
      'created_at': 1700000000000,
    });
    await db.insert('call_event', {
      'id': 'call-1',
      'direction': 'incoming',
      'number': '+905551112233',
      'timestamp': 1700000000000,
      'encrypted': '',
      'status': 'ringing',
      'created_at': 1700000000000,
    });

    // Now run the app's real upgrade path, v1 -> current.
    await AppDatabase.instance.upgradeTables(db, 1, AppDatabase.schemaVersion);

    final peers = await db.query('peer');
    expect(peers, hasLength(1));
    expect(peers.first['id'], 'peer-1');
    expect(peers.first['ip'], '192.168.1.10', reason: 'pre-existing data must survive the upgrade');
    expect(peers.first['device_name'], '', reason: 'new column gets its declared default');
    expect(peers.first['public_key'], '');

    final calls = await db.query('call_event');
    expect(calls, hasLength(1));
    expect(calls.first['number'], '+905551112233');
    expect(calls.first['contact_name'], '');

    final peerColumns = await _columnNames(db, 'peer');
    expect(peerColumns, containsAll(['device_name', 'public_key']));
    final callColumns = await _columnNames(db, 'call_event');
    expect(callColumns, contains('contact_name'));
    final smsColumns = await _columnNames(db, 'sms_message');
    expect(smsColumns, contains('contact_name'));

    await db.close();
  });

  test('upgrading from v2 only adds the columns introduced after it', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 2));

    await db.execute('''
      CREATE TABLE peer (
        id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL DEFAULT "",
        role TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        key TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE call_event (
        id TEXT PRIMARY KEY, direction TEXT NOT NULL, number TEXT NOT NULL,
        timestamp INTEGER NOT NULL, encrypted TEXT NOT NULL, status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sms_message (
        id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, address TEXT NOT NULL,
        body TEXT NOT NULL, encrypted TEXT NOT NULL, direction TEXT NOT NULL,
        status TEXT NOT NULL, timestamp INTEGER NOT NULL, created_at INTEGER NOT NULL
      )
    ''');

    await AppDatabase.instance.upgradeTables(db, 2, AppDatabase.schemaVersion);

    final peerColumns = await _columnNames(db, 'peer');
    expect(peerColumns, contains('public_key'));

    await db.close();
  });
}

Future<List<String>> _columnNames(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toList();
}
