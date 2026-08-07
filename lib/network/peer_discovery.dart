import 'dart:io';

import 'package:logger/logger.dart';

class PeerDiscovery {
  static const String _serviceType = '_mirrorline._tcp';
  final Logger _logger = Logger();

  String get serviceType => _serviceType;

  /// Returns the device's local IPv4 address on the LAN.
  /// Supports all private ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.
  /// Falls back to the first non-loopback IPv4 address.
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? fallback;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (_isPrivateIp(ip)) return ip;
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (e) {
      _logger.e('Failed to get local IP: $e');
    }
    return null;
  }

  static bool _isPrivateIp(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 16 && second <= 31) return true;
    }
    return false;
  }
}
