import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/notification_event_dao.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/stable_notification_id.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

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
  final NotificationEventDao _dao;
  final Ref _ref;
  final Logger _logger;
  final SendOrQueue _sendOrQueue;
  final ShowNotification _notify;
  late final Future<void> _initialized;

  NotificationFacade({
    required this._ref,
    required this._logger,
    required this._sendOrQueue,
    required this._notify,
    NotificationEventDao? dao,
  }) : _dao = dao ?? NotificationEventDao(),
       super([]) {
    _initialized = load();
  }

  Future<void> get initialized => _initialized;

  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------

  Future<void> load() async {
    state = await _dao.getAll();
  }

  Future<List<NotificationEvent>> loadRecent({
    required int limit,
    DateTime? since,
  }) async {
    return _dao.getRecent(limit: limit, since: since);
  }

  Future<List<NotificationEvent>> loadOlder({
    required int limit,
    required int offset,
    DateTime? before,
  }) async {
    return _dao.getOlder(limit: limit, offset: offset, before: before);
  }

  Future<void> add(NotificationEvent event) async {
    await initialized;
    await _persistEvent(event);
  }

  Future<void> _persistEvent(
    NotificationEvent event, {
    DatabaseExecutor? transaction,
  }) async {
    if (transaction == null) {
      await _dao.insert(event);
    } else {
      await _dao.insertOn(transaction, event);
    }
    final exists = state.any((e) => e.id == event.id);
    state = exists
        ? state.map((e) => e.id == event.id ? event : e).toList()
        : [event, ...state];
  }

  Future<void> removeByNativeId(
    String sourcePeerId,
    String packageName,
    String nativeId,
  ) async {
    await initialized;
    bool matches(NotificationEvent e) =>
        e.sourcePeerId == sourcePeerId &&
        e.packageName == packageName &&
        e.nativeId == nativeId;
    NotificationEvent? target;
    for (final e in state) {
      if (matches(e)) {
        target = e;
        break;
      }
    }
    await _dao.deleteByNativeId(sourcePeerId, packageName, nativeId);
    state = state.where((e) => !matches(e)).toList();
    if (target != null) {
      try {
        // Must match the id _notify() used when showing it (the full source
        // identity, not the local event id) or the wrong OS notification --
        // or none -- gets cancelled.
        await NotificationService.cancel(
          stableNotificationId(
            'mirrored_notification',
            '$sourcePeerId:$packageName:$nativeId',
          ),
        );
      } catch (e) {
        _logger.e('Failed to cancel mirrored notification: $e');
      }
    }
  }

  /// Permanently deletes every event in [ids] (used by multi-select clear).
  Future<void> removeMany(Iterable<String> ids) async {
    await initialized;
    final idSet = ids.toSet();
    for (final id in idSet) {
      await _dao.delete(id);
    }
    state = state.where((e) => !idSet.contains(e.id)).toList();
  }

  /// Permanently deletes all notifications (used by "clear all" / device reset).
  Future<void> removeAll() async {
    await initialized;
    await _dao.deleteAll();
    state = [];
  }

  /// Sends a synthetic notification-mirrored message, bypassing
  /// handleNativeEvent's native-map/self-package/watched-apps gating --
  /// for the Settings diagnostics "Run Tests" button (issue #42), which
  /// needs to broadcast a fake event regardless of watched-apps state.
  /// Uses a fixed synthetic packageName so repeated test runs group
  /// together under one recognizable "app" on the receiving device,
  /// distinct from any real installed app. Not persisted locally on the
  /// sending device, matching CallFacade.sendCallNotification/
  /// SmsFacade.sendSmsNotification -- the sender doesn't get a mirrored
  /// copy of its own outgoing event.
  Future<bool> sendTestNotification({
    required String appName,
    required String title,
    required String text,
  }) {
    final nativeId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _sendOrQueue(MessageTypes.notificationMirrored, {
      'nativeId': nativeId,
      'packageName': 'mirrorline.diagnostics.test',
      'appName': appName,
      'title': title,
      'text': text,
      'timestamp': timestamp,
    });
  }

  // -----------------------------------------------------------------------
  // Native events (Source device only)
  // -----------------------------------------------------------------------

  Future<void> handleNativeEvent(
    Map<dynamic, dynamic> data, {
    required String id,
    required DateTime now,
  }) async {
    await Future.wait([
      initialized,
      _ref.read(watchedAppsProvider.notifier).initialized,
    ]);
    final packageName = (data['packageName'] as String?) ?? 'unknown';
    if (packageName == 'io.github.yildizib.mirrorline') return;
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
      sourcePeerId: NotificationEvent.localSourcePeerId,
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
    await Future.wait([
      initialized,
      _ref.read(watchedAppsProvider.notifier).initialized,
    ]);
    // Intentionally a no-op. Android fires onNotificationRemoved for many
    // reasons (dismiss, auto-cancel on open, summary regrouping) that don't
    // mean the user wants the mirrored record gone. We keep events in the
    // DB, matching how Call/SMS are persisted regardless of the source
    // notification's lifecycle. The native listener no longer forwards
    // removals here either (issue #59); this is kept as a safety net.
    _logger.i('NotificationFacade: native removal ignored (event kept)');
  }

  // -----------------------------------------------------------------------
  // Incoming peer messages (Main-device side)
  // -----------------------------------------------------------------------

  Future<void> handleIncomingMessage(
    String type,
    Map<String, dynamic> payload,
    MirrorMessage message,
    DateTime now, {
    DatabaseExecutor? transaction,
  }) async {
    await initialized;
    switch (type) {
      case MessageTypes.notificationMirrored:
        final packageName = payload['packageName'] as String? ?? 'unknown';
        final appName = payload['appName'] as String? ?? packageName;
        final title = payload['title'] as String? ?? '';
        final text = payload['text'] as String? ?? '';
        final nativeId = payload['nativeId'] as String? ?? message.id;
        final sourcePeerId = message.sourcePeerId;
        if (sourcePeerId == null) {
          _logger.w('Ignoring notification without a source peer identity');
          return;
        }
        final event = NotificationEvent(
          id: stableNotificationId(
            'mirrored_notification',
            '$sourcePeerId:$packageName:$nativeId',
          ).toString(),
          nativeId: nativeId,
          sourcePeerId: sourcePeerId,
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
        await _persistEvent(event, transaction: transaction);
        await _notify(
          id: stableNotificationId(
            'mirrored_notification',
            '$sourcePeerId:$packageName:$nativeId',
          ),
          title: appName,
          body: (title.isNotEmpty && title != appName) ? '$title: $text' : text,
          payload: NotificationPayload(
            type: 'mirrored_notification',
            id: event.id,
          ),
        );
        break;

      case MessageTypes.notificationRemoved:
        // No-op: keep events in the DB. Older source devices may still
        // send this message; we intentionally ignore it so notifications
        // persist on the Main device too (issue #59).
        _logger.i('NotificationFacade: peer removal ignored (event kept)');
        break;

      default:
        _logger.i('NotificationFacade: unhandled message type $type');
    }
  }
}
