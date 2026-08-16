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
      await dao.claim(
        operationId: 'm1',
        kind: 'sms_send',
        payload: '{"messageId":"sms-1"}',
      ),
      isTrue,
    );
    expect(
      await dao.claim(
        operationId: 'm1',
        kind: 'sms_send',
        payload: '{"messageId":"sms-1"}',
      ),
      isFalse,
    );
    expect(
      await dao.transition('m1', from: ['received'], to: 'succeeded'),
      isTrue,
    );
    expect(await dao.state('m1'), 'succeeded');
    expect(await dao.payload('m1'), '{"messageId":"sms-1"}');
  });

  test('executing operations are recovered after process restart', () async {
    expect(
      await dao.claim(operationId: 'm2', kind: 'call_reject', payload: '{}'),
      isTrue,
    );
    await dao.transition('m2', from: ['received'], to: 'executing');
    expect(await dao.recoverExecuting(), 1);
    expect(await dao.state('m2'), 'received');
  });

  test(
    'terminal and submitted operations cannot be overwritten or recovered',
    () async {
      await dao.claim(operationId: 'm3', kind: 'sms_send', payload: '{}');
      await dao.transition('m3', from: ['received'], to: 'executing');
      await dao.transition('m3', from: ['executing'], to: 'submitted');

      expect(
        await dao.transition('m3', from: ['submitted'], to: 'succeeded'),
        isTrue,
      );
      expect(
        await dao.transition('m3', from: ['submitted'], to: 'failed'),
        isFalse,
      );
      expect(await dao.recoverExecuting(), 0);
      expect(await dao.state('m3'), 'succeeded');
    },
  );

  test('operations can be queried for recovery by kind and state', () async {
    await dao.claim(
      operationId: 'sms',
      kind: 'sms_send',
      payload: '{"id":"1"}',
    );
    await dao.claim(operationId: 'call', kind: 'call_reject', payload: '{}');

    final operations = await dao.list(kind: 'sms_send', states: ['received']);

    expect(operations, hasLength(1));
    expect(operations.single.id, 'sms');
    expect(operations.single.payload, '{"id":"1"}');
  });

  test(
    'ready calls can be failed without retrying an uncertain boundary',
    () async {
      await dao.claim(
        operationId: 'call-ready',
        kind: 'call_reject',
        payload: '{}',
      );
      await dao.transition('call-ready', from: ['received'], to: 'ready');

      expect(await dao.failReady(kind: 'call_reject'), 1);
      expect(await dao.state('call-ready'), 'failed');
    },
  );
}
