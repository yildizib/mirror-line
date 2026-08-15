import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

/// First three octets of a dotted-quad IPv4 address (e.g. "192.168.1" from
/// "192.168.1.42"), or null if it doesn't look like one. Used both by
/// [SubnetScanner] (to bound its /24 scan) and by the known-network
/// reconnect cache (see KnownNetworkDao) as a permission-free stand-in for
/// "which network am I on" -- weaker than a real BSSID (two different
/// routers can share the same private subnet range) but requires no
/// location permission, which this app doesn't otherwise request.
String? subnetPrefixOf(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  return '${parts[0]}.${parts[1]}.${parts[2]}';
}

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

  /// Scans a single local /24 subnet for a host with [port] open.
  /// Returns the first responsive host IP, or null if none found.
  Future<String?> findHostWithOpenPort({
    required String localIp,
    required int port,
    Duration perHostTimeout = const Duration(milliseconds: 400),
    int concurrency = 24,
    void Function(int batch, int totalBatches, String subnet)? onProgress,
    ScanCancellationToken? cancellationToken,
  }) async {
    final base = subnetPrefixOf(localIp);
    if (base == null) return null;

    _logger.i('Scanning $base.0/24 for port $port (fallback discovery)...');
    final candidates = List<int>.generate(254, (i) => i + 1);
    final selfLastOctet = int.tryParse(localIp.split('.').last);
    final totalBatches = (candidates.length / concurrency).ceil();

    var batchIndex = 0;
    for (var start = 0; start < candidates.length; start += concurrency) {
      if (cancellationToken?.isCancelled ?? false) return null;
      batchIndex++;
      onProgress?.call(batchIndex, totalBatches, base);
      final batch = candidates
          .skip(start)
          .take(concurrency)
          .where((n) => n != selfLastOctet);
      final results = await Future.wait(
        batch.map((n) => _probe('$base.$n', port, perHostTimeout)),
      );
      if (cancellationToken?.isCancelled ?? false) return null;
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

  /// Scans **multiple** local subnets in parallel (e.g. WiFi `192.168.1.0/24`
  /// + VPN `10.8.0.0/24`). This is essential for VPN support: the peer may
  /// be on the VPN subnet while the device also has a WiFi interface.
  ///
  /// [localIps] is the list of local IPs (one per interface) to scan the
  /// /24 of. Each is scanned independently in parallel; the first hit
  /// across all subnets wins.
  ///
  /// [onProgress] reports per-subnet progress: `(batch, totalBatches, subnet)`
  /// where `subnet` is the prefix (e.g. "192.168.1" or "10.8.0"). Since
  /// multiple subnets scan in parallel, the callback may interleave
  /// progress from different subnets -- the caller should display the
  /// latest.
  Future<String?> findHostWithOpenPortMulti({
    required List<String> localIps,
    required int port,
    Duration perHostTimeout = const Duration(milliseconds: 400),
    int concurrency = 24,
    void Function(int batch, int totalBatches, String subnet)? onProgress,
    ScanCancellationToken? cancellationToken,
  }) async {
    if (localIps.isEmpty) return null;
    if (localIps.length == 1) {
      return findHostWithOpenPort(
        localIp: localIps.first,
        port: port,
        perHostTimeout: perHostTimeout,
        concurrency: concurrency,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    _logger.i(
      'Scanning ${localIps.length} subnets in parallel for port $port...',
    );

    // Race all subnet scans in parallel. First hit cancels future batches
    // and suppresses stale progress from the losing scans.
    final completer = Completer<String?>();
    final raceToken = ScanCancellationToken(parent: cancellationToken);
    var pending = localIps.length;

    for (final ip in localIps) {
      findHostWithOpenPort(
            localIp: ip,
            port: port,
            perHostTimeout: perHostTimeout,
            concurrency: concurrency,
            onProgress: (batch, total, subnet) {
              if (!raceToken.isCancelled) {
                onProgress?.call(batch, total, subnet);
              }
            },
            cancellationToken: raceToken,
          )
          .then((found) {
            pending--;
            if (found != null && !completer.isCompleted) {
              raceToken.cancel();
              completer.complete(found);
            } else if (pending == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            pending--;
            if (pending == 0 && !completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          });
    }

    return completer.future;
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
}

class ScanCancellationToken {
  ScanCancellationToken({this.parent});

  final ScanCancellationToken? parent;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled || (parent?.isCancelled ?? false);

  void cancel() => _isCancelled = true;
}
