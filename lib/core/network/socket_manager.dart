import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:uuid/uuid.dart';

class SocketManager {
  final Logger _logger = Logger();
  final void Function(MirrorMessage) onMessage;
  final void Function()? onConnected;
  final void Function()? onDisconnected;

  /// When this device is the *server*, this callback is invoked with the
  /// incoming socket's remote address so the caller can decide whether to
  /// accept the connection.  Return false to reject.
  final Future<bool> Function(String remoteAddress)? onAcceptConnection;

  /// Public key (base64) of the paired peer — used for challenge-response
  /// authentication after the TCP connection is established.
  String? _peerPublicKeyBase64;
  String? _localDeviceId;
  String? _peerDeviceId;
  String? _localPublicKeyBase64;
  String? _clientAuthTranscript;
  String? _sessionId;
  int _nextSequence = 0;
  int _lastReceivedSequence = 0;
  final List<String> _acceptedMessageIds = [];

  /// This device's Ed25519 keypair, used to sign challenges when acting as
  /// the *client*.  Set via [setAuthIdentity].
  SimpleKeyPair? _localKeyPair;

  /// Whether this socket is acting as server (accepts incoming) or client
  /// (initiates connection).
  bool _isServer = false;
  bool _identityRequired = false;

  /// Completer for the client-side auth challenge.
  Completer<void>? _authCompleter;

  /// Server-side watchdog: closes the connection if the client never
  /// completes authentication (e.g. it connected but went silent).
  Timer? _serverAuthTimer;

  ServerSocket? _server;
  Socket? _client;
  SecretKey? _key;
  bool _isConnected = false;
  bool _authed = false;
  bool _disposed = false;
  final List<int> _buffer = [];
  Timer? _heartbeatTimer;
  DateTime _lastDataAt = DateTime.now();
  // Bumped on every connect()/disconnect()/disconnectClient() call so a
  // superseded connect() attempt (e.g. abandoned by a forced reconnect) can
  // tell it's stale when its TCP handshake finally resolves, instead of
  // reviving a connection nothing is expecting anymore.
  int _connectGeneration = 0;

  SocketManager({
    required this.onMessage,
    this.onConnected,
    this.onDisconnected,
    this.onAcceptConnection,
  });

  bool get isConnected => _isConnected;
  bool get isAuthed => _authed;

  /// Extends the heartbeat cadence when the app goes to the background
  /// (screen off) and restores it on resume. A slower ping while the
  /// screen is off is friendlier to the Wi-Fi radio's power-save state
  /// (the high-perf wifi lock keeps it alive, but less frequent wake-ups
  /// still save battery) while the 90s receive-timeout is generous enough
  /// to tolerate the longer gap.
  void setBackgroundMode(bool background) {
    _backgroundMode = background;
    if (_authed) _startHeartbeat();
  }

  bool _backgroundMode = false;

  /// The connected peer's real IP address (from the live TCP socket),
  /// or null if no client is connected. More trustworthy than anything the
  /// peer claims about itself in application-level messages.
  String? get remoteAddress => _client?.remoteAddress.address;

  /// Configure the authentication identity for this socket.
  /// [peerPublicKeyBase64] is the other device's public key (for verifying
  /// their signatures when we are the server).
  /// [localKeyPair] is our Ed25519 keypair (for signing challenges when we
  /// are the client).
  void setAuthIdentity({
    required String peerPublicKeyBase64,
    required SimpleKeyPair localKeyPair,
    String? localDeviceId,
    String? peerDeviceId,
  }) {
    _peerPublicKeyBase64 = peerPublicKeyBase64;
    _localKeyPair = localKeyPair;
    _localDeviceId = localDeviceId;
    _peerDeviceId = peerDeviceId;
  }

  void requireAuthIdentity() => _identityRequired = true;

