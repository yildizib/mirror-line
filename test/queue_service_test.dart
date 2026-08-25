import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:mirrorline/core/services/queue_service.dart';

void main() {
  test('rejects payloads larger than the configured item limit', () async {
    final dao = _FakeQueueDao();
    final service = QueueService(
      dao: dao,
      makeDedupeKey: (type, payload) async =>
          payload.contains('message-1') ? '$type:message-1' : null,
    );
    final payload = 'x' * (SecurityConstants.maxQueueItemBytes + 1);

    expect(() => service.enqueue('sms', payload), throwsStateError);
    expect(dao.items, isEmpty);
  });

  test('rejects new items when the queue count limit is reached', () async {
    final dao = _FakeQueueDao(
      items: List.generate(
        SecurityConstants.maxQueueItems,
        (index) => QueueItem(
          id: index,
          type: 'sms',
          payload: 'payload',
          createdAt: DateTime.now(),
        ),
      ),
    );
    final service = QueueService(dao: dao);

    expect(() => service.enqueue('sms', 'payload'), throwsStateError);
    expect(dao.items, hasLength(SecurityConstants.maxQueueItems));
  });

  test('removes expired and retry-exhausted items before delivery', () async {
    final now = DateTime.now();
    final dao = _FakeQueueDao(
      items: [
        QueueItem(
          id: 1,
          type: 'sms',
          payload: 'expired',
          createdAt: now.subtract(SecurityConstants.queueItemTtl),
        ),
        QueueItem(
          id: 2,
          type: 'sms',
          payload: 'retry-exhausted',
          retryCount: SecurityConstants.maxQueueRetryCount,
          createdAt: now,
        ),
        QueueItem(id: 3, type: 'sms', payload: 'available', createdAt: now),
      ],
    );
    final service = QueueService(dao: dao);

    final pending = await service.pendingItems();

    expect(pending.map((item) => item.payload), ['available']);
  });

  test('deduplicates queued messages by originating identity', () async {
    final dao = _FakeQueueDao();
    final service = QueueService(
      dao: dao,
      makeDedupeKey: (type, payload) async =>
          payload.contains('message-1') ? '$type:message-1' : null,
    );
    const payload = '{"id":"message-1","body":"hello"}';

    await service.enqueue('sms_incoming', payload);
    await service.enqueue('sms_incoming', payload);

    expect(dao.items, hasLength(1));
  });

  test(
    'drops items at the retry boundary and increments lower retries',
    () async {
      final dao = _FakeQueueDao(
        items: [
          QueueItem(
            id: 1,
            type: 'sms',
            payload: 'drop',
            createdAt: DateTime.now(),
          ),
          QueueItem(
            id: 2,
            type: 'sms',
            payload: 'retry',
            createdAt: DateTime.now(),
          ),
        ],
      );
      final service = QueueService(dao: dao);

      expect(
        await service.markFailed(1, SecurityConstants.maxQueueRetryCount),
        isTrue,
      );
      expect(await service.markFailed(2, 1), isFalse);
      expect(dao.items.singleWhere((item) => item.id == 2).retryCount, 2);
      expect(dao.items.any((item) => item.id == 1), isFalse);
    },
  );
}

class _FakeQueueDao extends QueueDao {
  _FakeQueueDao({List<QueueItem>? items}) : items = items ?? [];

  final List<QueueItem> items;

  @override
  Future<void> insert(QueueItem item) async => items.add(item);

  @override
  Future<List<QueueItem>> getAll() async => List.of(items);

  @override
  Future<int> count() async => items.length;

  @override
  Future<void> deleteExpired(DateTime cutoff) async {
    items.removeWhere((item) => item.createdAt.isBefore(cutoff));
  }

  @override
  Future<void> deleteRetryExceeded(int maxRetryCount) async {
    items.removeWhere((item) => item.retryCount >= maxRetryCount);
  }

  @override
  Future<bool> hasDedupeKey(String dedupeKey) async =>
      items.any((item) => item.dedupeKey == dedupeKey);

  @override
  Future<void> updateRetryCount(int id, int retryCount) async {
    final index = items.indexWhere((item) => item.id == id);
    items[index] = items[index].copyWith(retryCount: retryCount);
  }

  @override
  Future<void> delete(int id) async {
    items.removeWhere((item) => item.id == id);
  }
}
