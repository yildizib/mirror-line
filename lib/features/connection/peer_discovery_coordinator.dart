import 'dart:async';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';

/// [fromScan] distinguishes a rare, expensive active-scan discovery (worth
/// abandoning an in-flight connect attempt for) from a routine, frequent
/// beacon discovery (worth skipping if an attempt is already in flight) --
/// the two call sites apply different in-flight-attempt policies, mirroring
/// the pre-extraction behavior this coordinator replaces.
typedef OnDiscoveredIp =
    Future<void> Function(String ip, int port, {required bool fromScan});

class PeerDiscoveryCoordinator {
  static const Duration _scanGraceDuration = Duration(seconds: 25);
  static const Duration _scanBackoff = Duration(seconds: 60);

  final Logger _logger;
  final OnDiscoveredIp _onDiscovered;
  final String Function() _getPeerId;
  final int Function() _getPeerPort;
  final String Function() _getDeviceName;
  final List<String> Function() _getAllLocalIps;
  // The *paired* peer's id, used to ignore beacons from an unrelated device
  // (e.g. another MirrorLine install on the same LAN) -- distinct from
  // _getPeerId, which is this device's own self-identity broadcast
  // alongside listening.
  final String? Function() _getExpectedPeerId;

  late final BeaconListener _listener;
  late final SubnetScanner _scanner;

  DateTime? _disconnectedSince;
  DateTime? _lastScanAt;
  bool _scanning = false;
  bool _disposed = false;
  ScanCancellationToken? _scanCancellation;
  final List<String> _beaconIps = [];

  PeerDiscoveryCoordinator({
    required this._logger,
    required this._onDiscovered,
    required this._getPeerId,
    required this._getPeerPort,
    required this._getDeviceName,
    required this._getAllLocalIps,
    required this._getExpectedPeerId,
  }) : _listener = BeaconListener(),
       _scanner = SubnetScanner();

  List<String> get beaconIps => List.unmodifiable(_beaconIps);
  bool get isDisconnected => _disconnectedSince != null;

  Future<void> startListening() async {
    if (_disposed) return;
    if (!_listener.isListening) {
      final selfId = _getPeerId();
      final selfName = _getDeviceName();
      final allIps = _getAllLocalIps().isNotEmpty ? _getAllLocalIps() : null;
      await _listener.start(
        onBeacon: handleBeacon,
        peerId: selfId,
        tcpPort: _getPeerPort(),
        deviceName: selfName,
        ips: allIps,
      );
    }
  }

  void markDisconnected() {
    // First-wins, not overwrite: repeated disconnect signals (e.g. an
    // offline event followed by the socket's own onDisconnected) must not
    // keep resetting the clock the grace period is measured from --
    // matches ReconnectScheduler.markDisconnected()'s same `??=` pattern.
    _disconnectedSince ??= DateTime.now();
  }

  void markConnected() {
    _disconnectedSince = null;
    _beaconIps.clear();
    _lastScanAt = null;
  }

  void updateBeaconInfo() {
    final allIps = _getAllLocalIps().isNotEmpty ? _getAllLocalIps() : null;
    _listener.updateBroadcastInfo(
      peerId: _getPeerId(),
      tcpPort: _getPeerPort(),
      deviceName: _getDeviceName(),
      ips: allIps,
    );
  }

  void setThrottle(bool connected) {
    _listener.setThrottle(connected);
  }

  /// [immediate] skips the grace-period wait -- used when the caller
  /// already has a concrete reason to believe the network changed, rather
  /// than just "haven't heard from the peer in a while". [force]
  /// additionally bypasses [_scanBackoff] -- reserved for a user-facing
  /// "force reconnect" action. The re-entrancy guard ([_scanning]) applies
  /// either way.
  Future<void> maybeRunFallbackScan({
    bool immediate = false,
    bool force = false,
  }) async {
    if (_disposed || _scanning) return;

    if (!immediate) {
      final disconnectedSince = _disconnectedSince;
      if (disconnectedSince == null) return;
      if (DateTime.now().difference(disconnectedSince) < _scanGraceDuration) {
        return;
      }
    }

    if (!force) {
      final lastScan = _lastScanAt;
      if (lastScan != null &&
          DateTime.now().difference(lastScan) < _scanBackoff) {
        return;
      }
    }

    _scanning = true;
    _lastScanAt = DateTime.now();
    final cancellation = ScanCancellationToken();
    _scanCancellation = cancellation;

    try {
      final scanIps = _getAllLocalIps().isNotEmpty
          ? _getAllLocalIps()
          : <String>[];
      if (scanIps.isEmpty) {
        _logger.i('No local IPs for subnet scan.');
        return;
      }

      _logger.i('Running fallback subnet scan...');
      final found = await _scanner.findHostWithOpenPortMulti(
        localIps: scanIps,
        port: _getPeerPort(),
        cancellationToken: cancellation,
      );
      if (found != null && !cancellation.isCancelled && !_disposed) {
        await _onDiscovered(found, _getPeerPort(), fromScan: true);
      }
    } catch (e) {
      _logger.e('Subnet scan failed: $e');
    } finally {
      if (identical(_scanCancellation, cancellation)) {
        _scanCancellation = null;
        _scanning = false;
      }
    }
  }

  Future<void> handleBeacon(BeaconInfo info) async {
    final expectedPeerId = _getExpectedPeerId();
    if (expectedPeerId != null && info.peerId != expectedPeerId) {
      _logger.w('Ignoring beacon from unknown peer: ${info.peerId}');
      return;
    }
    _logger.i(
      'Beacon received: ${info.deviceName} at ${info.ip}:${info.tcpPort}',
    );

    // The datagram source IP may be unreachable from this device (e.g. the
    // peer is on VPN but the OS chose a different interface as the UDP
    // source). Prefer a same-subnet IP or a VPN-style IP the peer claims,
    // falling back to the raw datagram source IP.
    final bestIp = _pickBestBeaconIp(info);

    // Replace wholesale (not accumulate/dedupe): stale IPs from an earlier
    // beacon shouldn't linger once a newer beacon reports a different set.
    _beaconIps
      ..clear()
      ..addAll(info.ips);

    await _onDiscovered(bestIp, info.tcpPort, fromScan: false);
  }

  /// Picks the most likely-reachable IP from a beacon. Prefers:
  /// 1. An IP on the same /24 as one of our local IPs (same subnet).
  /// 2. Any VPN-style IP (10.x, 172.16-31.x) the peer claims.
  /// 3. The datagram source IP (fallback).
  String _pickBestBeaconIp(BeaconInfo info) {
    final sourceIp = info.ip;
    final allPeerIps = {sourceIp, ...info.ips};
    final allLocalIps = _getAllLocalIps();

    for (final peerIp in allPeerIps) {
      final peerPrefix = subnetPrefixOf(peerIp);
      if (peerPrefix == null) continue;
      for (final localIp in allLocalIps) {
        if (subnetPrefixOf(localIp) == peerPrefix) {
          return peerIp; // same subnet, directly reachable
        }
      }
    }

    for (final peerIp in allPeerIps) {
      if (peerIp.startsWith('10.')) return peerIp;
    }

    return sourceIp;
  }

  Future<void> stopListening() async {
    cancelActiveScan();
    await _listener.stop();
    _beaconIps.clear();
  }

  void cancelActiveScan() {
    _scanCancellation?.cancel();
    _scanCancellation = null;
    _scanning = false;
  }

  void dispose() {
    _disposed = true;
    cancelActiveScan();
    unawaited(stopListening());
  }
}
