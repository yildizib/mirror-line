import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/services/queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late QueueService service;

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
    service = QueueService(dao: QueueDao.forDatabase(db));
  });

  tearDown(() => db.close());

  test('outbox assigns stable IDs and isolates destination peers', () async {
    final first = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );
    await service.enqueue('sms', '{}', destinationPeerId: 'peer-b');

    expect(first.messageId, isNotEmpty);
    final pending = await service.pendingItems('peer-a');
    expect(pending, hasLength(1));
    expect(pending.single.messageId, first.messageId);
    expect(pending.single.destinationPeerId, 'peer-a');
  });

  test('transport success keeps the row with transported status', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );

    await service.markSent(item.id!);

    expect(await service.pendingItems('peer-a'), isEmpty);
    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'transported');
  });

  test('exhausted retries become diagnosable dead letters', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );

    expect(await service.markFailed(item.id!, 5), isTrue);
    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'dead_letter');
  });
}
