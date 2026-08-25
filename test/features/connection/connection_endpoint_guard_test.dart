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
    test('rejects invalid addresses and ports', () {
      expect(
        isUsableEndpoint(ip: 'not-an-ip', port: 45678, localIps: const []),
        false,
      );
      expect(
        isUsableEndpoint(ip: '192.168.1.20', port: 0, localIps: const []),
        false,
      );
    });
  });
}
