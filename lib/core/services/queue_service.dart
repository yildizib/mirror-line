import 'dart:async';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:math';

class OutboxFlushGate {
  Future<void>? _inFlight;
  bool _rerunRequested = false;

  Future<void> run(Future<void> Function() worker) async {
    final running = _inFlight;
    if (running != null) {
      _rerunRequested = true;
      return running;
    }
    final future = _run(worker);
    _inFlight = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  Future<void> _run(Future<void> Function() worker) async {
    do {
      _rerunRequested = false;
      await worker();
    } while (_rerunRequested);
  }
}

typedef OutboxRetryTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Owns one in-process Outbox wake-up and discards callbacks from replaced
/// socket sessions. The callback enters the caller's normal flush gate.
class OutboxRetryScheduler {
  OutboxRetryScheduler({OutboxRetryTimerFactory? timerFactory})
    : _timerFactory = timerFactory ?? Timer.new;

  final OutboxRetryTimerFactory _timerFactory;
  Timer? _timer;
  Object? _session;

  void schedule({
    required Object session,
    required DateTime deadline,
    required DateTime now,
    required bool Function() isSessionCurrent,
    required Future<void> Function() onDue,
  }) {
    _timer?.cancel();
    _session = session;
    final delay = deadline.difference(now);
    _timer = _timerFactory(delay.isNegative ? Duration.zero : delay, () async {
      if (!identical(_session, session) || !isSessionCurrent()) return;
      _timer = null;
      await onDue();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _session = null;
  }
}

class QueueService {
  static const _ackRetryDelay = Duration(seconds: 5);
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

  Future<DateTime?> nextAttemptAt(String destinationPeerId) =>
      _dao.nextAttemptAt(destinationPeerId);

  /// Keeps a successfully written item eligible if its ACK is lost.
  Future<void> markSent(int id) async {
    await _dao.markSent(id, DateTime.now().add(_ackRetryDelay));
  }

  Future<void> markAcknowledged(
    String messageId, {
    String? destinationPeerId,
  }) async {
    await _dao.markAcknowledged(
      messageId,
      destinationPeerId: destinationPeerId,
    );
  }

  /// Returns true if this was the final attempt and the item was dropped
  /// (never silently -- the caller is expected to reflect that back to the
  /// user, e.g. by marking the originating SMS/call entry as 'failed').
  Future<bool> markFailed(int id, int retryCount) async {
    if (retryCount >= 5) {
      return _dao.moveToDeadLetter(id);
    }
    final nextRetryCount = retryCount + 1;
    final exponentialSeconds = pow(2, retryCount).toInt().clamp(1, 300);
    final jitterMilliseconds = Random().nextInt(1000);
    await _dao.updateRetry(
      id,
      nextRetryCount,
      DateTime.now().add(
        Duration(seconds: exponentialSeconds, milliseconds: jitterMilliseconds),
      ),
    );
    return false;
  }

  Future<void> clear() => _dao.deleteAll();
}