  Future<void> startServer(int port, SecretKey key) async {
    _key = key;
    _isServer = true;
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _logger.i('Socket server listening on port $port');

      _server!.listen((socket) {
        if (_client != null) {
          // A previous connection is still registered. It may be a genuine
          // second peer, but in this app's 1:1 pairing model it is far more
          // likely a stale/zombie socket (e.g. the other side's process died
          // without a clean TCP close). Drop it and accept the new one —
          // otherwise a single silent disconnect would permanently block all
          // future reconnect attempts until this device's app is restarted.
          _logger.w(
            'Replacing previous connection with new incoming connection.',
          );
          _handleClosed();
        }
        _accept(socket);
      });
    } catch (e) {
      _logger.e('Failed to start server on port $port: $e');
      rethrow;
    }
  }

  Future<bool> connect(
    String ip,
    int port,
    SecretKey key, {
    Duration? connectTimeout,
  }) async {
    if (_isConnected) return true;
    if (ip.isEmpty || ip == 'unknown') return false;
    // Don't let an outward connect() call clobber a running server. This
    // was a root-cause of Source's server dying after an onDisconnected
    // callback: the reconnect path -> _connectTo -> connect() flipped
    // _isServer = false, silently destroying the server's accept loop.
    // The caller (ConnectionFacade) now guards with isSource, but this
    // is a defensive backstop so a misconfigured caller can't break the
    // server again.
    if (_isServer && _server != null) {
      _logger.w(
        'connect() called on a server-mode socket manager; refusing to '
        'clobber the server. Caller should use a separate socket manager.',
      );
      return false;
    }
    _key = key;
    _isServer = false;
    final generation = ++_connectGeneration;
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: connectTimeout ?? const Duration(seconds: 5),
      );
      if (generation != _connectGeneration) {
        // A newer connect()/disconnect() call superseded this one while the
        // TCP handshake was in flight (e.g. a forced reconnect) -- discard
        // this socket instead of reviving a connection nothing is expecting
        // anymore, which would otherwise clobber the newer attempt's _client.
        socket.destroy();
        return false;
      }
      _accept(socket);
      _logger.i('Connected to peer $ip:$port, awaiting auth...');

      // Wait for auth to complete (or fail/timeout).
      try {
        await _authCompleter?.future.timeout(
          SecurityConstants.authenticationTimeout,
        );
        return true;
      } catch (e) {
        _logger.w('Auth failed during connect: $e');
        _handleClosed();
        return false;
      }
    } catch (e) {
      _logger.w('Failed to connect to peer $ip:$port: $e');
      return false;
    }
  }

  void _accept(Socket socket) {
    _client = socket;
    _isConnected = true;
    _authed = false;
    _disposed = false;
    _buffer.clear();
    _sessionId = null;
    _nextSequence = 0;
    _lastReceivedSequence = 0;
    _acceptedMessageIds.clear();
    _lastDataAt = DateTime.now();
    socket.setOption(SocketOption.tcpNoDelay, true);
    _listen(socket);

    // Start challenge-response authentication before announcing connection.
    // Skip auth if no peer public key is configured (pairing mode).
    if (_isServer) {
      if (_peerPublicKeyBase64 != null && _peerPublicKeyBase64!.isNotEmpty) {
        unawaited(_startServerAuth(socket));
      } else {
        if (_identityRequired) {
          _logger.e('Paired connection is missing authentication identity.');
          _handleClosed();
          return;
        }
        _logger.i(
          'Server: no peer public key set — pairing mode, skipping auth.',
        );
        _onAuthSuccess();
      }
    } else {
      if (_localKeyPair != null) {
        _startClientAuth();
      } else {
        if (_identityRequired) {
          _logger.e('Paired connection is missing authentication identity.');
          _handleClosed();
          return;
        }
        _logger.i(
          'Client: no local key pair set — pairing mode, skipping auth.',
        );
        _onAuthSuccess();
      }
    }
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
    _authed = false;
    _stopHeartbeat();
    _stopServerAuthTimer();
    _client?.destroy();
    _client = null;
    _buffer.clear();
    if (!_disposed) onDisconnected?.call();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    final interval = _backgroundMode
        ? SecurityConstants.backgroundHeartbeatInterval
        : SecurityConstants.heartbeatInterval;
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      if (!_isConnected) return;
      if (DateTime.now().difference(_lastDataAt) >
          SecurityConstants.receiveTimeout) {
        _logger.w(
          'Peer unresponsive (no data for '
          '${SecurityConstants.receiveTimeout.inSeconds}s). Closing.',
        );
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
        if (message.sessionId != null) {
          _sessionId ??= message.sessionId;
        }

        if (message.protocolVersion != SecurityConstants.protocolVersion) {
          _logger.w('Rejected message with unknown protocol version.');
          continue;
        }

        // ---- Intercept auth messages before heartbeat / onMessage ----
        if (message.type == MessageTypes.ping) {
          sendMessage(MessageTypes.pong, {});
          continue;
        }
        if (message.type == MessageTypes.pong) {
          continue;
        }

        if (message.type == MessageTypes.authChallenge) {
          _handleAuthChallenge(message);
          continue;
        }
        if (message.type == MessageTypes.authResponse) {
          _handleAuthResponse(message);
          continue;
        }
        if (message.type == MessageTypes.authOk) {
          _onClientAuthOk(message);
          continue;
        }
        if (message.type == MessageTypes.authAck) {
          _onAuthSuccess();
          continue;
        }
        if (message.type == MessageTypes.authFail) {
          _onAuthFail();
          continue;
        }

        // ---- Past auth: normal messages ----
        if (!_authed) {
          _logger.w(
            'Received non-auth message before auth completed: ${message.type}',
          );
          continue;
        }

        if (!_acceptNormalMessage(message)) {
          continue;
        }

        _logger.i('Received: ${message.type}');
        onMessage(message);
      } catch (e) {
        _logger.e('Invalid message received: $e');
      }
    }
  }

  bool _acceptNormalMessage(MirrorMessage message) {
    final sessionId = _sessionId;
    if (sessionId != null) {
      if (message.sessionId != sessionId || message.sequence == null) {
        _logger.w('Rejected message from another session or without sequence.');
        return false;
      }
      if (message.sequence! <= _lastReceivedSequence) {
        _logger.w('Rejected duplicate or reordered message sequence.');
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((now - message.timestamp).abs() >
          SecurityConstants.messageFreshnessWindow.inMilliseconds) {
        _logger.w('Rejected message outside freshness window.');
        return false;
      }
      _lastReceivedSequence = message.sequence!;
    }

    if (_acceptedMessageIds.contains(message.id)) {
      _logger.w('Rejected duplicate message ID.');
      return false;
    }
    _acceptedMessageIds.add(message.id);
    if (_acceptedMessageIds.length > SecurityConstants.maxAcceptedMessageIds) {
      _acceptedMessageIds.removeAt(0);
    }
    return true;
  }

  /// Encrypts and sends a message. Returns true if the message was written.
  Future<bool> sendMessage(String type, Map<String, dynamic> payload) async {
    final client = _client;
    final key = _key;
    if (client == null || key == null || !_isConnected) {
      return false;
    }

    try {
      final id = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sequence = _isControlMessage(type) ? null : ++_nextSequence;
      final metadata = CryptoManager.canonicalMessageMetadata(
        version: SecurityConstants.protocolVersion,
        type: type,
        id: id,
        timestamp: timestamp,
      );
      final encrypted = _isControlMessage(type)
          ? await CryptoManager.encrypt(key, jsonEncode(payload))
          : await CryptoManager.encryptWithAad(
              key,
              jsonEncode(payload),
              aad: utf8.encode(metadata),
            );
      final message = MirrorMessage(
        type: type,
        id: id,
        timestamp: timestamp,
        payload: encrypted,
        sessionId: _sessionId,
        sequence: sequence,
      );
      client.write('${message.encode()}\n');
      await client.flush();
      if (type != MessageTypes.ping && type != MessageTypes.pong) {
        _logger.i('Sent: $type');
      }
      return true;
    } catch (e) {
      _logger.e('Failed to send $type: $e');
      // A write failure means the socket is dead -- don't wait for the
      // 45s receive-timeout watchdog to notice. Without this, a heartbeat
      // ping that fails to send (broken pipe, silently dropped Wi-Fi
      // connection) was logged and ignored, leaving `state` stuck at
      // "connected" and reconnection never triggered until the app was
      // killed and restarted.
      _handleClosed();
      return false;
    }
  }

  bool _isControlMessage(String type) =>
      type == MessageTypes.authChallenge ||
      type == MessageTypes.authResponse ||
      type == MessageTypes.authOk ||
      type == MessageTypes.authAck ||
      type == MessageTypes.authFail ||
      type == MessageTypes.ping ||
      type == MessageTypes.pong;

  // --------------------------------------------------------------------
  // Challenge-response authentication
  // --------------------------------------------------------------------

  /// Server side: send a random nonce to the client.
  Future<void> _startServerAuth(Socket socket) async {
    final nonce = CryptoManager.generateNonce();
    _sessionId = const Uuid().v4();
    final localKey = _localKeyPair;
    final localPublicKey = localKey == null
        ? ''
        : base64Encode((await localKey.extractPublicKey()).bytes);
    _localPublicKeyBase64 = localPublicKey;
    _logger.i('Server sending auth challenge.');
    sendMessage(MessageTypes.authChallenge, {
      'nonce': nonce,
      'session_id': _sessionId,
      'protocol_version': SecurityConstants.protocolVersion,
      'server_device_id': _localDeviceId,
      'client_device_id': _peerDeviceId,
      'server_public_key': localPublicKey,
      'client_public_key': _peerPublicKeyBase64,
    });

    // If the client never responds (e.g. it silently died), don't hold this
    // connection slot forever — close it so a real reconnect can get through.
    _stopServerAuthTimer();
    _serverAuthTimer = Timer(SecurityConstants.authenticationTimeout, () {
      if (!_authed) {
        _logger.w(
          'Server auth timeout: client never completed authentication.',
        );
        _handleClosed();
      }
    });
  }

  void _stopServerAuthTimer() {
    _serverAuthTimer?.cancel();
    _serverAuthTimer = null;
  }

  /// Client side: wait for the server's challenge, sign it, and respond.
  void _startClientAuth() {
    _authCompleter = Completer<void>();
    // Start heartbeat only after auth completes (in _onAuthSuccess).
    // Timeout: if server never challenges us, drop the connection.
    Future.delayed(SecurityConstants.authenticationTimeout, () {
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _logger.w('Auth timeout (no challenge from server).');
        _authCompleter!.completeError('timeout');
        _handleClosed();
      }
    });
  }

  /// Client side: received a challenge from the server, sign it.
  void _handleAuthChallenge(MirrorMessage message) async {
    final key = _key;
    final localKeyPair = _localKeyPair;
    if (key == null || localKeyPair == null) {
      _logger.e('Auth challenge received but no local key pair set.');
      _handleClosed();
      return;
    }

    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) {
      _logger.e('Could not decrypt auth challenge.');
      _handleClosed();
      return;
    }
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final nonce = payload['nonce'] as String? ?? '';
    final sessionId = payload['session_id'] as String? ?? '';
    if (nonce.isEmpty || sessionId.isEmpty || message.sessionId != sessionId) {
      _logger.e('Empty nonce in auth challenge.');
      _handleClosed();
      return;
    }

    if (payload['protocol_version'] != SecurityConstants.protocolVersion ||
        payload['server_device_id'] != _peerDeviceId ||
        payload['client_device_id'] != _localDeviceId ||
        payload['server_public_key'] != _peerPublicKeyBase64) {
      _handleClosed();
      return;
    }
    final transcript = _authTranscript(payload);
    _clientAuthTranscript = transcript;
    final signature = await CryptoManager.sign(localKeyPair, transcript);
    _logger.i('Client sending auth response (signed nonce).');
    await sendMessage(MessageTypes.authResponse, {
      'nonce': nonce,
      'session_id': sessionId,
      'signature': signature,
      'transcript': transcript,
    });
  }

  /// Server side: received the client's signed nonce, verify it.
  void _handleAuthResponse(MirrorMessage message) async {
    final key = _key;
    final peerPubKey = _peerPublicKeyBase64;
    if (key == null || peerPubKey == null) {
      _logger.e('Auth response received but no peer public key set.');
      _onAuthFail();
      return;
    }

    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) {
      _logger.e('Could not decrypt auth response.');
      _onAuthFail();
      return;
    }
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final nonce = payload['nonce'] as String? ?? '';
    final sessionId = payload['session_id'] as String? ?? '';
    final signature = payload['signature'] as String? ?? '';
    final transcript = payload['transcript'] as String? ?? '';

    // Verify the signature against the nonce using the peer's public key.
    final expectedTranscript = _authTranscript({
      'nonce': nonce,
      'session_id': sessionId,
      'protocol_version': SecurityConstants.protocolVersion,
      'server_device_id': _localDeviceId,
      'client_device_id': _peerDeviceId,
      'server_public_key': _localPublicKeyBase64,
      'client_public_key': peerPubKey,
    });
    final ok =
        sessionId.isNotEmpty &&
        message.sessionId == sessionId &&
        sessionId == _sessionId &&
        transcript == expectedTranscript &&
        await CryptoManager.verifySignature(
          signatureBase64: signature,
          message: transcript,
          publicKeyBase64: peerPubKey,
        );

    if (ok) {
      _logger.i(
        'Client authenticated successfully. Sent authOk, awaiting ack.',
      );
      final localKey = _localKeyPair;
      if (localKey == null) {
        _onAuthFail();
        return;
      }
      final serverSignature = await CryptoManager.sign(localKey, transcript);
      await sendMessage(MessageTypes.authOk, {
        'transcript': transcript,
        'signature': serverSignature,
      });
      // Don't call _onAuthSuccess() yet: if this authOk never reaches the
      // client (dropped packet, client already gave up), we'd otherwise
      // believe the connection is live -- start heartbeating, report
      // "connected" -- while the client has already closed its side. Only
      // commit to "connected" once the client acks (see authAck above).
      // _serverAuthTimer (already running) closes the connection if no ack
      // arrives in time.
    } else {
      _logger.w('Client authentication failed (invalid signature).');
      await sendMessage(MessageTypes.authFail, {});
      _onAuthFail();
    }
  }

  String _authTranscript(Map<String, dynamic> payload) => jsonEncode({
    'protocol_version': payload['protocol_version'],
    'nonce': payload['nonce'],
    'session_id': payload['session_id'],
    'server_device_id': payload['server_device_id'],
    'client_device_id': payload['client_device_id'],
    'server_public_key': payload['server_public_key'],
    'client_public_key': payload['client_public_key'],
  });

  /// Client side: server accepted our signed challenge. Ack it so the
  /// server knows we actually received this before either side considers
  /// the connection established (see _handleAuthResponse above).
  void _onClientAuthOk(MirrorMessage message) async {
    final key = _key;
    final peerKey = _peerPublicKeyBase64;
    if (key == null || peerKey == null || _clientAuthTranscript == null) {
      _onAuthFail();
      return;
    }
    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) {
      _onAuthFail();
      return;
    }
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final valid =
        payload['transcript'] == _clientAuthTranscript &&
        await CryptoManager.verifySignature(
          signatureBase64: payload['signature'] as String? ?? '',
          message: _clientAuthTranscript!,
          publicKeyBase64: peerKey,
        );
    if (!valid) {
      _onAuthFail();
      return;
    }
    await sendMessage(MessageTypes.authAck, {});
    _onAuthSuccess();
  }

  void _onAuthSuccess() {
    if (_authed) return;
    _authed = true;
    _stopServerAuthTimer();
    _logger.i('Auth complete. Connection fully established.');
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete();
    }
    onConnected?.call();
    _startHeartbeat();
  }

  void _onAuthFail() {
    _logger.w('Authentication failed. Closing connection.');
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.completeError('auth failed');
    }
    _handleClosed();
  }

  Future<void> disconnect() async {
    _connectGeneration++;
    _disposed = true;
    _authed = false;
    _stopHeartbeat();
    _stopServerAuthTimer();
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

  /// Closes only the listening server socket; leaves an active client
  /// connection (if any) untouched. Used to tear down a temporary
  /// pairing-time server once a device that isn't permanently a server
  /// (i.e. not 'source') finishes pairing.
  Future<void> stopServer() async {
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }

  /// Closes only the active client connection; keeps the server listening.
  Future<void> disconnectClient() async {
    _connectGeneration++;
    _authed = false;
    _stopHeartbeat();
    _stopServerAuthTimer();
    try {
      _client?.destroy();
    } catch (_) {}
    _client = null;
    _isConnected = false;
    _buffer.clear();
  }
}
