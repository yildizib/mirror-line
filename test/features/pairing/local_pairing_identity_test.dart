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

  final unavailableCases = <(String, LocalPairingIdentity)>[
    ('empty ID', _identity(id: '')),
    ('empty name', _identity(deviceName: '')),
    ('Unknown Device placeholder', _identity(deviceName: 'Unknown Device')),
    ('Android Device placeholder', _identity(deviceName: 'Android Device')),
    ('empty public key', _identity(publicKey: '')),
    ('empty pairing key', _identity(keyBase64: '')),
    ('invalid role', _identity(role: 'viewer')),
    ('invalid port', _identity(port: 0)),
    ('malformed endpoint', _identity(ip: 'not-an-ip')),
    ('unknown endpoint', _identity(ip: 'unknown')),
    ('IPv4 loopback endpoint', _identity(ip: '127.0.0.1')),
    ('IPv6 loopback endpoint', _identity(ip: '::1')),
  ];

  for (final unavailableCase in unavailableCases) {
    test('QR is unavailable for ${unavailableCase.$1}', () {
      expect(unavailableCase.$2.isReadyForQr, isFalse);
    });
  }
}

LocalPairingIdentity _identity({
  String id = 'local-id',
  String deviceName = 'Local Device',
  String role = 'source',
  String publicKey = 'local-public-key',
  String ip = '10.8.0.4',
  int port = 45678,
  String keyBase64 = 'shared-key',
}) {
  return LocalPairingIdentity(
    id: id,
    deviceName: deviceName,
    role: role,
    publicKey: publicKey,
    ip: ip,
    port: port,
    keyBase64: keyBase64,
  );
}
