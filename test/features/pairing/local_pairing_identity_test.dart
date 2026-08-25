import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/pairing/local_pairing_identity.dart';

void main() {
  test('QR payload contains only the resolved local identity', () {
    const identity = LocalPairingIdentity(
      id: 'local-id',
      deviceName: 'Local Device',
      role: 'source',
      publicKey: 'local-public-key',
      ip: '10.8.0.4',
      port: 45678,
      keyBase64: 'shared-key',
    );

    expect(
      identity.qrData,
      'local-id|10.8.0.4|45678|shared-key|Local Device|source|local-public-key',
    );
    expect(identity.qrData, isNot(contains('remote')));
    expect(identity.isReadyForQr, true);
  });

  test('QR is unavailable for missing or placeholder identity fields', () {
    const missingKey = LocalPairingIdentity(
      id: 'local-id',
      deviceName: 'Local Device',
      role: 'source',
      publicKey: '',
      ip: '10.8.0.4',
      port: 45678,
      keyBase64: 'shared-key',
    );
    const placeholderName = LocalPairingIdentity(
      id: 'local-id',
      deviceName: 'Unknown Device',
      role: 'source',
      publicKey: 'local-public-key',
      ip: '10.8.0.4',
      port: 45678,
      keyBase64: 'shared-key',
    );

    expect(missingKey.isReadyForQr, false);
    expect(placeholderName.isReadyForQr, false);
  });

  test('QR is unavailable for stale or unusable endpoints', () {
    const unknownEndpoint = LocalPairingIdentity(
      id: 'local-id',
      deviceName: 'Local Device',
      role: 'main',
      publicKey: 'local-public-key',
      ip: 'unknown',
      port: 45678,
      keyBase64: 'shared-key',
    );
    const loopbackEndpoint = LocalPairingIdentity(
      id: 'local-id',
      deviceName: 'Local Device',
      role: 'main',
      publicKey: 'local-public-key',
      ip: '127.0.0.1',
      port: 45678,
      keyBase64: 'shared-key',
    );

    expect(unknownEndpoint.isReadyForQr, false);
    expect(loopbackEndpoint.isReadyForQr, false);
  });
}
