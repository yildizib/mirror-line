import 'package:mirrorline/features/connection/connection_status_provider.dart';

/// Orchestrates parallel discovery and connection attempts for force-connect.
/// Decouples discovery logic from ConnectionNotifier for unit testing.
class ForceConnectStrategy {
  final String? storedIp;
  final List<String> beaconIps;
  final List<String> allLocalIps;
  final String? localIp;
  final String peerId;
  final int peerPort;

  /// Called to attempt a connection to a candidate IP.
  /// Returns true if successfully connected.
  final Future<bool> Function(
    String ip,
    int port,
    ConnectionStatusNotifier statusNotifier,
    {required String label, Duration? connectTimeout}
  ) connectWithProgress;

  /// Called to look up cached IPs for the current subnet.
  final Future<List<String>> Function(
    ConnectionStatusNotifier statusNotifier,
    String peerId,
  ) lookupKnownNetworkIp;

  /// Called to scan subnets for the peer.
  final Future<String?> Function(
    List<String> scanIps,
    int port,
    ConnectionStatusNotifier statusNotifier,
  ) scanSubnetsWithProgress;

  /// Called to record a successfully discovered address.
  final Function(String ip, int port) recordDiscoveredAddress;

  ForceConnectStrategy({
    required this.storedIp,
    required this.beaconIps,
    required this.allLocalIps,
    required this.localIp,
    required this.peerId,
    required this.peerPort,
    required this.connectWithProgress,
    required this.lookupKnownNetworkIp,
    required this.scanSubnetsWithProgress,
    required this.recordDiscoveredAddress,
  });

  /// Executes parallel discovery and connection strategy.
  /// Returns true if connected, false if all paths failed.
  /// [isConnected] callback to check current connection state.
  /// [isConnecting] callback to check if a connection is in flight.
  Future<bool> execute(
    ConnectionStatusNotifier statusNotifier,
    bool Function() isConnected,
    bool Function() isConnecting,
  ) async {
    if (storedIp == null || storedIp!.isEmpty) {
      statusNotifier.logDiscovery('No peer configured.', isError: true);
      return false;
    }

    final candidateFutures = <Future<List<String>>>[];

    // Path 1: stored IP + beacon IPs.
    if (storedIp!.isNotEmpty && storedIp != 'unknown') {
      final candidates = <String>[storedIp!, ...beaconIps.where((ip) => ip != storedIp)];
      statusNotifier.logDiscovery('Trying stored/beacon IPs: ${candidates.join(', ')}...');
      candidateFutures.add(Future.value(candidates));
    } else if (beaconIps.isNotEmpty) {
      statusNotifier.logDiscovery('Trying beacon IPs: ${beaconIps.join(', ')}...');
      candidateFutures.add(Future.value(beaconIps));
    }

    // Path 2: known-network cache.
    candidateFutures.add(lookupKnownNetworkIp(statusNotifier, peerId));

    // Path 3: subnet scan (parallel with paths 1+2).
    final scanIps = allLocalIps.isNotEmpty ? allLocalIps : (localIp != null ? [localIp!] : <String>[]);
    final scanCandidates = <String>{};
    if (scanIps.isNotEmpty) {
      candidateFutures.add(
        scanSubnetsWithProgress(scanIps, peerPort, statusNotifier).then((found) {
          if (found != null) {
            statusNotifier.logDiscovery('Scan found host: $found', isSuccess: true);
            scanCandidates.add(found);
            return [found];
          }
          return <String>[];
        }),
      );
    }

    // Collect candidates as they arrive.
    final allCandidates = <String>{};
    var discoveryDone = false;

    for (final f in candidateFutures) {
      f.then((ips) {
        for (final ip in ips) {
          if (!discoveryDone && !isConnected()) {
            allCandidates.add(ip);
          }
        }
      });
    }

    // Phase 2: connect to candidates as they arrive.
    await Future.delayed(const Duration(milliseconds: 200));

    var completedCount = 0;
    final totalCount = candidateFutures.length;
    for (final f in candidateFutures) {
      f.then((_) => completedCount++);
    }

    while (!isConnected() && !isConnecting()) {
      if (allCandidates.isNotEmpty) {
        final ip = allCandidates.first;
        allCandidates.remove(ip);
        final isScanCandidate = scanCandidates.contains(ip);
        final timeout = isScanCandidate ? null : const Duration(milliseconds: 1500);
        final ok = await connectWithProgress(
          ip,
          peerPort,
          statusNotifier,
          label: ip,
          connectTimeout: timeout,
        );
        if (ok) {
          recordDiscoveredAddress(ip, peerPort);
          statusNotifier.logDiscovery('Connected to $ip!', isSuccess: true);
          discoveryDone = true;
          return true;
        }
        statusNotifier.logDiscovery('Failed to connect to $ip.', isError: true);
      } else {
        if (completedCount >= totalCount) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (isConnected()) {
      statusNotifier.logDiscovery('Connected!', isSuccess: true);
      discoveryDone = true;
      return true;
    }

    statusNotifier.logDiscovery('All discovery paths failed.', isError: true);
    discoveryDone = true;
    return false;
  }
}
