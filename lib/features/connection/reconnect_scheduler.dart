import 'dart:async';
import 'package:logger/logger.dart';

typedef OnReconnect = Future<void> Function(String ip, int port);

class ReconnectScheduler {
  static const Duration _reconnectInitialDelay = Duration(seconds: 2);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);

  final Logger _logger;
  final OnReconnect _onReconnect;
  final String? Function() _getPeerIp;
  final int Function() _getPeerPort;
  final Duration initialDelay;
  final Duration maxDelay;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _connectGeneration = 0;
  DateTime? _disconnectedSince;
  bool _attemptInFlight = false;
  bool _paused = false;
  bool _stopped = false;
  bool _disposed = false;

  ReconnectScheduler({
    required this._logger,
    required this._onReconnect,
    required this._getPeerIp,
    required this._getPeerPort,
    this.initialDelay = _reconnectInitialDelay,
    this.maxDelay = _reconnectMaxDelay,
  });

  bool get isDisconnected => _disconnectedSince != null;
  bool get isStopped => _stopped;
  bool get isPaused => _paused;
  bool get isDisposed => _disposed;
  bool get hasAttemptInFlight => _attemptInFlight;
  int get generation => _connectGeneration;

  void start() {
    if (_disposed) return;
    _stopped = false;
    _paused = false;
  }

  void markDisconnected({bool schedule = true}) {
    if (_paused || _stopped || _disposed) return;
    _disconnectedSince ??= DateTime.now();
    if (schedule) scheduleReconnect();
  }

  void markConnected() {
    _paused = false;
    _disconnectedSince = null;
    _reconnectAttempts = 0;
    _cancelPendingWork();
  }

  void forceReconnect() {
    if (_stopped || _disposed) return;
    _paused = false;
    _connectGeneration++;
    _reconnectAttempts = 0;
    _disconnectedSince ??= DateTime.now();
    scheduleReconnect();
  }

  void scheduleReconnect() {
    if (_paused || _stopped || _disposed || _attemptInFlight) return;
    _reconnectTimer?.cancel();
    final exponent = _reconnectAttempts.clamp(0, 4);
    var delay = initialDelay * (1 << exponent);
    if (delay > maxDelay) delay = maxDelay;
    _logger.i(
      'Scheduling reconnect in ${delay.inSeconds}s (attempt ${_reconnectAttempts + 1}).',
    );
    _reconnectTimer = Timer(delay, () async {
      await _tryConnect();
    });
  }

  Future<void> _tryConnect() async {
    if (_paused || _stopped || _disposed || _attemptInFlight) return;
    final ip = _getPeerIp();
    final port = _getPeerPort();
    if (ip == null || ip.isEmpty) {
      _logger.w('No peer IP available for reconnect.');
      _reconnectAttempts++;
      scheduleReconnect();
      return;
    }
    await _connectTo(ip, port);
  }

  Future<void> _connectTo(String ip, int port) async {
    final generation = ++_connectGeneration;
    const timeout = Duration(seconds: 15);
    _attemptInFlight = true;
    try {
      _logger.i('Attempting connection to $ip:$port (gen=$generation)...');
      await _onReconnect(ip, port).timeout(timeout);
      // Connection succeeded; markConnected() is called by ConnectionFacade
    } catch (e) {
      if (generation != _connectGeneration || _stopped || _disposed) {
        _logger.d(
          'Stale connection attempt (gen=$generation), ignoring result.',
        );
        return;
      }
      _logger.e('Connection attempt failed: $e');
      _reconnectAttempts++;
    } finally {
      _attemptInFlight = false;
      if (_disconnectedSince != null && !_paused && !_stopped && !_disposed) {
        scheduleReconnect();
      }
    }
  }

  void pause() {
    _paused = true;
    _cancelPendingWork();
  }

  void stop() {
    _stopped = true;
    _paused = false;
    _disconnectedSince = null;
    _reconnectAttempts = 0;
    _cancelPendingWork();
  }

  void _cancelPendingWork() {
    _connectGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }
}
