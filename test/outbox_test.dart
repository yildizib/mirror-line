import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
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

  test('transport success keeps the row until committed ACK', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );

    await service.markSent(item.id!);

    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'sent');
    expect(rows.single['next_attempt_at'], isNotNull);
    expect(
      await service.pendingItems('peer-a'),
      isEmpty,
      reason: 'wait for the ACK retry window instead of immediately resending',
    );
    await db.update(
      'outbox',
      {'next_attempt_at': DateTime.now().millisecondsSinceEpoch - 1},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect((await service.pendingItems('peer-a')).single.status, 'sent');
    await service.markAcknowledged(item.messageId);
    final acknowledged = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(acknowledged.single['status'], 'completed');
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

  test('lost ACK retries with the original ID until dead-lettered', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
      messageId: 'lost-ack-id',
    );

    for (var attempt = 0; attempt < 5; attempt++) {
      final due = await service.pendingItems('peer-a');
      expect(due.single.messageId, 'lost-ack-id');
      await service.markSent(item.id!);
      await service.markFailed(item.id!, attempt);
      await db.update(
        'outbox',
        {'next_attempt_at': DateTime.now().millisecondsSinceEpoch - 1},
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    expect(await service.markFailed(item.id!, 5), isTrue);

    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'dead_letter');
    expect(rows.single['next_attempt_at'], isNull);
  });

  test('each live ACK deadline expiry progresses to dead letter', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
      messageId: 'live-lost-ack-id',
    );
    await service.markSent(item.id!);

    for (
      var expectedAttemptCount = 0;
      expectedAttemptCount <= 5;
      expectedAttemptCount++
    ) {
      await db.update(
        'outbox',
        {'next_attempt_at': DateTime.now().millisecondsSinceEpoch - 1},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      final expired = (await service.pendingItems('peer-a')).single;
      expect(expired.status, 'sent');
      expect(expired.messageId, 'live-lost-ack-id');
      expect(expired.retryCount, expectedAttemptCount);

      final deadLettered = await service.markFailed(
        expired.id!,
        expired.retryCount,
      );
      expect(deadLettered, expectedAttemptCount == 5);
    }

    final row = (await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    )).single;
    expect(row['status'], 'dead_letter');
    expect(row['next_attempt_at'], isNull);
  });

  test('domain mutation and Outbox insertion roll back together', () async {
    final dao = QueueDao.forDatabase(db);
    expect(
      () => db.transaction((transaction) async {
        await transaction.insert('sms_message', {
          'id': 'sms-transaction',
          'thread_id': '',
          'address': '+1',
          'contact_name': '',
          'body': 'body',
          'encrypted': '',
          'direction': 'outgoing',
          'status': 'pending',
          'delivery_status': 'none',
          'timestamp': 1,
          'created_at': 1,
        });
        await dao.insertOn(
          transaction,
          QueueItem(
            messageId: 'message-transaction',
            destinationPeerId: 'peer-a',
            type: 'sms',
            payload: '{}',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          ),
        );
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await db.query('sms_message'), isEmpty);
    expect(await db.query('outbox'), isEmpty);
  });

  test('lost and duplicate ACKs preserve idempotent retry identity', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
      messageId: 'stable-message',
    );
    await service.markSent(item.id!);

    await db.update(
      'outbox',
      {'next_attempt_at': DateTime.now().millisecondsSinceEpoch - 1},
      where: 'id = ?',
      whereArgs: [item.id],
    );

    final retry = await service.pendingItems('peer-a');
    expect(retry.single.messageId, 'stable-message');
    expect(retry.single.status, 'sent');

    await service.markAcknowledged('stable-message');
    await service.markAcknowledged('stable-message');
    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'completed');
  });

  test('stale terminal transitions cannot overwrite a completed ACK', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );

    await service.markAcknowledged(item.messageId);
    await service.markSent(item.id!);
    expect(await service.markFailed(item.id!, 5), isFalse);

    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['status'], 'completed');
  });

  test('retry scheduling uses exponential delay with jitter', () async {
    final item = await service.enqueue(
      'sms',
      '{}',
      destinationPeerId: 'peer-a',
    );
    final before = DateTime.now().millisecondsSinceEpoch;

    await service.markFailed(item.id!, 0);

    final rows = await db.query(
      'outbox',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(rows.single['attempt_count'], 1);
    expect(rows.single['next_attempt_at'] as int, greaterThan(before + 900));
  });

  test(
    'concurrent flush requests schedule one rerun after the active worker',
    () async {
      final gate = OutboxFlushGate();
      var executions = 0;
      Future<void> worker() async {
        executions++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      await Future.wait([gate.run(worker), gate.run(worker)]);

      expect(executions, 2);
    },
  );

  test('retry scheduler ignores stale session workers', () async {
    final callbacks = <void Function()>[];
    final timers = <Timer>[];
    final scheduler = OutboxRetryScheduler(
      timerFactory: (_, callback) {
        callbacks.add(callback);
        final timer = Timer(const Duration(days: 1), () {});
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(() {
      scheduler.cancel();
      for (final timer in timers) {
        timer.cancel();
      }
    });
    var flushed = 0;
    final oldSession = Object();
    final currentSession = Object();

    scheduler.schedule(
      session: oldSession,
      deadline: DateTime(2026),
      now: DateTime(2026),
      isSessionCurrent: () => true,
      onDue: () async => flushed++,
    );
    scheduler.schedule(
      session: currentSession,
      deadline: DateTime(2026),
      now: DateTime(2026),
      isSessionCurrent: () => true,
      onDue: () async => flushed++,
    );

    callbacks.first();
    await Future<void>.delayed(Duration.zero);
    expect(flushed, 0, reason: 'replacement cancels the old session worker');

    callbacks.last();
    await Future<void>.delayed(Duration.zero);
    expect(flushed, 1);
  });
}
