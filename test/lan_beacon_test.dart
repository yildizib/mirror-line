import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';

void main() {
  group('BeaconCodec', () {
    test('encode/decode round trip', () {
      final raw = BeaconCodec.encode(
        peerId: 'peer-1',
        tcpPort: 45678,
        deviceName: 'Pixel 8',
      );

      final info = BeaconCodec.decode(raw, '192.168.1.33');
      expect(info, isNotNull);
      expect(info!.peerId, 'peer-1');
      expect(info.tcpPort, 45678);
      expect(info.deviceName, 'Pixel 8');
      expect(info.ip, '192.168.1.33');
    });

    test('decode rejects foreign app beacons', () {
      const raw = '{"app":"otherapp","v":1,"id":"x","port":1234}';
      expect(BeaconCodec.decode(raw, '10.0.0.5'), isNull);
    });

    test('decode rejects malformed payloads', () {
      expect(BeaconCodec.decode('garbage', '10.0.0.5'), isNull);
      expect(BeaconCodec.decode('', '10.0.0.5'), isNull);
      expect(BeaconCodec.decode('{"app":"mirrorline"}', '10.0.0.5'), isNull);
      expect(
        BeaconCodec.decode('{"app":"mirrorline","id":"","port":1}', '10.0.0.5'),
        isNull,
      );
      expect(
        BeaconCodec.decode(
          '{"app":"mirrorline","id":"x","port":"abc"}',
          '10.0.0.5',
        ),
        isNull,
      );
    });

    test('decode tolerates missing device name', () {
      const raw = '{"app":"mirrorline","v":1,"id":"x","port":45678}';
      final info = BeaconCodec.decode(raw, '10.0.0.5');
      expect(info, isNotNull);
      expect(info!.deviceName, '');
    });
  });
}
