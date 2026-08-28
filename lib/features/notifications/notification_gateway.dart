import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/services/notification_service.dart';

abstract interface class NotificationNavigationGateway {
  ValueListenable<NotificationNavigationRequest?> get requests;
  void consume();
}

class NotificationRouterGateway implements NotificationNavigationGateway {
  const NotificationRouterGateway();

  @override
  ValueListenable<NotificationNavigationRequest?> get requests =>
      NotificationRouter.instance.requests;

  @override
  void consume() => NotificationRouter.instance.consume();
}
