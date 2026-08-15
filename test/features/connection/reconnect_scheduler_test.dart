import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/features/connection/reconnect_scheduler.dart';

void main() {
  group('ReconnectScheduler', () {
    test('Tracks connection generation for stale result prevention', () {
      var generation = 0;
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {},
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      expect(scheduler.generation, 0);

      scheduler.forceReconnect();
      generation = scheduler.generation;
      expect(generation, greaterThan(0));

      scheduler.forceReconnect();
      expect(scheduler.generation, greaterThan(generation));
      scheduler.dispose();
    });

    test('Disconnection state management', () {
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {},
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      expect(scheduler.isDisconnected, false);

      scheduler.markDisconnected();
      expect(scheduler.isDisconnected, true);

      scheduler.markConnected();
      expect(scheduler.isDisconnected, false);
      scheduler.dispose();
    });

    test('Force reconnect resets attempt counter and bumps generation', () {
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {},
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
      );

      final oldGeneration = scheduler.generation;

      scheduler.forceReconnect();

      expect(scheduler.generation, greaterThan(oldGeneration));
      expect(scheduler.isDisconnected, true);
      scheduler.dispose();
    });

    test('stop prevents a pending reconnect from running', () async {
      var calls = 0;
      late final ReconnectScheduler scheduler;
      scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {
          calls++;
          scheduler.markConnected();
        },
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
        initialDelay: const Duration(milliseconds: 5),
      );

      scheduler.scheduleReconnect();
      scheduler.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 0);
      expect(scheduler.isStopped, true);
    });

    test('pause cancels recovery until start', () async {
      var calls = 0;
      late final ReconnectScheduler scheduler;
      scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {
          calls++;
          scheduler.markConnected();
        },
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
        initialDelay: const Duration(milliseconds: 5),
      );

      scheduler.markDisconnected();
      scheduler.pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0);
      expect(scheduler.isPaused, true);

      scheduler.start();
      scheduler.scheduleReconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);
      scheduler.dispose();
    });

    test('in-flight result cannot reschedule after dispose', () async {
      final attempt = Completer<void>();
      var calls = 0;
      final scheduler = ReconnectScheduler(
        logger: Logger(),
        onReconnect: (ip, port) async {
          calls++;
          await attempt.future;
          throw StateError('failed');
        },
        getPeerIp: () => '192.168.1.100',
        getPeerPort: () => 45678,
        initialDelay: const Duration(milliseconds: 1),
      );

      scheduler.markDisconnected();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(scheduler.hasAttemptInFlight, true);

      scheduler.dispose();
      attempt.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 1);
      expect(scheduler.isDisposed, true);
    });

    test(
      'simultaneous triggers keep one reconnect attempt in flight',
      () async {
        final attempt = Completer<void>();
        var active = 0;
        var maxActive = 0;
        late final ReconnectScheduler scheduler;
        scheduler = ReconnectScheduler(
          logger: Logger(),
          onReconnect: (ip, port) async {
            active++;
            if (active > maxActive) maxActive = active;
            await attempt.future;
            active--;
            scheduler.markConnected();
          },
          getPeerIp: () => '192.168.1.100',
          getPeerPort: () => 45678,
          initialDelay: const Duration(milliseconds: 1),
        );

        scheduler.markDisconnected();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        scheduler.forceReconnect();
        scheduler.scheduleReconnect();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(maxActive, 1);
        attempt.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        scheduler.dispose();
      },
    );
  });
}
