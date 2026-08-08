import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('broadcaster -> listener end to end', () async {
    final received = Completer<BeaconInfo>();
    final listener = BeaconListener();
    await listener.start(onBeacon: received.complete);

    final broadcaster = BeaconBroadcaster();
    await broadcaster.start(
      peerId: 'peer-777',
      tcpPort: 45678,
      deviceName: 'Pixel 8',
    );

    final info = await received.future.timeout(const Duration(seconds: 5));
    expect(info.peerId, 'peer-777');
    expect(info.tcpPort, 45678);
    expect(info.deviceName, 'Pixel 8');
    expect(info.ip, isNotEmpty);

    await broadcaster.stop();
    await listener.stop();
  }, skip: !Platform.isLinux && !Platform.isWindows);

  test('beacon is delivered via unicast to the local interface', () async {
    // Deterministic check of the full UDP path (send -> bind -> decode)
    // without relying on OS broadcast loopback behaviour.
    final localIp = await _localIp();
    expect(localIp, isNotNull, reason: 'Machine should have a non-loopback IPv4');

    final received = Completer<BeaconInfo>();
    final listener = BeaconListener();
    await listener.start(onBeacon: received.complete);

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final payload = BeaconCodec.encode(peerId: 'peer-unicast', tcpPort: 45678, deviceName: 'X');
    socket.send(utf8.encode(payload), InternetAddress(localIp!), BeaconConfig.port);

    final info = await received.future.timeout(const Duration(seconds: 5));
    expect(info.peerId, 'peer-unicast');
    expect(info.ip, isNotEmpty);

    socket.close();
    await listener.stop();
  });

  test('listener filters nothing; codec rejects foreign packets', () async {
    // Direct unit coverage for decode (no sockets needed).
    expect(BeaconCodec.decode('{"app":"evil","id":"x","port":1}', '1.2.3.4'), isNull);
    expect(BeaconCodec.decode('not json', '1.2.3.4'), isNull);
  });
}

Future<String?> _localIp() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return null;
}
