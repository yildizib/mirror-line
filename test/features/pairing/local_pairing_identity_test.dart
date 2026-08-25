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
  });
}
