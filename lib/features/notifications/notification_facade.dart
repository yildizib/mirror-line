import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/notification_event_dao.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:uuid/uuid.dart';

final notificationFacadeProvider =
    StateNotifierProvider<NotificationFacade, List<NotificationEvent>>((ref) {
      final connectionFacade = ref.read(connectionFacadeProvider.notifier);
      return NotificationFacade(
        ref: ref,
        logger: Logger(),
        sendOrQueue: connectionFacade.sendOrQueue,
        notify: connectionFacade.notify,
      );
    });

/// Built directly as a Facade (state + native/peer handling merged), per
/// issue #40 -- issue #39 already established this merged shape for
/// CallFacade/SmsFacade, so there's no reason to build an intermediate
/// pre-merge handler class here. Own top-level provider (not a private
/// field of ConnectionFacade) so NotificationsScreen/HomeFeedScreen can
/// watch it independently.
class NotificationFacade extends StateNotifier<List<NotificationEvent>> {
  final NotificationEventDao _dao = NotificationEventDao();
  final Ref _ref;
  final Logger _logger;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;

  NotificationFacade({
    required this._ref,
    required this._logger,
    required this._sendOrQueue,
    required this._notify,
  }) : super([]) {
    load();
  }

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------

  Future<void> load() async {
    state = await _dao.getAll();
  }

  Future<void> add(NotificationEvent event) async {
    await _dao.insert(event);
    final exists = state.any((e) => e.id == event.id);
    state = exists
        ? state.map((e) => e.id == event.id ? event : e).toList()
        : [event, ...state];
  }

  Future<void> removeByNativeId(String packageName, String nativeId) async {
    bool matches(NotificationEvent e) =>
        e.packageName == packageName && e.nativeId == nativeId;
    NotificationEvent? target;
    for (final e in state) {
      if (matches(e)) {
        target = e;
        break;
      }
    }
    await _dao.deleteByNativeId(packageName, nativeId);
    state = state.where((e) => !matches(e)).toList();
    if (target != null) {
      try {
        // Must match the id _notify() used when showing it (nativeId's
        // hash, not the local event id) or the wrong OS notification --
        // or none -- gets cancelled.
        await NotificationService.cancel(
          target.nativeId.hashCode & 0x7fffffff,
        );
      } catch (e) {
        _logger.e('Failed to cancel mirrored notification: $e');
      }
    }
  }

  /// Permanently deletes every event in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    for (final id in idSet) {
      await _dao.delete(id);
    }
    state = state.where((e) => !idSet.contains(e.id)).toList();
  }

  /// Permanently deletes all notifications (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await _dao.deleteAll();
    state = [];
  }

  // -----------------------------------------------------------------------
  // Native events (Source device only)
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    final packageName = (data['packageName'] as String?) ?? 'unknown';
    if (packageName == 'com.thinksolve.mirrorline') return;
    // Read live, not captured at construction -- the watched set can
    // change any time via the Watched Apps screen.
    if (!_ref.read(watchedAppsProvider.notifier).isWatched(packageName)) {
      return;
    }

    final appName = (data['appName'] as String?) ?? packageName;
    final title = (data['title'] as String?) ?? '';
    final text = (data['text'] as String?) ?? '';
    final timestamp = (data['timestamp'] as int?) ?? now.millisecondsSinceEpoch;
    // Native's own stable per-notification key (sbn.key), not the
    // generated message id -- lets a dismissal on the source device match
    // back to the right stored event.
    final nativeId = (data['id'] as String?) ?? id;

    final event = NotificationEvent(
      id: id,
      nativeId: nativeId,
      packageName: packageName,
      appName: appName,
      title: title,
      text: text,
      encrypted: '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      createdAt: now,
    );
    await add(event);
    await _sendOrQueue(MessageTypes.notificationMirrored, {
      'nativeId': nativeId,
      'packageName': packageName,
      'appName': appName,
      'title': title,
      'text': text,
      'timestamp': timestamp,
    });
  }

  Future<void> handleNativeRemoval(Map<dynamic, dynamic> data) async {
    final packageName = (data['packageName'] as String?) ?? 'unknown';
    final nativeId = (data['id'] as String?) ?? '';
    if (nativeId.isEmpty) return;

    await removeByNativeId(packageName, nativeId);
    await _sendOrQueue(MessageTypes.notificationRemoved, {
      'packageName': packageName,
      'nativeId': nativeId,
    });
  }

  // -----------------------------------------------------------------------
  // Incoming peer messages (Main-device side)
  // -----------------------------------------------------------------------

  Future<void> handleIncomingMessage(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now,
  ) async {
    switch (type) {
      case MessageTypes.notificationMirrored:
        final packageName = payload['packageName'] as String? ?? 'unknown';
        final appName = payload['appName'] as String? ?? packageName;
        final title = payload['title'] as String? ?? '';
        final text = payload['text'] as String? ?? '';
        final nativeId = payload['nativeId'] as String? ?? message.id;
        final event = NotificationEvent(
          id: const Uuid().v4(),
          nativeId: nativeId,
          packageName: packageName,
          appName: appName,
          title: title,
          text: text,
          encrypted: message.payload,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            payload['timestamp'] as int? ?? now.millisecondsSinceEpoch,
          ),
          createdAt: now,
        );
        await add(event);
        await _notify(
          id: nativeId.hashCode & 0x7fffffff,
          title: appName,
          body: (title.isNotEmpty && title != appName) ? '$title: $text' : text,
          payload: NotificationPayload(type: 'mirrored_notification', id: event.id),
        );
        break;

      case MessageTypes.notificationRemoved:
        final packageName = payload['packageName'] as String? ?? 'unknown';
        final nativeId = payload['nativeId'] as String? ?? '';
        if (nativeId.isNotEmpty) {
          await removeByNativeId(packageName, nativeId);
        }
        break;

      default:
        _logger.i('NotificationFacade: unhandled message type $type');
    }
  }
}
