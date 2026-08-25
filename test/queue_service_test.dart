import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:mirrorline/core/services/queue_service.dart';

void main() {
  test('rejects payloads larger than the configured item limit', () async {
    final dao = _FakeQueueDao();
    final service = QueueService(dao: dao);
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
}
