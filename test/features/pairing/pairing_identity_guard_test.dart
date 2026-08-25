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
  });
}
