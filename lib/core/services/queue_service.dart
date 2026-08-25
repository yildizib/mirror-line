import 'dart:convert';

import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/security_constants.dart';

class QueueService {
  final QueueDao _dao;
  final Future<String?> Function(String type, String payload) _makeDedupeKey;

  QueueService({
    QueueDao? dao,
    Future<String?> Function(String type, String payload)? makeDedupeKey,
  }) : _dao = dao ?? QueueDao(),
       _makeDedupeKey = makeDedupeKey ?? _defaultDedupeKey;

  Future<void> enqueue(String type, String payload) async {
    await _removeUnavailableItems();
    if (utf8.encode(payload).length > SecurityConstants.maxQueueItemBytes) {
      throw StateError('Queue payload exceeds the maximum item size.');
    }
    if (await _dao.count() >= SecurityConstants.maxQueueItems) {
      throw StateError('Queue item limit reached.');
    }
    final dedupeKey = await _makeDedupeKey(type, payload);
    if (dedupeKey != null && await _dao.hasDedupeKey(dedupeKey)) return;
    await _dao.insert(
      QueueItem(
        type: type,
        payload: payload,
        dedupeKey: dedupeKey,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<QueueItem>> pendingItems() async {
    await _removeUnavailableItems();
    return _dao.getAll();
  }

  Future<void> markSent(int id) async {
    await _dao.delete(id);
  }

  /// Returns true if this was the final attempt and the item was dropped
  /// (never silently -- the caller is expected to reflect that back to the
  /// user, e.g. by marking the originating SMS/call entry as 'failed').
  Future<bool> markFailed(int id, int retryCount) async {
    if (retryCount >= SecurityConstants.maxQueueRetryCount) {
      await _dao.delete(id);
      return true;
    }
    await _dao.updateRetryCount(id, retryCount + 1);
    return false;
  }

  Future<void> clear() => _dao.deleteAll();

  Future<void> _removeUnavailableItems() async {
    final cutoff = DateTime.now().subtract(SecurityConstants.queueItemTtl);
    await _dao.deleteExpired(cutoff);
    await _dao.deleteRetryExceeded(SecurityConstants.maxQueueRetryCount);
  }

  static Future<String?> _defaultDedupeKey(String type, String payload) async {
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic>) return null;
      final identity = value['id'] ?? value['nativeId'];
      if (identity == null || identity.toString().isEmpty) return null;
      final key = await KeyStore.ensureLocalDatabaseKey();
      return await CryptoManager.keyedLookupDigest(
        key,
        '$type:${identity.toString()}',
      );
    } on FormatException {
      return null;
    }
  }
}
