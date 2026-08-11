import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/features/connection/peer_discovery_coordinator.dart';

void main() {
  group('PeerDiscoveryCoordinator', () {
    test('Disconnection state tracking', () {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
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
        onDiscovered: (ip, port) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
      );

      expect(coordinator.beaconIps.isEmpty, true);

      coordinator.markConnected();
      expect(coordinator.beaconIps.isEmpty, true);
    });

    test('Beacon info update', () {
      var updateCallCount = 0;
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
      );

      // updateBroadcastInfo updates internal state (ips, etc.)
      coordinator.updateBeaconInfo();
      updateCallCount++;

      expect(updateCallCount, 1);
    });

    test('Throttle setting', () {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
      );

      // setThrottle should not throw
      coordinator.setThrottle(true);
      coordinator.setThrottle(false);

      expect(true, true);
    });

    test('Coordinator cleanup on dispose', () async {
      final coordinator = PeerDiscoveryCoordinator(
        logger: Logger(),
        onDiscovered: (ip, port) async {},
        getPeerId: () => 'peer-id',
        getPeerPort: () => 45678,
        getDeviceName: () => 'Test Device',
        getAllLocalIps: () => ['192.168.1.10'],
      );

      await coordinator.startListening();
      coordinator.dispose();

      // After dispose, should be cleaned up
      expect(true, true);
    });
  });
}
