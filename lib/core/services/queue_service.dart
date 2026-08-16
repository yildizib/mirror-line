import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:uuid/uuid.dart';

class QueueService {
  final QueueDao _dao = QueueDao();

  Future<void> enqueue(
    String type,
    String payload, {
    required String destinationPeerId,
    String? messageId,
  }) async {
    await _dao.insert(
      QueueItem(
        messageId: messageId ?? const Uuid().v4(),
        destinationPeerId: destinationPeerId,
        type: type,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<QueueItem>> pendingItems() => _dao.getAll();

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
