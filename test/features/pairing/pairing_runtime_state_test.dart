import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/features/pairing/pairing_runtime_state.dart';

void main() {
  final peer = Peer(
    id: 'remote-id',
    deviceName: 'Remote',
    role: 'main',
    ip: '192.168.1.20',
    port: 45678,
    key: 'key',
    publicKey: 'remote-public-key',
    createdAt: DateTime(2026),
  );

  group('resolvePairingRuntimeState', () {
    test('reports an unpaired device without a completed peer', () {
      expect(
        resolvePairingRuntimeState(
          peer: null,
          isPairingPending: false,
          isPairingComplete: false,
        ),
        PairingRuntimeState.unpaired,
      );
    });

    test('reports a pending pairing before persisted peer state', () {
      expect(
        resolvePairingRuntimeState(
          peer: null,
          isPairingPending: true,
          isPairingComplete: false,
        ),
        PairingRuntimeState.pairingPending,
      );
    });

    test('reports completion before normal paired state resumes', () {
      expect(
        resolvePairingRuntimeState(
          peer: peer,
          isPairingPending: false,
          isPairingComplete: true,
        ),
        PairingRuntimeState.pairingComplete,
      );
    });

    test('reports a persisted remote identity as paired', () {
      expect(
        resolvePairingRuntimeState(
          peer: peer,
          isPairingPending: false,
          isPairingComplete: false,
        ),
        PairingRuntimeState.paired,
      );
    });
  });
}
