import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';

abstract class BeaconConfig {
  static const int port = 45679;
  static const String app = 'mirrorline';
  // Fast while disconnected (peer needs to find us ASAP), slow once a TCP
  // connection is established (the beacon is just a keep-alive fallback
  // then, so rare broadcasts spare the Wi-Fi radio during screen-off).
  static const Duration intervalFast = Duration(seconds: 3);
  static const Duration intervalSlow = Duration(seconds: 15);
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
  Duration _interval = BeaconConfig.intervalFast;

  bool get isBroadcasting => _timer != null;

  /// Switches between fast (3s, while searching for the peer) and slow
  /// (15s, once a TCP connection is established) beacon cadence without
  /// tearing down and rebinding the socket. No-op if already at the
  /// requested cadence.
  void setThrottle(bool connected) {
    final target = connected ? BeaconConfig.intervalSlow : BeaconConfig.intervalFast;
    if (target == _interval) return;
    _interval = target;
    _timer?.cancel();
    void sendOnce() async {
      final targets = await _broadcastTargets();
      for (final target in targets) {
        try {
          _socket?.send(payload, target, BeaconConfig.port);
        } catch (e) {
          _logger.w('Beacon send to $target failed: $e');
        }
      }
    }
    _timer = Timer.periodic(_interval, (_) => sendOnce());
  }

  late final Uint8List payload;

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

      payload = Uint8List.fromList(
        utf8.encode(BeaconCodec.encode(peerId: peerId, tcpPort: tcpPort, deviceName: deviceName)),
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
      _timer = Timer.periodic(_interval, (_) => sendOnce());
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
 _logger.d('Found ${interfaces.length} network interfaces for beacon broadcast');
 for (final interface in interfaces) {
 _logger.d('Interface: ${interface.name} - ${interface.addresses.map((a) => a.address).join(', ')}');
 for (final addr in interface.addresses) {
 if (addr.isLoopback) continue;
 final parts = addr.address.split('.');
 if (parts.length == 4) {
 final broadcast = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
 targets.add(broadcast);
 _logger.d('Adding broadcast target: $broadcast');
 }
 }
 }
 } catch (e) {
 _logger.e('Failed to get network interfaces: $e');
 }
 return targets.toList();
 }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Listens for UDP beacons broadcast by the paired device and also broadcasts own beacons.
/// Bidirectional beacon ensures both devices can discover each other's IP.
class BeaconListener {
  final Logger _logger = Logger();
  RawDatagramSocket? _socket;
  void Function(BeaconInfo)? _onBeacon;
  Timer? _broadcastTimer;
  Duration _interval = BeaconConfig.intervalFast;
  String? _myPeerId;
  int? _myTcpPort;
  String? _myDeviceName;

  bool get isListening => _socket != null;

  /// Switches between fast (3s) and slow (15s) beacon cadence without
  /// tearing down the listener socket. No-op if already at the requested
  /// cadence or if broadcasting isn't running.
  void setThrottle(bool connected) {
    final target = connected ? BeaconConfig.intervalSlow : BeaconConfig.intervalFast;
    if (target == _interval) return;
    _interval = target;
    if (_myPeerId != null && _myTcpPort != null && _myDeviceName != null) {
      _broadcastTimer?.cancel();
      _startBroadcasting(_myPeerId!, _myTcpPort!, _myDeviceName!);
    }
  }

  Future<void> start({
    required void Function(BeaconInfo) onBeacon,
    String? peerId,
    int? tcpPort,
    String? deviceName,
  }) async {
    await stop();
    _onBeacon = onBeacon;
    _myPeerId = peerId;
    _myTcpPort = tcpPort;
    _myDeviceName = deviceName;
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
          _logger.d('Received beacon from ${datagram.address.address}: $raw');
          final info = BeaconCodec.decode(raw, datagram.address.address);
          if (info != null) {
            _logger.i('Beacon received from ${info.deviceName} at ${info.ip}:${info.tcpPort}');
            _onBeacon?.call(info);
          } else {
            _logger.w('Invalid beacon format from ${datagram.address.address}');
          }
        }
      });
      _logger.i('Beacon listener started on port ${BeaconConfig.port}');

      if (peerId != null && tcpPort != null && deviceName != null) {
        _startBroadcasting(peerId, tcpPort, deviceName);
      }
    } catch (e) {
      _logger.e('Failed to start beacon listener: $e');
      await stop();
    }
  }

  void _startBroadcasting(String peerId, int tcpPort, String deviceName) {
    final payload = utf8.encode(
      BeaconCodec.encode(peerId: peerId, tcpPort: tcpPort, deviceName: deviceName),
    );

    void sendOnce() async {
      final targets = await _broadcastTargets();
      for (final target in targets) {
        try {
          _socket?.send(payload, target, BeaconConfig.port);
          _logger.d('Beacon sent to $target');
        } catch (e) {
          _logger.w('Beacon send to $target failed: $e');
        }
      }
    }

    sendOnce();
    _broadcastTimer = Timer.periodic(_interval, (_) => sendOnce());
    _logger.i('Beacon broadcaster started (peerId=$peerId, tcpPort=$tcpPort)');
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

  void updateBroadcastInfo({String? peerId, int? tcpPort, String? deviceName}) {
    if (peerId != null) _myPeerId = peerId;
    if (tcpPort != null) _myTcpPort = tcpPort;
    if (deviceName != null) _myDeviceName = deviceName;

    if (_broadcastTimer != null && _myPeerId != null && _myTcpPort != null && _myDeviceName != null) {
      _broadcastTimer?.cancel();
      _startBroadcasting(_myPeerId!, _myTcpPort!, _myDeviceName!);
    }
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
    _onBeacon = null;
  }
}
