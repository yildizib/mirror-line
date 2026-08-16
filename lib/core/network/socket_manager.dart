import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:uuid/uuid.dart';

enum _AuthPhase { none, awaitChallenge, awaitResponse, awaitOk, awaitAck }

class _SocketSession {
  _SocketSession({required this.socket, required this.generation})
    : sessionId = const Uuid().v4();

  final Socket socket;
  final int generation;
  String sessionId;
  final List<int> buffer = [];
  StreamSubscription<List<int>>? subscription;
  Completer<void>? authCompleter;
  Timer? authTimer;
  _AuthPhase authPhase = _AuthPhase.none;
  String? challengeNonce;
  int nextSequence = 0;
  int lastReceivedSequence = -1;
  Future<void> messagePipeline = Future<void>.value();
}

class SocketManager {
  static const int _maxFrameBytes = 256 * 1024;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _heartbeatIntervalBackground = Duration(seconds: 60);
  static const Duration _receiveTimeout = Duration(seconds: 90);
  static const Duration _defaultAuthTimeout = Duration(seconds: 10);

  final Logger _logger = Logger();
  final FutureOr<void> Function(MirrorMessage) onMessage;
  final void Function()? onConnected;
  final void Function()? onDisconnected;
  final Duration authTimeout;

  /// When this device is the *server*, this callback is invoked with the
  /// incoming socket's remote address so the caller can decide whether to
  /// accept the connection.  Return false to reject.
  final Future<bool> Function(String remoteAddress)? onAcceptConnection;

  /// Public key (base64) of the paired peer — used for challenge-response
  /// authentication after the TCP connection is established.
  String? _peerPublicKeyBase64;
  String? _localPeerId;
  Future<void>? _localPeerIdReady;

  /// This device's Ed25519 keypair, used to sign challenges when acting as
  /// the *client*.  Set via [setAuthIdentity].
  SimpleKeyPair? _localKeyPair;

  /// Whether this socket is acting as server (accepts incoming) or client
  /// (initiates connection).
  bool _isServer = false;

