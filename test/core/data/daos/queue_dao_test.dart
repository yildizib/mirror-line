import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('returns decrypted payload while SQLite stores ciphertext', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        singleInstance: false,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    final dao = QueueDao.forDatabase(db);
    const payload = '{"body":"private queue payload"}';

    await dao.insert(
      QueueItem(type: 'sms', payload: payload, createdAt: DateTime.now()),
    );

    final raw = (await db.query('offline_queue')).single;
    final storedPayload = raw['payload']! as String;
    expect(storedPayload, startsWith(LocalStorageCrypto.currentPrefix));
    expect(storedPayload, isNot(contains('private queue payload')));

    final items = await dao.getAll();
    expect(items.single.payload, payload);
    expect(
      await LocalStorageCrypto.decrypt(
        await KeyStore.ensureLocalDatabaseKey(),
        storedPayload,
      ),
      payload,
    );
  });

  test('uses the same local key for repeated queue reads', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        singleInstance: false,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    await db.delete('offline_queue');
    final dao = QueueDao.forDatabase(db);
    final key = await KeyStore.ensureLocalDatabaseKey();

    await dao.insert(
      QueueItem(
        type: 'call',
        payload: 'private call',
        createdAt: DateTime.now(),
      ),
    );

    final first = await dao.getAll();
    final second = await dao.getAll();

    expect(first.single.payload, 'private call');
    expect(second.single.payload, 'private call');
    expect((await key.extractBytes()).length, 32);
  });
}
