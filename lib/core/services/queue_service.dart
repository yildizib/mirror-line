import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';

class QueueService {
  final QueueDao _dao = QueueDao();

  Future<void> enqueue(String type, String payload) async {
    await _dao.insert(QueueItem(
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    ));
  }

  Future<List<QueueItem>> pendingItems() => _dao.getAll();

  Future<void> markSent(int id) async {
    await _dao.delete(id);
  }

  Future<void> markFailed(int id, int retryCount) async {
    if (retryCount >= 5) {
      await _dao.delete(id);
    } else {
      await _dao.updateRetryCount(id, retryCount + 1);
    }
  }

  Future<void> clear() => _dao.deleteAll();
}
