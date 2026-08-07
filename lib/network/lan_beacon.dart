import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';

abstract class BeaconConfig {
  static const int port = 45679;
  static const String app = 'mirrorline';
  static const Duration interval = Duration(seconds: 3);
}

class BeaconInfo {
  final String peerId;
  final int tcpPort;
  final String deviceName;
  final String ip;

  const BeaconInfo({
    required this.peerId,
    required this.tcpPort,
    required this.deviceName,
    required this.ip,
  });

  @override
  String toString() => 'BeaconInfo($peerId, $ip:$tcpPort, $deviceName)';
}

class BeaconCodec {
  static String encode({
    required String peerId,
    required int tcpPort,
    required String deviceName,
  }) =>
      jsonEncode({
        'app': BeaconConfig.app,
        'v': 1,
        'id': peerId,
        'port': tcpPort,
        'name': deviceName,
      });

  static BeaconInfo? decode(String raw, String senderIp) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      if (map['app'] != BeaconConfig.app) return null;
      final id = map['id'];
      final port = map['port'];
      if (id is! String || id.isEmpty) return null;
      if (port is! int) return null;
      return BeaconInfo(
        peerId: id,
        tcpPort: port,
        deviceName: map['name'] is String ? map['name'] as String : '',
        ip: senderIp,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Periodically broadcasts a UDP beacon on the LAN so that the paired
/// 'main' device can discover this device's current IP address.
class BeaconBroadcaster {
  final Logger _logger = Logger();
  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isBroadcasting => _timer != null;

  Future<void> start({
    required String peerId,
    required int tcpPort,
    required String deviceName,
  }) async {
    await stop();
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      _socket = socket;

      final payload = utf8.encode(
        BeaconCodec.encode(peerId: peerId, tcpPort: tcpPort, deviceName: deviceName),
      );

      void sendOnce() async {
        final targets = await _broadcastTargets();
        for (final target in targets) {
          try {
            socket.send(payload, target, BeaconConfig.port);
          } catch (e) {
            _logger.w('Beacon send to $target failed: $e');
          }
        }
      }

      sendOnce();
      _timer = Timer.periodic(BeaconConfig.interval, (_) => sendOnce());
      _logger.i('Beacon broadcaster started (peerId=$peerId, tcpPort=$tcpPort)');
    } catch (e) {
      _logger.e('Failed to start beacon broadcaster: $e');
      await stop();
    }
  }

  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
          }
        }
      }
    } catch (_) {}
    return targets.toList();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Listens for UDP beacons broadcast by the paired 'source' device.
class BeaconListener {
  final Logger _logger = Logger();
  RawDatagramSocket? _socket;
  void Function(BeaconInfo)? _onBeacon;

  bool get isListening => _socket != null;

  Future<void> start({required void Function(BeaconInfo) onBeacon}) async {
    await stop();
    _onBeacon = onBeacon;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        BeaconConfig.port,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _socket = socket;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final raw = utf8.decode(datagram!.data, allowMalformed: true);
          final info = BeaconCodec.decode(raw, datagram.address.address);
          if (info != null) {
            _onBeacon?.call(info);
          }
        }
      });
      _logger.i('Beacon listener started on port ${BeaconConfig.port}');
    } catch (e) {
      _logger.e('Failed to start beacon listener: $e');
      await stop();
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _onBeacon = null;
  }
}
