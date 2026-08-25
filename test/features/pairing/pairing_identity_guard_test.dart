import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/pairing/pairing_identity_guard.dart';

void main() {
  group('isValidRemoteIdentity', () {
    test('accepts a distinct complete remote identity', () {
      expect(
        isValidRemoteIdentity(
          remoteId: 'remote-id',
          remotePublicKey: 'remote-key',
          localId: 'local-id',
          localPublicKey: 'local-key',
        ),
        true,
      );
    });

    test('rejects a self identity', () {
      expect(
        isValidRemoteIdentity(
          remoteId: 'local-id',
          remotePublicKey: 'local-key',
          localId: 'local-id',
          localPublicKey: 'local-key',
        ),
        false,
      );
    });

    test('rejects incomplete identity material', () {
      expect(
        isValidRemoteIdentity(
          remoteId: 'remote-id',
          remotePublicKey: '',
          localId: 'local-id',
          localPublicKey: 'local-key',
        ),
        false,
      );
    });

    test('rejects an identity with a mismatched public key', () {
      expect(
        isValidRemoteIdentity(
          remoteId: 'remote-id',
          remotePublicKey: 'local-key',
          localId: 'local-id',
          localPublicKey: 'local-key',
        ),
        false,
      );
    });

    test('accepts a retry identity after a failed transaction', () {
      expect(
        isValidRemoteIdentity(
          remoteId: 'new-remote-id',
          remotePublicKey: 'new-remote-key',
          localId: 'local-id',
          localPublicKey: 'local-key',
        ),
        true,
      );
    });
  });

  group('isExpectedPairingAck', () {
    test('accepts an ack matching the active transaction and peer', () {
      expect(
        isExpectedPairingAck(
          transactionId: 'transaction-id',
          peerId: 'peer-id',
          peerPublicKey: 'peer-key',
          expectedTransactionId: 'transaction-id',
          expectedPeerId: 'peer-id',
          expectedPeerPublicKey: 'peer-key',
        ),
        true,
      );
    });

    test('rejects an ack when no transaction is active', () {
      expect(
        isExpectedPairingAck(
          transactionId: 'transaction-id',
          peerId: 'peer-id',
          peerPublicKey: 'peer-key',
          expectedTransactionId: null,
          expectedPeerId: null,
          expectedPeerPublicKey: null,
        ),
        false,
      );
    });

    test('rejects an ack for another transaction', () {
      expect(
        isExpectedPairingAck(
          transactionId: 'stale-transaction-id',
          peerId: 'peer-id',
          peerPublicKey: 'peer-key',
          expectedTransactionId: 'transaction-id',
          expectedPeerId: 'peer-id',
          expectedPeerPublicKey: 'peer-key',
        ),
        false,
      );
    });

    test('rejects an ack from another peer identity', () {
      expect(
        isExpectedPairingAck(
          transactionId: 'transaction-id',
          peerId: 'other-peer-id',
          peerPublicKey: 'other-peer-key',
          expectedTransactionId: 'transaction-id',
          expectedPeerId: 'peer-id',
          expectedPeerPublicKey: 'peer-key',
        ),
        false,
      );
    });

    test('rejects malformed ack identity fields', () {
      expect(
        isExpectedPairingAck(
          transactionId: 42,
          peerId: ['peer-id'],
          peerPublicKey: {'value': 'peer-key'},
          expectedTransactionId: 'transaction-id',
          expectedPeerId: 'peer-id',
          expectedPeerPublicKey: 'peer-key',
        ),
        false,
      );
    });
  });
}
