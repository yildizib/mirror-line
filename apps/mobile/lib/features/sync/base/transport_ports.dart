import 'package:mirrorline/core/services/notification_service.dart';

/// Transport port used by feature facades for reliable peer delivery.
typedef SendOrQueue =
    Future<bool> Function(String type, Map<String, dynamic> payload);

/// Message-routing port used by feature facades for local notifications.
typedef ShowNotification =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      NotificationPayload? payload,
    });
