import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/services/local_storage_migration.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('prepare creates a key and starts in the not-started state', () async {
    final preparation = await LocalStorageMigrationCoordinator().prepare();

    expect(preparation.state, LocalStorageMigrationState.notStarted);
    expect(preparation.checkpoint, isNull);
    expect((await preparation.localKey.extractBytes()).length, 32);
  });

  test('prepare recovers in-progress state and checkpoint', () async {
    final coordinator = LocalStorageMigrationCoordinator();
    await coordinator.prepare();
    await coordinator.begin();
    await coordinator.saveCheckpoint('sms_message:42');

    final resumed = await coordinator.prepare();

    expect(resumed.state, LocalStorageMigrationState.inProgress);
    expect(resumed.checkpoint, 'sms_message:42');
  });

  test('complete stores a terminal state and checkpoint', () async {
    final coordinator = LocalStorageMigrationCoordinator();
    await coordinator.prepare();
    await coordinator.begin();
    await coordinator.complete();

    final preparation = await coordinator.prepare();

    expect(preparation.state, LocalStorageMigrationState.completed);
    expect(preparation.checkpoint, 'complete');
  });

  test('empty checkpoints are rejected', () async {
    final coordinator = LocalStorageMigrationCoordinator();

    expect(() => coordinator.saveCheckpoint(''), throwsArgumentError);
  });

  test('invalid persisted state fails closed', () async {
    FlutterSecureStorage.setMockInitialValues({
      'local_storage_migration_state': 'unknown',
    });

    expect(
      () => LocalStorageMigrationCoordinator().prepare(),
      throwsStateError,
    );
  });

  test('migrates sensitive fields in bounded, repeatable batches', () async {
    final db = await _openDatabase();
    final networkKey = SecretKey(List<int>.generate(32, (index) => index));
    await KeyStore.setPeerKey(networkKey);
    final networkKeyBase64 = base64Encode(await networkKey.extractBytes());
    await _insertLegacyRows(db, networkKeyBase64);

    final coordinator = LocalStorageMigrationCoordinator();
    await coordinator.migrate(db, batchSize: 1);
    final preparation = await coordinator.prepare();
    final rows = await db.query('sms_message');

    expect(preparation.state, LocalStorageMigrationState.completed);
    expect(rows.single['body'], startsWith(LocalStorageCrypto.currentPrefix));
    expect(
      rows.single['address'],
      startsWith(LocalStorageCrypto.currentPrefix),
    );
    expect(
      await LocalStorageCrypto.decrypt(
        preparation.localKey,
        rows.single['body']! as String,
      ),
      'legacy body',
    );

    final ciphertext = rows.single['body'];
    await coordinator.migrate(db, batchSize: 1);
    expect((await db.query('sms_message')).single['body'], ciphertext);
    expect(
      (await db.query('peer')).single['key'],
      startsWith(LocalStorageCrypto.currentPrefix),
    );
  });

  test('resumes from a persisted checkpoint after an interruption', () async {
    final db = await _openDatabase();
    final networkKey = SecretKey(List<int>.generate(32, (index) => index));
    await KeyStore.setPeerKey(networkKey);
    final localKey = await KeyStore.ensureLocalDatabaseKey();
    final encryptedValues = await _encryptedSmsValues(localKey);

    await db.insert('sms_message', {
      'id': 'sms-1',
      ...encryptedValues,
      'encrypted': '',
      'direction': 'incoming',
      'status': 'received',
      'timestamp': 1700000000000,
      'created_at': 1700000000000,
    });
    await db.insert('sms_message', {
      'id': 'sms-2',
      'thread_id': 'thread-2',
      'address': '+905550000002',
      'contact_name': 'Second Sender',
      'body': 'second body',
      'encrypted': '',
      'direction': 'incoming',
      'status': 'received',
      'timestamp': 1700000000001,
      'created_at': 1700000000001,
    });
    await KeyStore.setLocalStorageMigrationState('in_progress');
    await KeyStore.setLocalStorageMigrationCheckpoint(
      jsonEncode({'tableIndex': 2, 'lastId': 'sms-1'}),
    );

    await LocalStorageMigrationCoordinator().migrate(db, batchSize: 1);

    final second = (await db.query(
      'sms_message',
      where: 'id = ?',
      whereArgs: ['sms-2'],
    )).single;
    expect(second['body'], startsWith(LocalStorageCrypto.currentPrefix));
    expect(
      await LocalStorageCrypto.decrypt(localKey, second['body']! as String),
      'second body',
    );
    expect(
      (await LocalStorageMigrationCoordinator().prepare()).state,
      LocalStorageMigrationState.completed,
    );
  });

  test(
    'does not change records when the secure network key is missing',
    () async {
      final db = await _openDatabase();
      await db.insert('peer', {
        'id': 'peer-1',
        'device_name': 'Legacy Device',
        'role': 'main',
        'ip': '192.168.1.10',
        'port': 45678,
        'key': 'legacy-network-key',
        'public_key': 'legacy-public-key',
        'created_at': 1700000000000,
      });

      expect(
        () => LocalStorageMigrationCoordinator().migrate(db),
        throwsStateError,
      );

      final peer = (await db.query('peer')).single;
      expect(peer['device_name'], 'Legacy Device');
      expect(peer['key'], 'legacy-network-key');
    },
  );

  test(
    'rejects corrupt versioned ciphertext without replacing the record',
    () async {
      final db = await _openDatabase();
      final networkKey = SecretKey(List<int>.generate(32, (index) => index));
      await KeyStore.setPeerKey(networkKey);
      await db.insert('sms_message', {
        'id': 'sms-corrupt',
        'thread_id': 'thread-corrupt',
        'address': '+905550000099',
        'contact_name': 'Corrupt Sender',
        'body': '${LocalStorageCrypto.currentPrefix}not-valid-ciphertext',
        'encrypted': '',
        'direction': 'incoming',
        'status': 'received',
        'timestamp': 1700000000000,
        'created_at': 1700000000000,
      });

      expect(
        () => LocalStorageMigrationCoordinator().migrate(db),
        throwsStateError,
      );

      final row = (await db.query('sms_message')).single;
      expect(
        row['body'],
        '${LocalStorageCrypto.currentPrefix}not-valid-ciphertext',
      );
      expect(row['address'], '+905550000099');
    },
  );
}

