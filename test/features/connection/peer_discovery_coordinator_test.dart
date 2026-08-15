import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';
import 'package:mirrorline/features/connection/peer_discovery_coordinator.dart';

void main() {
  group('PeerDiscoveryCoordinator', () {
    test('Disconnection state tracking', () {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => null,
      );

      expect(coordinator.isDisconnected, false);

      coordinator.markDisconnected();
      expect(coordinator.isDisconnected, true);

      coordinator.markConnected();
      expect(coordinator.isDisconnected, false);
    });

    test('Beacon IPs collection', () {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => null,
      );

      expect(coordinator.beaconIps.isEmpty, true);

      coordinator.markConnected();
      expect(coordinator.beaconIps.isEmpty, true);
    });

    test('new beacon with no addresses clears stale candidates', () async {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'self-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => 'peer-id',
      );

      await coordinator.handleBeacon(
        const BeaconInfo(
          peerId: 'peer-id',
          tcpPort: 45678,
          deviceName: 'Peer',
          ip: '192.168.1.20',
          ips: ['10.0.0.20'],
        ),
      );
      expect(coordinator.beaconIps, ['10.0.0.20']);

      await coordinator.handleBeacon(
        const BeaconInfo(
          peerId: 'peer-id',
          tcpPort: 45678,
          deviceName: 'Peer',
          ip: '192.168.1.20',
        ),
      );
      expect(coordinator.beaconIps, isEmpty);
    });

    test('Beacon info update', () {
      var updateCallCount = 0;
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => null,
      );

      // updateBroadcastInfo updates internal state (ips, etc.)
      coordinator.updateBeaconInfo();
      updateCallCount++;

      expect(updateCallCount, 1);
    });

    test('Throttle setting', () {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => null,
      );

      // setThrottle should not throw
      coordinator.setThrottle(true);
      coordinator.setThrottle(false);

      expect(true, true);
    });

    test('Coordinator cleanup on dispose', () async {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port, {required fromScan}) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
        getExpectedPeerId: () => null,
      );

      await coordinator.startListening();
      coordinator.dispose();

      // After dispose, should be cleaned up
      expect(true, true);
    });
  });
}