  ServerSocket? _server;
  _SocketSession? _session;
  SecretKey? _key;
  bool _isConnected = false;
  bool _authed = false;
  bool _disposed = false;
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
    this.authTimeout = _defaultAuthTimeout,
  });

  bool get isConnected => _isConnected;
  bool get isAuthed => _authed;
  int? get sessionGeneration => _session?.generation;
  String? get sessionId => _session?.sessionId;

  bool isSessionCurrent(int generation) {
    final session = _session;
    return session != null &&
        session.generation == generation &&
        _isCurrent(session);
  }

  /// Extends the heartbeat cadence when the app goes to the background
  /// (screen off) and restores it on resume. A slower ping while the
  /// screen is off is friendlier to the Wi-Fi radio's power-save state
  /// (the high-perf wifi lock keeps it alive, but less frequent wake-ups
  /// still save battery) while the 90s receive-timeout is generous enough
  /// to tolerate the longer gap.
  void setBackgroundMode(bool background) {
    _backgroundMode = background;
    final session = _session;
    if (_authed && session != null) _startHeartbeat(session);
  }

  bool _backgroundMode = false;

  /// The connected peer's real IP address (from the live TCP socket),
  /// or null if no client is connected. More trustworthy than anything the
  /// peer claims about itself in application-level messages.
  String? get remoteAddress => _session?.socket.remoteAddress.address;

  /// Configure the authentication identity for this socket.
  /// [peerPublicKeyBase64] is the other device's public key (for verifying
  /// their signatures when we are the server).
  /// [localKeyPair] is our Ed25519 keypair (for signing challenges when we
  /// are the client).
  void setAuthIdentity({
    required String peerPublicKeyBase64,
    required SimpleKeyPair localKeyPair,
  }) {
    _peerPublicKeyBase64 = peerPublicKeyBase64;
    _localKeyPair = localKeyPair;
    _localPeerIdReady = _loadLocalPeerId(localKeyPair);
  }

  Future<void> _loadLocalPeerId(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    _localPeerId = base64Encode(publicKey.bytes);
  }

  Future<void> startServer(int port, SecretKey key) async {
    _key = key;
    _isServer = true;
    _disposed = false;
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _logger.i('Socket server listening on port $port');

      _server!.listen((socket) {
        final generation = ++_connectGeneration;
        final previous = _session;
        if (previous != null) {
          // A previous connection is still registered. It may be a genuine
          // second peer, but in this app's 1:1 pairing model it is far more
          // likely a stale/zombie socket (e.g. the other side's process died
          // without a clean TCP close). Drop it and accept the new one —
          // otherwise a single silent disconnect would permanently block all
          // future reconnect attempts until this device's app is restarted.
          _logger.w(
            'Replacing previous connection with new incoming connection.',
          );
          _closeSession(previous);
        }
        _accept(socket, generation);
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
    _disposed = false;
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
      _accept(socket, generation);
      final session = _session;
      if (session == null || session.generation != generation) {
        socket.destroy();
        return false;
      }
      _logger.i('Connected to peer $ip:$port, awaiting auth...');

      // Wait for auth to complete (or fail/timeout).
      try {
        final authCompleter = session.authCompleter;
        if (authCompleter != null) await authCompleter.future;
        return _isCurrent(session) && _authed;
      } catch (e) {
        _logger.w('Auth failed during connect: $e');
        _closeSession(session);
        return false;
      }
    } catch (e) {
      _logger.w('Failed to connect to peer $ip:$port: $e');
      return false;
    }
  }

  void _accept(Socket socket, int generation) {
    final session = _SocketSession(socket: socket, generation: generation);
    _session = session;
    _isConnected = true;
    _authed = false;
    _disposed = false;
    _lastDataAt = DateTime.now();
    socket.setOption(SocketOption.tcpNoDelay, true);
    _listen(session);

    // Start challenge-response authentication before announcing connection.
    // Skip auth only when neither side has paired identity material.
    if (_isServer) {
      final hasPeerIdentity =
          _peerPublicKeyBase64 != null && _peerPublicKeyBase64!.isNotEmpty;
      if (hasPeerIdentity && _localKeyPair != null) {
        _startServerAuth(session);
      } else if (hasPeerIdentity || _localKeyPair != null) {
        _logger.e('Incomplete server auth identity. Closing connection.');
        _closeSession(session);
      } else {
        _logger.i(
          'Server: no peer public key set — pairing mode, skipping auth.',
        );
        _onAuthSuccess(session);
      }
    } else {
      final hasPeerIdentity =
          _peerPublicKeyBase64 != null && _peerPublicKeyBase64!.isNotEmpty;
      if (_localKeyPair != null && hasPeerIdentity) {
        _startClientAuth(session);
      } else if (_localKeyPair != null || hasPeerIdentity) {
        _logger.e('Incomplete client auth identity. Closing connection.');
        _closeSession(session);
      } else {
        _logger.i(
          'Client: no local key pair set — pairing mode, skipping auth.',
        );
        _onAuthSuccess(session);
      }
    }
  }

  void _listen(_SocketSession session) {
    session.subscription = session.socket.listen(
      (data) {
        if (!_isCurrent(session)) return;
        _lastDataAt = DateTime.now();
        session.buffer.addAll(data);
        if (session.buffer.length > _maxFrameBytes) {
          _logger.w('Receive buffer exceeded the maximum frame size.');
          _closeSession(session);
          return;
        }
        _processBuffer(session);
      },
      onDone: () {
        _logger.i('Socket connection closed by peer.');
        _closeSession(session);
      },
      onError: (error) {
        _logger.e('Socket error: $error');
        _closeSession(session);
      },
      cancelOnError: true,
    );
  }

  bool _isCurrent(_SocketSession session) =>
      identical(_session, session) && session.generation == _connectGeneration;

  void _closeSession(_SocketSession session, {bool notify = true}) {
    session.authTimer?.cancel();
    session.authTimer = null;
    unawaited(session.subscription?.cancel());
    session.subscription = null;
    session.buffer.clear();
    try {
      session.socket.destroy();
    } catch (_) {}

    if (!identical(_session, session)) return;
    _session = null;
    _isConnected = false;
    _authed = false;
    _stopHeartbeat();
    final authCompleter = session.authCompleter;
    if (authCompleter != null && !authCompleter.isCompleted) {
      authCompleter.completeError('connection closed');
    }
    if (notify && !_disposed) onDisconnected?.call();
  }

  void _startHeartbeat(_SocketSession session) {
    _stopHeartbeat();
    final interval = _backgroundMode
        ? _heartbeatIntervalBackground
        : _heartbeatInterval;
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      if (!_isCurrent(session) || !_isConnected) return;
      if (DateTime.now().difference(_lastDataAt) > _receiveTimeout) {
        _logger.w(
          'Peer unresponsive (no data for ${_receiveTimeout.inSeconds}s). Closing.',
        );
        _closeSession(session);
        return;
      }
      await sendMessage(MessageTypes.ping, {});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _processBuffer(_SocketSession session) {
    while (_isCurrent(session) && session.buffer.isNotEmpty) {
      final newlineIndex = session.buffer.indexOf(10); // \n
      if (newlineIndex == -1) break;

      final rawMessage = session.buffer.sublist(0, newlineIndex);
      session.buffer.removeRange(0, newlineIndex + 1);
      if (rawMessage.isEmpty) continue;

      try {
        final raw = utf8.decode(rawMessage);
        final message = MirrorMessage.decode(raw);

        // The server chooses the session identifier and the client adopts it
        // from the first authenticated envelope it receives.
        if (!_isServer &&
            message.type == MessageTypes.authChallenge &&
            session.authPhase == _AuthPhase.awaitChallenge &&
            message.sessionId != null) {
          session.sessionId = message.sessionId!;
        }
        if (message.hasAuthenticatedEnvelope &&
            !_acceptEnvelope(session, message)) {
          _logger.w('Rejected invalid or replayed message envelope.');
          _closeSession(session);
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
          _handleAuthChallenge(session, message);
          continue;
        }
        if (message.type == MessageTypes.authResponse) {
          _handleAuthResponse(session, message);
          continue;
        }
        if (message.type == MessageTypes.authOk) {
          _onClientAuthOk(session);
          continue;
        }
        if (message.type == MessageTypes.authAck) {
          if (session.authPhase != _AuthPhase.awaitAck) {
            _logger.w('Unexpected auth ACK received. Closing connection.');
            _closeSession(session);
            continue;
          }
          _onAuthSuccess(session);
          continue;
        }
        if (message.type == MessageTypes.authFail) {
          _onAuthFail(session);
          continue;
        }

        // ---- Past auth: normal messages ----
        if (!_authed) {
          _logger.w(
            'Received non-auth message before auth completed: ${message.type}',
          );
          continue;
        }

        _logger.i('Received: ${message.type}');
        _enqueueMessage(session, message);
      } catch (e) {
        _logger.e('Invalid message received: $e');
      }
    }
  }

  void _enqueueMessage(_SocketSession session, MirrorMessage message) {
    session.messagePipeline = session.messagePipeline.then((_) async {
      if (!_isCurrent(session)) return;
      try {
        await onMessage(message);
      } catch (e, stackTrace) {
        _logger.e(
          'Message handler failed for ${message.type}: $e',
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Encrypts and sends a message. Returns true if the message was written.
  Future<bool> sendMessage(String type, Map<String, dynamic> payload) async {
    final session = _session;
    final key = _key;
    if (session == null || key == null || !_isConnected) {
      return false;
    }

    try {
      await _localPeerIdReady;
      final id = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sequence = session.nextSequence++;
      final envelope = MirrorMessage(
        type: type,
        id: id,
        timestamp: timestamp,
        payload: '',
        sourcePeerId: _localPeerId,
        destinationPeerId: _peerPublicKeyBase64 ?? '',
        sessionId: session.sessionId,
        sequence: sequence,
      );
      final encrypted = await CryptoManager.encrypt(
        key,
        jsonEncode(payload),
        aad: envelope.hasAuthenticatedEnvelope
            ? utf8.encode(envelope.authenticatedData())
            : const [],
      );
      if (!_isCurrent(session)) return false;
      final message = MirrorMessage(
        type: envelope.type,
        id: envelope.id,
        timestamp: envelope.timestamp,
        payload: encrypted,
        sourcePeerId: envelope.sourcePeerId,
        destinationPeerId: envelope.destinationPeerId,
        sessionId: envelope.sessionId,
        sequence: envelope.sequence,
      );
      session.socket.write('${message.encode()}\n');
      await session.socket.flush();
      if (!_isCurrent(session)) return false;
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
      _closeSession(session);
      return false;
    }
  }

  bool _acceptEnvelope(_SocketSession session, MirrorMessage message) {
    if (message.protocolVersion != MirrorMessage.currentProtocolVersion ||
        message.sessionId != session.sessionId ||
        message.sequence == null ||
        message.sequence! <= session.lastReceivedSequence) {
      return false;
    }
    if (message.destinationPeerId != (_localPeerId ?? '')) return false;
    session.lastReceivedSequence = message.sequence!;
    return true;
  }

  Future<String?> _decryptMessage(SecretKey key, MirrorMessage message) =>
      CryptoManager.decrypt(
        key,
        message.payload,
        aad: message.hasAuthenticatedEnvelope
            ? utf8.encode(message.authenticatedData())
            : const [],
      );

  // --------------------------------------------------------------------
  // Challenge-response authentication
  // --------------------------------------------------------------------

  /// Server side: send a random nonce to the client.
  void _startServerAuth(_SocketSession session) async {
    final nonce = CryptoManager.generateNonce();
    final localKeyPair = _localKeyPair;
    if (localKeyPair == null) {
      _closeSession(session);
      return;
    }
    session.authPhase = _AuthPhase.awaitResponse;
    session.challengeNonce = nonce;
    final signature = await CryptoManager.sign(localKeyPair, nonce);
    if (!_isCurrent(session)) return;
    _logger.i('Server sending auth challenge.');
    await sendMessage(MessageTypes.authChallenge, {
      'nonce': nonce,
      'signature': signature,
    });

    // If the client never responds (e.g. it silently died), don't hold this
    // connection slot forever — close it so a real reconnect can get through.
    _stopAuthTimer(session);
    session.authTimer = Timer(authTimeout, () {
      if (_isCurrent(session) && !_authed) {
        _logger.w(
          'Server auth timeout: client never completed authentication.',
        );
        _closeSession(session);
      }
    });
  }

  void _stopAuthTimer(_SocketSession session) {
    session.authTimer?.cancel();
    session.authTimer = null;
  }

  /// Client side: wait for the server's challenge, sign it, and respond.
  void _startClientAuth(_SocketSession session) {
    session.authCompleter = Completer<void>();
    session.authPhase = _AuthPhase.awaitChallenge;
    // Start heartbeat only after auth completes (in _onAuthSuccess).
    // Timeout: if server never challenges us, drop the connection.
    _stopAuthTimer(session);
    session.authTimer = Timer(authTimeout, () {
      final authCompleter = session.authCompleter;
      if (_isCurrent(session) &&
          authCompleter != null &&
          !authCompleter.isCompleted) {
        _logger.w('Auth timeout (no challenge from server).');
        authCompleter.completeError('timeout');
        _closeSession(session);
      }
    });
  }

  /// Client side: received a challenge from the server, sign it.
  void _handleAuthChallenge(
    _SocketSession session,
    MirrorMessage message,
  ) async {
    if (!_isCurrent(session) ||
        session.authPhase != _AuthPhase.awaitChallenge) {
      _logger.w('Unexpected auth challenge received. Closing connection.');
      _closeSession(session);
      return;
    }
    final key = _key;
    final localKeyPair = _localKeyPair;
    if (key == null || localKeyPair == null) {
      _logger.e('Auth challenge received but no local key pair set.');
      _closeSession(session);
      return;
    }

    final decrypted = await _decryptMessage(key, message);
    if (!_isCurrent(session)) return;
    if (decrypted == null) {
      _logger.e('Could not decrypt auth challenge.');
      _closeSession(session);
      return;
    }
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final nonce = payload['nonce'] as String? ?? '';
    final serverSignature = payload['signature'] as String? ?? '';
    if (nonce.isEmpty) {
      _logger.e('Empty nonce in auth challenge.');
      _closeSession(session);
      return;
    }

    final peerPublicKey = _peerPublicKeyBase64;
    final serverVerified =
        peerPublicKey != null &&
        await CryptoManager.verifySignature(
          signatureBase64: serverSignature,
          message: nonce,
          publicKeyBase64: peerPublicKey,
        );
    if (!_isCurrent(session)) return;
    if (!serverVerified) {
      _logger.e('Server authentication failed.');
      _closeSession(session);
      return;
    }

    final signature = await CryptoManager.sign(localKeyPair, nonce);
    if (!_isCurrent(session)) return;
    session.authPhase = _AuthPhase.awaitOk;
    _logger.i('Client sending auth response (signed nonce).');
    await sendMessage(MessageTypes.authResponse, {
      'nonce': nonce,
      'signature': signature,
    });
  }

  /// Server side: received the client's signed nonce, verify it.
  void _handleAuthResponse(
    _SocketSession session,
    MirrorMessage message,
  ) async {
    if (!_isCurrent(session) || session.authPhase != _AuthPhase.awaitResponse) {
      _logger.w('Unexpected auth response received. Closing connection.');
      _closeSession(session);
      return;
    }
    final key = _key;
    final peerPubKey = _peerPublicKeyBase64;
    if (key == null || peerPubKey == null) {
      _logger.e('Auth response received but no peer public key set.');
      _onAuthFail(session);
      return;
    }

    final decrypted = await _decryptMessage(key, message);
    if (!_isCurrent(session)) return;
    if (decrypted == null) {
      _logger.e('Could not decrypt auth response.');
      _onAuthFail(session);
      return;
    }
    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final nonce = payload['nonce'] as String? ?? '';
    final signature = payload['signature'] as String? ?? '';
    final expectedNonce = session.challengeNonce;
    // Consume the challenge before verification so a nonce cannot be reused
    // after an invalid signature or a concurrent duplicate response.
    session.challengeNonce = null;
    if (nonce.isEmpty || nonce != expectedNonce) {
      _logger.w('Client authentication failed (invalid nonce).');
      _closeSession(session);
      return;
    }

    // Verify the signature against the nonce using the peer's public key.
    final ok = await CryptoManager.verifySignature(
      signatureBase64: signature,
      message: nonce,
      publicKeyBase64: peerPubKey,
    );
    if (!_isCurrent(session)) return;

    if (ok) {
      _logger.i(
        'Client authenticated successfully. Sent authOk, awaiting ack.',
      );
      session.authPhase = _AuthPhase.awaitAck;
      await sendMessage(MessageTypes.authOk, {});
      if (!_isCurrent(session)) return;
      // Don't call _onAuthSuccess() yet: if this authOk never reaches the
      // client (dropped packet, client already gave up), we'd otherwise
      // believe the connection is live -- start heartbeating, report
      // "connected" -- while the client has already closed its side. Only
      // commit to "connected" once the client acks (see authAck above).
      // The session auth timer closes the connection if no ack
      // arrives in time.
    } else {
      _logger.w('Client authentication failed (invalid signature).');
      await sendMessage(MessageTypes.authFail, {});
      if (!_isCurrent(session)) return;
      _onAuthFail(session);
    }
  }

  /// Client side: server accepted our signed challenge. Ack it so the
  /// server knows we actually received this before either side considers
  /// the connection established (see _handleAuthResponse above).
  void _onClientAuthOk(_SocketSession session) async {
    if (!_isCurrent(session) || session.authPhase != _AuthPhase.awaitOk) {
      _logger.w('Unexpected auth OK received. Closing connection.');
      _closeSession(session);
      return;
    }
    await sendMessage(MessageTypes.authAck, {});
    if (!_isCurrent(session)) return;
    _onAuthSuccess(session);
  }

  void _onAuthSuccess(_SocketSession session) {
    if (!_isCurrent(session) || _authed) return;
    _authed = true;
    session.authPhase = _AuthPhase.none;
    _stopAuthTimer(session);
    _logger.i('Auth complete. Connection fully established.');
    final authCompleter = session.authCompleter;
    if (authCompleter != null && !authCompleter.isCompleted) {
      authCompleter.complete();
    }
    onConnected?.call();
    _startHeartbeat(session);
  }

  void _onAuthFail(_SocketSession session) {
    if (!_isCurrent(session)) return;
    _logger.w('Authentication failed. Closing connection.');
    final authCompleter = session.authCompleter;
    if (authCompleter != null && !authCompleter.isCompleted) {
      authCompleter.completeError('auth failed');
    }
    _closeSession(session);
  }

  Future<void> disconnect() async {
    _connectGeneration++;
    _disposed = true;
    final session = _session;
    if (session != null) _closeSession(session);
    _authed = false;
    _stopHeartbeat();
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _session = null;
    _isConnected = false;
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
    final session = _session;
    if (session != null) _closeSession(session, notify: false);
    _connectGeneration++;
    _authed = false;
    _stopHeartbeat();
    _session = null;
    _isConnected = false;
  }
}
