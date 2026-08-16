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

  test('state updates and seven-day retention cleanup are durable', () async {
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
    expect(
      await dao.deleteExpired(now: DateTime(2027)),
      1,
      reason: 'expired Inbox records cannot outlive sender retries',
    );
    expect(await dao.get('peer-a', 'message-a'), isNull);
  });

  test('retention keeps records newer than the documented policy', () async {
    final now = DateTime(2027, 1, 8);
    final retained = InboxRecord(
      sourcePeerId: 'peer-a',
      messageId: 'recent-message',
      type: 'sms',
      receivedAt: now.subtract(InboxDao.retentionPeriod),
      updatedAt: now.subtract(InboxDao.retentionPeriod),
    );
    await dao.insertIfAbsent(retained);

    expect(await dao.deleteExpired(now: now), 0);
    expect(await dao.get('peer-a', 'recent-message'), isNotNull);
  });

  test('Inbox and domain persistence roll back together', () async {
    final record = InboxRecord(
      sourcePeerId: 'peer-a',
      messageId: 'message-a',
      type: 'call',
      receivedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(
      () => db.transaction((transaction) async {
        await transaction.insert('call_event', {
          'id': 'call-transaction',
          'direction': 'incoming',
          'number': '+1',
          'contact_name': '',
          'timestamp': 1,
          'encrypted': '',
          'status': 'ringing',
          'delivery_status': 'none',
          'created_at': 1,
        });
        await dao.insertIfAbsentOn(transaction, record);
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await db.query('call_event'), isEmpty);
    expect(await db.query('inbox'), isEmpty);
  });
}
