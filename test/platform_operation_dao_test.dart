import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/platform_operation_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late PlatformOperationDao dao;

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
    dao = PlatformOperationDao.forDatabase(db);
  });

  tearDown(() => db.close());

  test('operation ID claim and state are durable and idempotent', () async {
    expect(
      await dao.claim(operationId: 'm1', kind: 'sms_send', payload: '{}'),
      isTrue,
    );
    expect(
      await dao.claim(operationId: 'm1', kind: 'sms_send', payload: '{}'),
      isFalse,
    );
    await dao.updateState('m1', 'succeeded');
    expect(await dao.state('m1'), 'succeeded');
  });

  test('executing operations are recovered after process restart', () async {
    expect(
      await dao.claim(operationId: 'm2', kind: 'call_reject', payload: '{}'),
      isTrue,
    );
    await dao.updateState('m2', 'executing');
    expect(await dao.recoverExecuting(), 1);
    expect(await dao.state('m2'), 'received');
  });
}
