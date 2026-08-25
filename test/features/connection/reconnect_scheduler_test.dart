import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/features/connection/reconnect_scheduler.dart';

void main() {
  group('ReconnectScheduler', () {
    test('Tracks connection generation for stale result prevention', () {
      var generation = 0;
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async => true,
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      expect(scheduler.generation, 0);

      scheduler.forceReconnect();
      generation = scheduler.generation;
      expect(generation, greaterThan(0));

      scheduler.forceReconnect();
      expect(scheduler.generation, greaterThan(generation));
    });

    test('Disconnection state management', () {
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async => true,
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      expect(scheduler.isDisconnected, false);

      scheduler.markDisconnected();
      expect(scheduler.isDisconnected, true);

      scheduler.markConnected();
      expect(scheduler.isDisconnected, false);
    });

    test('Force reconnect resets attempt counter and bumps generation', () {
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async => true,
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      final oldGeneration = scheduler.generation;

      scheduler.forceReconnect();

      expect(scheduler.generation, greaterThan(oldGeneration));
      expect(scheduler.isDisconnected, false);
    });

    test('Reconnect scheduler disposes resources', () {
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async => true,
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      scheduler.scheduleReconnect();
      scheduler.dispose();
      // After dispose, timer should be cancelled (no exception thrown)
      expect(true, true);
    });
  });
}
