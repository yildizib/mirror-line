import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:logger/logger.dart';

import '../security/crypto_manager.dart';
import 'message_protocol.dart';

class SocketManager {
  static const Duration _heartbeatInterval = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 45);

  final Logger _logger = Logger();
  final void Function(MirrorMessage) onMessage;
  final void Function()? onConnected;
  final void Function()? onDisconnected;

  ServerSocket? _server;
  Socket? _client;
  SecretKey? _key;
  bool _isConnected = false;
  bool _disposed = false;
  final List<int> _buffer = [];
  Timer? _heartbeatTimer;
  DateTime _lastDataAt = DateTime.now();

  SocketManager({
    required this.onMessage,
    this.onConnected,
    this.onDisconnected,
  });

  bool get isConnected => _isConnected;

  Future<void> startServer(int port, SecretKey key) async {
    _key = key;
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _logger.i('Socket server listening on port $port');

      _server!.listen((socket) {
        if (_client != null) {
          _logger.w('A client is already connected. Rejecting new connection.');
          socket.close();
          return;
        }
        _accept(socket);
      });
    } catch (e) {
      _logger.e('Failed to start server on port $port: $e');
      rethrow;
    }
  }

  Future<bool> connect(String ip, int port, SecretKey key) async {
    if (_isConnected) return true;
    if (ip.isEmpty || ip == 'unknown') return false;
    _key = key;
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _accept(socket);
      _logger.i('Connected to peer $ip:$port');
      return true;
    } catch (e) {
      _logger.w('Failed to connect to peer $ip:$port: $e');
      return false;
    }
  }

  void _accept(Socket socket) {
    _client = socket;
    _isConnected = true;
    _disposed = false;
    _buffer.clear();
    _lastDataAt = DateTime.now();
    socket.setOption(SocketOption.tcpNoDelay, true);
    onConnected?.call();
    _listen(socket);
    _startHeartbeat();
  }

  void _listen(Socket socket) {
    socket.listen(
      (data) {
        _lastDataAt = DateTime.now();
        _buffer.addAll(data);
        _processBuffer();
      },
      onDone: () {
        _logger.i('Socket connection closed by peer.');
        _handleClosed();
      },
      onError: (error) {
        _logger.e('Socket error: $error');
        _handleClosed();
      },
      cancelOnError: true,
    );
  }

  void _handleClosed() {
    if (!_isConnected && _client == null) return;
    _isConnected = false;
    _stopHeartbeat();
    _client?.destroy();
    _client = null;
    _buffer.clear();
    if (!_disposed) onDisconnected?.call();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (!_isConnected) return;
      if (DateTime.now().difference(_lastDataAt) > _receiveTimeout) {
        _logger.w('Peer unresponsive (no data for ${_receiveTimeout.inSeconds}s). Closing.');
        _handleClosed();
        return;
      }
      await sendMessage(MessageTypes.ping, {});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _processBuffer() {
    while (_buffer.isNotEmpty) {
      final newlineIndex = _buffer.indexOf(10); // \n
      if (newlineIndex == -1) break;

      final rawMessage = _buffer.sublist(0, newlineIndex);
      _buffer.removeRange(0, newlineIndex + 1);
      if (rawMessage.isEmpty) continue;

      try {
        final raw = utf8.decode(rawMessage);
        final message = MirrorMessage.decode(raw);

        if (message.type == MessageTypes.ping) {
          sendMessage(MessageTypes.pong, {});
          continue;
        }
        if (message.type == MessageTypes.pong) {
          continue;
        }

        _logger.i('Received: ${message.type}');
        onMessage(message);
      } catch (e) {
        _logger.e('Invalid message received: $e');
      }
    }
  }

  /// Encrypts and sends a message. Returns true if the message was written.
  Future<bool> sendMessage(String type, Map<String, dynamic> payload) async {
    final client = _client;
    final key = _key;
    if (client == null || key == null || !_isConnected) {
      return false;
    }

    try {
      final encrypted = await CryptoManager.encrypt(key, jsonEncode(payload));
      final message = MirrorMessage(
        type: type,
        id: '${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: encrypted,
      );
      client.write('${message.encode()}\n');
      await client.flush();
      if (type != MessageTypes.ping && type != MessageTypes.pong) {
        _logger.i('Sent: $type');
      }
      return true;
    } catch (e) {
      _logger.e('Failed to send $type: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    _stopHeartbeat();
    try {
      _client?.destroy();
    } catch (_) {}
    try {
      await _server?.close();
    } catch (_) {}
    _client = null;
    _server = null;
    _isConnected = false;
    _buffer.clear();
  }

  /// Closes only the active client connection; keeps the server listening.
  Future<void> disconnectClient() async {
    _stopHeartbeat();
    try {
      _client?.destroy();
    } catch (_) {}
    _client = null;
    _isConnected = false;
    _buffer.clear();
  }
}
