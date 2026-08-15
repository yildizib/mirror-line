import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Payload carried by a local notification, so a tap can deep-link the user
/// to the right place: the calls list, a specific SMS thread, or a
/// mirrored-notification's group detail screen.
///
/// Encoded as a JSON string because flutter_local_notifications only accepts
/// a single nullable `String?` payload.
@immutable
class NotificationPayload {
  /// 'call' | 'sms' | 'mirrored_notification'
  final String type;

  /// The call/SMS/notification id -- used to scroll to / highlight the
  /// relevant row, or (for mirrored_notification) to look up the event's
  /// packageName for group-detail navigation.
  final String? id;

  /// For SMS, the address (thread key) to open. Calls/notifications don't
  /// use this.
  final String? address;

  const NotificationPayload({required this.type, this.id, this.address});

  String? encode() {
    return jsonEncode({
      'type': type,
      if (id != null) 'id': id,
      if (address != null) 'address': address,
    });
  }

  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      return NotificationPayload(
        type: type,
        id: map['id'] as String?,
        address: map['address'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A tap target produced by a notification -- the UI layer listens to this
/// and navigates accordingly (switch tab, open an SMS thread, etc.).
class NotificationNavigationRequest {
  final NotificationPayload payload;

  NotificationNavigationRequest(this.payload);
}

/// Singleton bridge between notification taps (which arrive on a background
/// isolate callback with no BuildContext) and the widget tree. HomeScreen
/// listens to [requests] and consumes them on its next build.
class NotificationRouter {
  NotificationRouter._();
  static final NotificationRouter instance = NotificationRouter._();

  final ValueNotifier<NotificationNavigationRequest?> requests =
      ValueNotifier<NotificationNavigationRequest?>(null);
  final List<NotificationNavigationRequest> _pending = [];

  void dispatch(NotificationPayload payload) {
    _pending.add(NotificationNavigationRequest(payload));
    _publishNext();
  }

  void consume() {
    if (_pending.isNotEmpty) _pending.removeAt(0);
    _publishNext();
  }

  void _publishNext() {
    requests.value = _pending.isEmpty ? null : _pending.first;
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called by the platform when the user taps a notification. Forwards the
  /// payload (if we recognize it) to [NotificationRouter] so the running
  /// app can deep-link to the right screen.
  static void _onResponse(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    if (payload == null) return;
    NotificationRouter.instance.dispatch(payload);
  }

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    NotificationPayload? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'mirrorline_channel',
      'MirrorLine Notifications',
      channelDescription: 'Incoming calls and SMS sync notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload?.encode(),
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();
}
