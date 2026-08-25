import 'dart:async';
import 'package:logger/logger.dart';

typedef OnReconnect = Future<bool> Function(String ip, int port);

Duration reconnectDelayForAttempt(int attempt) {
  final exponent = attempt.clamp(0, 4);
  final delay = const Duration(seconds: 2) * (1 << exponent);
  return delay > const Duration(seconds: 30)
      ? const Duration(seconds: 30)
      : delay;
}

class ReconnectScheduler {
  final Logger _logger;
  final OnReconnect _onReconnect;
  final String? Function() _getPeerIp;
  final int Function() _getPeerPort;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _connectGeneration = 0;
  DateTime? _disconnectedSince;

  ReconnectScheduler({
    required this._logger,
    required this._onReconnect,
    required this._getPeerIp,
    required this._getPeerPort,
  });

  bool get isDisconnected => _disconnectedSince != null;
  int get generation => _connectGeneration;

  void markDisconnected() {
    _disconnectedSince ??= DateTime.now();
    scheduleReconnect();
  }

  void markConnected() {
    _disconnectedSince = null;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void forceReconnect() {
    _connectGeneration++;
    _reconnectAttempts = 0;
    _disconnectedSince = null;
    scheduleReconnect();
  }

  void invalidate() {
    _connectGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectedSince = null;
  }

  void scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = reconnectDelayForAttempt(_reconnectAttempts);
    _logger.i(
      'Scheduling reconnect in ${delay.inSeconds}s (attempt ${_reconnectAttempts + 1}).',
    );
    _reconnectTimer = Timer(delay, () async {
      await _tryConnect();
    });
  }

  Future<void> _tryConnect() async {
    final ip = _getPeerIp();
    final port = _getPeerPort();
    if (ip == null || ip.isEmpty || port <= 0 || port > 65535) {
      _logger.w('No usable peer endpoint available for reconnect.');
      scheduleReconnect();
      return;
    }
    await _connectTo(ip, port);
  }

  Future<void> _connectTo(String ip, int port) async {
    final generation = ++_connectGeneration;
    const timeout = Duration(seconds: 15);
    try {
      _logger.i('Attempting connection to $ip:$port (gen=$generation)...');
      final connected = await _onReconnect(ip, port).timeout(timeout);
      if (!connected) {
        throw StateError('Reconnect callback reported failure.');
      }
      // Connection succeeded; markConnected() is called by ConnectionFacade
    } catch (e) {
      if (generation != _connectGeneration) {
        _logger.d(
          'Stale connection attempt (gen=$generation), ignoring result.',
        );
        return;
      }
      _logger.e('Connection attempt failed: $e');
      _reconnectAttempts++;
      scheduleReconnect();
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
  }
}
