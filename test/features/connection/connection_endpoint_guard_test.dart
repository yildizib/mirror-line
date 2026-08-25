import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/features/connection/connection_endpoint_guard.dart';

void main() {
  final pairedPeer = Peer(
    id: 'remote-id',
    deviceName: 'Remote',
    role: 'main',
    ip: '192.168.1.20',
    port: 45678,
    key: 'key',
    publicKey: 'remote-public-key',
    createdAt: DateTime(2026),
  );

  group('isUsablePeerEndpoint', () {
    test('completed remote peer guard rejects self-only setup records', () {
      expect(hasCompletedRemotePeer(null), false);
      expect(hasCompletedRemotePeer(pairedPeer.copyWith(publicKey: '')), false);
      expect(hasCompletedRemotePeer(pairedPeer), true);
    });

    test('rejects an unpaired peer', () {
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer.copyWith(publicKey: ''),
          localIps: const ['192.168.1.10'],
        ),
        false,
      );
    });

    test('force reconnect guard rejects an unavailable remote peer', () {
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer.copyWith(publicKey: ''),
          localIps: const ['192.168.1.10'],
        ),
        false,
      );
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer.copyWith(ip: '192.168.1.10'),
          localIps: const ['192.168.1.10'],
        ),
        false,
      );
    });

    test('rejects a zero-port endpoint', () {
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer.copyWith(port: 0),
          localIps: const ['192.168.1.10'],
        ),
        false,
      );
    });

    test('rejects the local device endpoint', () {
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer.copyWith(ip: '192.168.1.10'),
          localIps: const ['192.168.1.10'],
        ),
        false,
      );
    });

    test('accepts a completed remote endpoint', () {
      expect(
        isUsablePeerEndpoint(
          peer: pairedPeer,
          localIps: const ['192.168.1.10'],
        ),
        true,
      );
    });
  });

  group('isUsableEndpoint', () {
    test('classifies locally owned and malformed endpoints', () {
      expect(
        validateEndpoint(
          ip: '192.168.1.10',
          port: 45678,
          localIps: const ['192.168.1.10'],
        ).rejectionReason,
        EndpointRejectionReason.locallyOwned,
      );
      expect(
        validateEndpoint(
          ip: 'not-an-ip',
          port: 45678,
          localIps: const [],
        ).rejectionReason,
        EndpointRejectionReason.malformed,
      );
    });

    test('rejects invalid addresses and ports', () {
      expect(isUsableEndpoint(ip: '', port: 45678, localIps: const []), false);
      expect(
        isUsableEndpoint(ip: 'not-an-ip', port: 45678, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(ip: '192.168.1.20', port: 0, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(ip: '192.168.1.20', port: 65536, localIps: const []),
        false,
      );
    });

    test('rejects IPv4 and IPv6 loopback addresses', () {
      expect(
        isUsableEndpoint(ip: '127.0.0.1', port: 45678, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(ip: '::1', port: 45678, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(
          ip: '::ffff:127.0.0.1',
          port: 45678,
          localIps: const [],
        ),
        false,
      );
    });

    test('rejects IPv4 and IPv6 unspecified addresses', () {
      expect(
        isUsableEndpoint(ip: '0.0.0.0', port: 45678, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(ip: '::', port: 45678, localIps: const []),
        false,
      );
    });

    test('rejects every locally owned address', () {
      const localIps = ['192.168.1.10', '2001:db8::1'];
      expect(
        isUsableEndpoint(ip: '192.168.1.10', port: 45678, localIps: localIps),
        false,
      );
      expect(
        isUsableEndpoint(
          ip: '2001:0db8:0:0:0:0:0:1',
          port: 45678,
          localIps: localIps,
        ),
        false,
      );
      expect(
        isUsableEndpoint(
          ip: '::ffff:192.168.1.10',
          port: 45678,
          localIps: localIps,
        ),
        false,
      );
    });

    test('rejects a scoped local IPv6 address', () {
      expect(
        isUsableEndpoint(
          ip: 'fe80::1',
          port: 45678,
          localIps: const ['fe80::1%wlan0'],
        ),
        false,
      );
    });

    test('accepts a distinct valid endpoint', () {
      expect(
        isUsableEndpoint(
          ip: '192.168.1.20',
          port: 45678,
          localIps: const ['192.168.1.10', '2001:db8::1'],
        ),
        true,
      );
    });
  });
}
