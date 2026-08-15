import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/stable_notification_id.dart';

void main() {
  test('notification IDs are stable and namespaced', () {
    final first = stableNotificationId('sms', 'message-1');
    expect(stableNotificationId('sms', 'message-1'), first);
    expect(stableNotificationId('call', 'message-1'), isNot(first));
  });

  test('notification router preserves FIFO requests until consumed', () {
    final router = NotificationRouter.instance;
    router.consume();
    router.dispatch(const NotificationPayload(type: 'call', id: 'first'));
    router.dispatch(const NotificationPayload(type: 'sms', id: 'second'));

    expect(router.requests.value?.payload.id, 'first');
    router.consume();
    expect(router.requests.value?.payload.id, 'second');
    router.consume();
    expect(router.requests.value, isNull);
  });
}
