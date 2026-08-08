import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

/// Fallback peer discovery for when the passive UDP beacon isn't getting
/// through (some routers restrict broadcast/multicast even within the same
/// subnet, even with AP isolation off). Actively probes the local /24 for a
/// host with the given TCP port open.
///
/// This only confirms *something* is listening on the port -- it does not
/// prove it's the real paired peer. That's fine: the caller always follows
/// up with the normal encrypted handshake (SocketManager.connect), which
/// will simply fail against anything that isn't the genuine peer. A scan
/// is deliberately bounded (short per-host timeout, capped concurrency) so
/// it finishes quickly and doesn't become a standing battery cost -- see
/// the caller's backoff logic for how often this is allowed to run at all.
class SubnetScanner {
  final Logger _logger = Logger();

  Future<String?> findHostWithOpenPort({
    required String localIp,
    required int port,
    Duration perHostTimeout = const Duration(milliseconds: 400),
    int concurrency = 24,
  }) async {
    final base = _subnetBase(localIp);
    if (base == null) return null;

    _logger.i('Scanning $base.0/24 for port $port (fallback discovery)...');
    final candidates = List<int>.generate(254, (i) => i + 1);
    final selfLastOctet = int.tryParse(localIp.split('.').last);

    for (var start = 0; start < candidates.length; start += concurrency) {
      final batch = candidates.skip(start).take(concurrency).where((n) => n != selfLastOctet);
      final results = await Future.wait(
        batch.map((n) => _probe('$base.$n', port, perHostTimeout)),
      );
      for (final hit in results) {
        if (hit != null) {
          _logger.i('Fallback scan found a responsive host: $hit:$port');
          return hit;
        }
      }
    }
    _logger.w('Fallback scan found no responsive host on port $port.');
    return null;
  }

  Future<String?> _probe(String ip, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      return ip;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// First three octets of a dotted-quad IPv4 address, or null if it
  /// doesn't look like one. Assumes a /24 -- true for the overwhelming
  /// majority of home/consumer routers this app targets.
  String? _subnetBase(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }
}
