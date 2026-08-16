import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/inbox_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/inbox_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late InboxDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    dao = InboxDao.forDatabase(db);
  });

  tearDown(() => db.close());

  test('insertIfAbsent deduplicates by source peer and message ID', () async {
    final record = InboxRecord(
      sourcePeerId: 'peer-a',
      messageId: 'message-a',
      type: 'sms',
      receivedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    expect(await dao.insertIfAbsent(record), isTrue);
    expect(await dao.insertIfAbsent(record), isFalse);
    expect(await dao.get('peer-a', 'message-a'), isNotNull);
  });

  test('state updates and retention cleanup are durable', () async {
    final record = InboxRecord(
      sourcePeerId: 'peer-a',
      messageId: 'message-a',
      type: 'sms',
      receivedAt: DateTime(2020),
      updatedAt: DateTime(2020),
    );
    await dao.insertIfAbsent(record);
    await dao.updateState('peer-a', 'message-a', 'processed');

    expect(
      (await dao.get('peer-a', 'message-a'))!.processingState,
      'processed',
    );
    expect(await dao.deleteOlderThan(DateTime(2027)), 1);
    expect(await dao.get('peer-a', 'message-a'), isNull);
  });
}
