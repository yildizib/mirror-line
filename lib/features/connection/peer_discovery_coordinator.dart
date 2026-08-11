import 'dart:async';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';

typedef OnDiscoveredIp = Future<void> Function(String ip, int port);

class PeerDiscoveryCoordinator {
  static const Duration _scanGraceDuration = Duration(seconds: 25);
  static const Duration _scanBackoff = Duration(seconds: 60);

  final Logger _logger;
  final OnDiscoveredIp _onDiscovered;
  final String Function() _getPeerId;
  final int Function() _getPeerPort;
  final String Function() _getDeviceName;
  final List<String> Function() _getAllLocalIps;

  late final BeaconListener _listener;
  late final SubnetScanner _scanner;

  DateTime? _disconnectedSince;
  DateTime? _lastScanAt;
  bool _scanning = false;
  final List<String> _beaconIps = [];

  PeerDiscoveryCoordinator({
    required this._logger,
    required this._onDiscovered,
    required this._getPeerId,
    required this._getPeerPort,
    required this._getDeviceName,
    required this._getAllLocalIps,
  }) : _listener = BeaconListener(),
       _scanner = SubnetScanner();

  List<String> get beaconIps => List.unmodifiable(_beaconIps);
  bool get isDisconnected => _disconnectedSince != null;

  Future<void> startListening() async {
    if (!_listener.isListening) {
      final selfId = _getPeerId();
      final selfName = _getDeviceName();
      final allIps = _getAllLocalIps().isNotEmpty ? _getAllLocalIps() : null;
      await _listener.start(
        onBeacon: _onBeacon,
        peerId: selfId,
        tcpPort: _getPeerPort(),
        deviceName: selfName,
        ips: allIps,
      );
    }
  }

  void markDisconnected() {
    _disconnectedSince = DateTime.now();
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

  Future<void> maybeRunFallbackScan(String? storedIp) async {
    final now = DateTime.now();
    final disconnectedSince = _disconnectedSince;

    if (disconnectedSince == null) return;
    if (_scanning) return;
    if (now.difference(disconnectedSince) < _scanGraceDuration) return;

    final lastScan = _lastScanAt;
    if (lastScan != null && now.difference(lastScan) < _scanBackoff) return;

    _scanning = true;
    _lastScanAt = now;

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
      );
      if (found != null) {
        await _onDiscovered(found, _getPeerPort());
      }
    } catch (e) {
      _logger.e('Subnet scan failed: $e');
    } finally {
      _scanning = false;
    }
  }

  Future<void> _onBeacon(BeaconInfo info) async {
    _logger.i(
      'Beacon received: ${info.deviceName} at ${info.ip}:${info.tcpPort}',
    );
    if (!_beaconIps.contains(info.ip)) {
      _beaconIps.add(info.ip);
    }
    if (info.ips.isNotEmpty) {
      for (final ip in info.ips) {
        if (!_beaconIps.contains(ip)) {
          _beaconIps.add(ip);
        }
      }
    }
    await _onDiscovered(info.ip, info.tcpPort);
  }

  Future<void> stopListening() async {
    await _listener.stop();
    _beaconIps.clear();
  }

  void dispose() {
    stopListening();
  }
}