Future<Database> _openDatabase() {
  return databaseFactory
      .openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          singleInstance: false,
          onCreate: AppDatabase.instance.createTables,
        ),
      )
      .then((db) async {
        for (final table in [
          'peer',
          'call_event',
          'sms_message',
          'notification_event',
          'offline_queue',
        ]) {
          await db.delete(table);
        }
        return db;
      });
}

Future<Map<String, String>> _encryptedSmsValues(SecretKey key) async {
  return {
    'thread_id': await LocalStorageCrypto.encrypt(key, 'thread-1'),
    'address': await LocalStorageCrypto.encrypt(key, '+905550000001'),
    'contact_name': await LocalStorageCrypto.encrypt(key, 'First Sender'),
    'body': await LocalStorageCrypto.encrypt(key, 'first body'),
  };
}

Future<void> _insertLegacyRows(Database db, String networkKeyBase64) async {
  const timestamp = 1700000000000;
  await db.insert('peer', {
    'id': 'peer-1',
    'device_name': 'Legacy Device',
    'role': 'main',
    'ip': '192.168.1.10',
    'port': 45678,
    'key': networkKeyBase64,
    'public_key': 'legacy-public-key',
    'created_at': timestamp,
  });
  await db.insert('call_event', {
    'id': 'call-1',
    'direction': 'incoming',
    'number': '+905551112233',
    'contact_name': 'Legacy Caller',
    'timestamp': timestamp,
    'encrypted': '',
    'status': 'missed',
    'created_at': timestamp,
  });
  await db.insert('sms_message', {
    'id': 'sms-1',
    'thread_id': 'thread-1',
    'address': '+905551112233',
    'contact_name': 'Legacy Sender',
    'body': 'legacy body',
    'encrypted': '',
    'direction': 'incoming',
    'status': 'received',
    'timestamp': timestamp,
    'created_at': timestamp,
  });
  await db.insert('notification_event', {
    'id': 'notification-1',
    'native_id': 'native-1',
    'package_name': 'com.example.legacy',
    'app_name': 'Legacy App',
    'title': 'Legacy title',
    'text': 'Legacy text',
    'encrypted': '',
    'timestamp': timestamp,
    'created_at': timestamp,
  });
  await db.insert('offline_queue', {
    'type': 'sms',
    'payload': '{"body":"legacy body"}',
    'retry_count': 0,
    'created_at': timestamp,
  });
}
