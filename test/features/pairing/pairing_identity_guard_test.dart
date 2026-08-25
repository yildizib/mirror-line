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
}
