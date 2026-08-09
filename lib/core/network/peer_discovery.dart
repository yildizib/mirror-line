import 'dart:io';

import 'package:logger/logger.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';

/// A local IPv4 address on a network interface, paired with the
/// interface name (e.g. "wlan0", "tun0") so callers can distinguish
/// WiFi from VPN from cellular.
class LocalIpInfo {
  final String ip;
  final String interfaceName;

  const LocalIpInfo({required this.ip, required this.interfaceName});

  @override
  String toString() => '$ip ($interfaceName)';
}

class PeerDiscovery {
  final Logger _logger = Logger();

  /// Returns the device's local IPv4 address on the LAN.
  ///
  /// On Android the native platform channel is used first
  /// (ConnectivityManager/LinkProperties — reliable), because
  /// dart:io's NetworkInterface.list often returns the cellular
  /// interface or nothing at all on Android.
  /// Falls back to dart:io for other platforms and edge cases.
  ///
  /// **Note:** This returns only one IP. For VPN support (where the
  /// device may have WiFi + VPN TUN interfaces simultaneously), use
  /// [getAllLocalIps] instead.
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

  /// Returns **all** private IPv4 addresses on all non-loopback network
  /// interfaces (WiFi, VPN TUN, ethernet, etc.). This is essential for
  /// VPN support: when a device is on WiFi + OpenVPN, it has two private
  /// IPs (e.g. `192.168.1.42` on wlan0 and `10.8.0.3` on tun0) and the
  /// peer could be reachable on either one.
  ///
  /// Cellular interfaces (rmnet) are excluded — their IPs are public
  /// (carrier-grade NAT) and not directly reachable from another device
  /// on a VPN.
  ///
  /// The native Android channel is used first for the "active" network
  /// IP (most reliable), then dart:io supplements with any additional
  /// interfaces (e.g. VPN TUN) that the native channel might not surface.
  Future<List<LocalIpInfo>> getAllLocalIps() async {
    final result = <LocalIpInfo>[];
    final seen = <String>{};

    // 1) Native (Android): active network's real IPv4 — add first so
    //    it's preferred by callers that pick the first entry.
    try {
      final native = await TelephonyChannel.getLocalIp();
      if (native != null && native.isNotEmpty && _isPrivateIp(native)) {
        seen.add(native);
        result.add(LocalIpInfo(ip: native, interfaceName: 'native-active'));
      }
    } catch (e) {
      _logger.w('Native getLocalIp failed: $e');
    }

    // 2) dart:io: enumerate all interfaces, add any private IPv4 we
    //    haven't already added from native. This picks up VPN TUN
    //    interfaces that the native ConnectivityManager might not
    //    report as the "active" network.
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (!_isPrivateIp(ip)) continue; // skip cellular/public IPs
          if (seen.contains(ip)) continue;
          seen.add(ip);
          result.add(LocalIpInfo(ip: ip, interfaceName: interface.name));
        }
      }
    } catch (e) {
      _logger.e('Failed to enumerate network interfaces: $e');
    }

    // VPN preference: if a TUN interface is present, move its IP to the
    // front. The VPN IP is reachable from any device on the same VPN,
    // whereas the 5G/WiFi IP may be behind carrier NAT or on a different
    // subnet. Callers that pick the first entry (Settings display, QR
    // encoding) will then prefer the VPN IP.
    final vpnIndex = result.indexWhere((e) =>
        e.interfaceName.contains('tun') || e.interfaceName.contains('tap'));
    if (vpnIndex > 0) {
      final vpn = result.removeAt(vpnIndex);
      result.insert(0, vpn);
      _logger.d('VPN IP preferred: ${vpn.ip} moved to front');
    }

    _logger.d('getAllLocalIps: ${result.map((e) => e.toString()).join(', ')}');
    return result;
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