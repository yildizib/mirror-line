import 'dart:io';

import 'package:logger/logger.dart';

import '../telephony/telephony_channel.dart';

class PeerDiscovery {
  final Logger _logger = Logger();

  /// Returns the device's local IPv4 address on the LAN.
  ///
  /// On Android the native platform channel is used first
  /// (ConnectivityManager/LinkProperties — reliable), because
  /// dart:io's NetworkInterface.list often returns the cellular
  /// interface or nothing at all on Android.
  /// Falls back to dart:io for other platforms and edge cases.
  Future<String?> getLocalIp() async {
    // 1) Native (Android): active network's real IPv4.
    try {
      final native = await TelephonyChannel.getLocalIp();
      if (native != null && native.isNotEmpty) {
        return native;
      }
    } catch (e) {
      _logger.w('Native getLocalIp failed: $e');
    }

    // 2) dart:io fallback: first private IPv4, else first non-loopback IPv4.
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
