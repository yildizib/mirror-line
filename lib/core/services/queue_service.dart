import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

class QueueService {
  final QueueDao _dao;

  QueueService({QueueDao? dao}) : _dao = dao ?? QueueDao();

  Future<QueueItem> enqueue(
    String type,
    String payload, {
    required String destinationPeerId,
    String? messageId,
  }) async {
    return _dao.insert(
      QueueItem(
        messageId: messageId ?? const Uuid().v4(),
        destinationPeerId: destinationPeerId,
        type: type,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<QueueItem> enqueueOnDatabase(
    DatabaseExecutor db,
    String type,
    String payload, {
    required String destinationPeerId,
    String? messageId,
  }) {
    return _dao.insertOn(
      db,
      QueueItem(
        messageId: messageId ?? const Uuid().v4(),
        destinationPeerId: destinationPeerId,
        type: type,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<QueueItem>> pendingItems(String destinationPeerId) =>
      _dao.getAll(destinationPeerId);

  Future<void> markSent(int id) async {
    await _dao.updateStatus(id, 'transported');
  }

  /// Returns true if this was the final attempt and the item was dropped
  /// (never silently -- the caller is expected to reflect that back to the
  /// user, e.g. by marking the originating SMS/call entry as 'failed').
  Future<bool> markFailed(int id, int retryCount) async {
    if (retryCount >= 5) {
      await _dao.updateStatus(id, 'dead_letter');
      return true;
    }
    await _dao.updateRetryCount(id, retryCount + 1);
    return false;
  }

  Future<void> clear() => _dao.deleteAll();
}
