import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/pairing/pairing_transport.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

/// What went wrong during pairing, kept as a code (not a rendered string)
/// so it can be localized at the widget layer -- see [pairingErrorText].
enum PairingErrorCode {
  connectionFailed,
  rejectedOrTimedOut,
  handshakeFailed,
  rejected,
  ackTimeout,
}

/// Renders a [PairingErrorCode] into user-facing text. A standalone
/// function (not a PairingState method) since PairingState has no
/// BuildContext to resolve AppLocalizations with.
String pairingErrorText(
  AppLocalizations l,
  PairingErrorCode code,
  String? detail,
) {
  return switch (code) {
    PairingErrorCode.connectionFailed => l.pairingErrorConnectionFailed,
    PairingErrorCode.rejectedOrTimedOut => l.pairingErrorRejectedOrTimedOut,
    PairingErrorCode.handshakeFailed =>
      detail == null
          ? l.pairingErrorHandshake
          : '${l.pairingErrorHandshake}: $detail',
    PairingErrorCode.rejected => l.pairingErrorRejected,
    PairingErrorCode.ackTimeout => l.pairingErrorAckTimeout,
  };
}

/// Pairing state visible to the UI.
class PairingState {
  final bool isWaitingForAccept; // Scanner side: sent request, waiting reply
  final bool isShowingRequest; // Scanned side: incoming request, awaiting user
  final bool
  isFinalizing; // Scanned side: sent accept, waiting for scanner's ack
  final String? remoteDeviceName; // Other device's name
  final String? remotePeerId; // Other device's peer id
  final String? verificationCode; // 6-digit code shared via QR/key
  final PairingErrorCode? errorCode;
  final String?
  errorDetail; // extra context for PairingErrorCode.handshakeFailed

  const PairingState({
    this.isWaitingForAccept = false,
    this.isShowingRequest = false,
    this.isFinalizing = false,
    this.remoteDeviceName,
    this.remotePeerId,
    this.verificationCode,
    this.errorCode,
    this.errorDetail,
  });

  PairingState copyWith({
    bool? isWaitingForAccept,
    bool? isShowingRequest,
    bool? isFinalizing,
    String? remoteDeviceName,
    String? remotePeerId,
    String? verificationCode,
    PairingErrorCode? errorCode,
    String? errorDetail,
    bool clearError = false,
  }) {
    return PairingState(
      isWaitingForAccept: isWaitingForAccept ?? this.isWaitingForAccept,
      isShowingRequest: isShowingRequest ?? this.isShowingRequest,
      isFinalizing: isFinalizing ?? this.isFinalizing,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      remotePeerId: remotePeerId ?? this.remotePeerId,
      verificationCode: verificationCode ?? this.verificationCode,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      errorDetail: clearError ? null : errorDetail ?? this.errorDetail,
    );
  }
}

enum PairingSessionRole { scanner, scanned }

enum PairingSessionPhase {
  connecting,
  waitingForAccept,
  awaitingDecision,
  waitingForAck,
  waitingForCompletion,
  persisting,
  completed,
  failed,
}

class _PairingSession {
  _PairingSession({
    required this.id,
    required this.role,
    required this.phase,
    required this.transport,
    required this.peerInfo,
  });

  final String id;
  final PairingSessionRole role;
  PairingSessionPhase phase;
  final PairingTransport transport;
  Object? transportToken;
  final Map<String, dynamic> peerInfo;
  final Completer<bool> response = Completer<bool>();
  final Completer<bool> completion = Completer<bool>();
  Map<String, dynamic>? responsePayload;
  bool cleanedUp = false;
}

class _SocketPairingClientTransport implements PairingClientTransport {
  _SocketPairingClientTransport({
    required this._onMessage,
    required void Function() onDisconnected,
  }) {
    late final SocketManager socket;
    socket = SocketManager(
      onMessage: (message) async {
        final key = _key;
        final generation = socket.sessionGeneration;
        if (key == null || generation == null) return;
        final decrypted = await CryptoManager.decrypt(
          key,
          message.payload,
          aad: message.hasAuthenticatedEnvelope
              ? utf8.encode(message.authenticatedData())
              : const [],
        );
        if (!socket.isSessionCurrent(generation)) return;
        Map<String, dynamic>? payload;
        try {
          payload = jsonDecode(decrypted ?? '') as Map<String, dynamic>;
        } catch (_) {
          payload = null;
        }
        await _onMessage(message.type, payload);
      },
      onConnected: () {},
      onDisconnected: onDisconnected,
    );
    _socket = socket;
  }

  final PairingMessageHandler _onMessage;
  late final SocketManager _socket;
  SecretKey? _key;

  @override
  Object get connectionToken => (_socket, _socket.sessionGeneration);

  @override
  bool get isCurrent {
    final generation = _socket.sessionGeneration;
    return generation != null && _socket.isSessionCurrent(generation);
  }

  @override
  String? get remoteAddress => _socket.remoteAddress;

  @override
  Future<bool> connect(String ip, int port, SecretKey key) {
    _key = key;
    return _socket.connect(ip, port, key);
  }

  @override
  Future<void> disconnect() => _socket.disconnect();

  @override
  Future<bool> send(String type, Map<String, dynamic> payload) =>
      _socket.sendMessage(type, payload);
}

final pairingFacadeProvider =
    StateNotifierProvider<PairingFacade, PairingState>((ref) {
      return PairingFacade(ref);
    });

/// Coordinates the two-way QR pairing handshake.
///
/// Flow:
///   1. Scanner reads QR -> calls [sendRequest] with scanned info.
///   2. Scanner opens a temporary TCP connection to the scanned device
///      and sends `pairingRequest` with its own device name + peer id.
///   3. Scanned device receives `pairingRequest` via ConnectionFacade,
///      which calls [handleIncomingRequest] -> UI shows confirmation dialog.
///   4. User on scanned device confirms -> [acceptRequest] sends
///      `pairingAccept` back and saves the peer.
///   5. Scanner receives `pairingAccept`, saves the peer, completes.
///
/// If the scanned device rejects, [rejectRequest] sends `pairingReject`
/// and the scanner shows an error.
class PairingFacade extends StateNotifier<PairingState> {
  final Logger _logger = Logger();
  final Ref _ref;
  final PairingClientTransportFactory _clientFactory;
  final Duration _acceptTimeout;
  final Duration _ackTimeout;
  final String Function() _createSessionId;
  final Future<void> Function(Map<String, dynamic>)? _persistScannerOverride;
  final Future<void> Function(Map<String, dynamic>)? _persistScannedOverride;
  final Future<void> Function(Map<String, dynamic>)? _rollbackScannerOverride;
  final Future<void> Function(Map<String, dynamic>)? _rollbackScannedOverride;
  final Future<Map<String, dynamic>> Function()? _localIdentityOverride;
  final String Function()? _verificationCodeOverride;
  _PairingSession? _session;

  PairingFacade(
    this._ref, {
    PairingClientTransportFactory? clientFactory,
    this._acceptTimeout = const Duration(seconds: 30),
    this._ackTimeout = const Duration(seconds: 15),
    String Function()? createSessionId,
    Future<void> Function(Map<String, dynamic>)? persistScanner,
    Future<void> Function(Map<String, dynamic>)? persistScanned,
    Future<void> Function(Map<String, dynamic>)? rollbackScanner,
    Future<void> Function(Map<String, dynamic>)? rollbackScanned,
    Future<Map<String, dynamic>> Function()? localIdentity,
    String Function()? verificationCode,
  }) : _clientFactory = clientFactory ?? _createSocketClient,
       _createSessionId = createSessionId ?? const Uuid().v4,
       _persistScannerOverride = persistScanner,
       _persistScannedOverride = persistScanned,
       _rollbackScannerOverride = rollbackScanner,
       _rollbackScannedOverride = rollbackScanned,
       _localIdentityOverride = localIdentity,
       _verificationCodeOverride = verificationCode,
       super(const PairingState());

  static PairingClientTransport _createSocketClient({
    required PairingMessageHandler onMessage,
    required void Function() onDisconnected,
  }) => _SocketPairingClientTransport(
    onMessage: onMessage,
    onDisconnected: onDisconnected,
  );

  /// Pending scanner info (for UI to pass to acceptRequest).
  Map<String, dynamic>? get pendingScannerInfo {
    final session = _session;
    return session?.role == PairingSessionRole.scanned
        ? Map.unmodifiable(session!.peerInfo)
        : null;
  }

  // --------------------------------------------------------------------
  // Scanner side
  // --------------------------------------------------------------------

  /// Called by the scanner after reading the other device's QR code.
  ///
  /// [scannedIp]/[scannedPort] come from the QR (used only for the *initial*
  /// TCP connection). [scannedKeyBase64] is the shared AES key (also from
  /// the QR). [myDeviceName], [myPeerId], [myRole], [myPublicKey] are this
  /// device's identity. [myIp] is this device's live local IP -- sent to
  /// the scanned device so it can store it as the peer IP (more reliable
  /// than the TCP remote address, which can be wrong on NAT/VLAN setups).
  Future<void> sendRequest({
    required String scannedId,
    required String scannedIp,
    required int scannedPort,
    required String scannedKeyBase64,
    required String scannedDeviceName,
    required String scannedPublicKey,
    required String myDeviceName,
    required String myPeerId,
    required String myRole,
    required String myPublicKey,
    required String myIp,
  }) async {
    final keyBytes = base64Decode(scannedKeyBase64);
    final key = SecretKey(keyBytes);
    final sessionId = _createSessionId();
    final verificationCode = PeerFacade.generateVerificationCode(
      scannedKeyBase64,
      scannedId,
    );
    late final _PairingSession session;
    final transport = _clientFactory(
      onMessage: (type, payload) =>
          _handleScannerMessage(session, type, payload),
      onDisconnected: () => _handleDisconnect(session),
    );
    session = _PairingSession(
      id: sessionId,
      role: PairingSessionRole.scanner,
      phase: PairingSessionPhase.connecting,
      transport: transport,
      peerInfo: {
        'id': scannedId,
        'ip': scannedIp,
        'port': scannedPort,
        'key': scannedKeyBase64,
        'deviceName': scannedDeviceName,
        'publicKey': scannedPublicKey,
        'role': myRole,
      },
    );
    await _replaceSession(session);
    state = PairingState(
      isWaitingForAccept: true,
      remoteDeviceName: scannedDeviceName,
      remotePeerId: scannedId,
      verificationCode: verificationCode,
    );
    Future<void> Function()? rollback;

    try {
      final ok = await transport.connect(scannedIp, scannedPort, key);
      if (!_owns(session)) return;
      if (!ok || !transport.isCurrent) {
        session.phase = PairingSessionPhase.failed;
        state = const PairingState(
          errorCode: PairingErrorCode.connectionFailed,
        );
        return;
      }
      session.transportToken = transport.connectionToken;
      session.phase = PairingSessionPhase.waitingForAccept;
      // The response completer is part of the session and exists before this
      // send, so an immediate accept cannot race waiter installation.
      final sent = await transport.send(MessageTypes.pairingRequest, {
        'sessionId': session.id,
        'deviceName': myDeviceName,
        'peerId': myPeerId,
        'role': myRole,
        'publicKey': myPublicKey,
        'ip': myIp,
      });
      if (!sent || !_ownsCurrent(session)) {
        _complete(session, false);
      }
      final accepted = await session.response.future.timeout(
        _acceptTimeout,
        onTimeout: () => false,
      );
      if (!_owns(session)) return;
      if (!accepted) {
        session.phase = PairingSessionPhase.failed;
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: state.errorCode ?? PairingErrorCode.rejectedOrTimedOut,
        );
        return;
      }
      session.phase = PairingSessionPhase.persisting;
      rollback = await _persistScanner(session);
      if (!_ownsCurrent(session)) {
        throw StateError('Pairing transport changed during persistence');
      }
      // Enter the completion phase before sending ACK so an immediate
      // pairingComplete response cannot race the state transition.
      session.phase = PairingSessionPhase.waitingForCompletion;
      final ackSent = await transport.send(MessageTypes.pairingAck, {
        'sessionId': session.id,
      });
      if (!ackSent || !_ownsCurrent(session)) {
        throw StateError('Pairing transport disconnected before ACK');
      }
      final completed = await session.completion.future.timeout(
        _ackTimeout,
        onTimeout: () => false,
      );
      if (!completed || !_ownsCurrent(session)) {
        throw StateError('Peer did not complete pairing');
      }
      session.phase = PairingSessionPhase.completed;
      rollback = null;
      state = const PairingState();
    } catch (e) {
      try {
        await rollback?.call();
      } catch (rollbackError) {
        _logger.e('Pairing rollback failed: $rollbackError');
      }
      if (!_owns(session)) return;
      session.phase = PairingSessionPhase.failed;
      _logger.e('Pairing sendRequest failed: $e');
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        errorDetail: '$e',
      );
    } finally {
      await _cleanupSession(session);
    }
  }

  void _handleScannerMessage(
    _PairingSession session,
    String type,
    Map<String, dynamic>? payload,
  ) {
    if (!_ownsCurrent(session)) return;
    final responseSessionId = payload?['sessionId'];
    if (responseSessionId is! String || responseSessionId.isEmpty) {
      if (session.phase == PairingSessionPhase.waitingForAccept) {
        state = const PairingState(
          errorCode: PairingErrorCode.handshakeFailed,
          errorDetail: 'Pairing response is missing its session ID',
        );
        session.phase = PairingSessionPhase.failed;
        _complete(session, false);
      }
      return;
    }
    if (responseSessionId != session.id) return;
    switch (type) {
      case MessageTypes.pairingAccept:
        if (session.phase != PairingSessionPhase.waitingForAccept ||
            !_validIdentity(payload, session.peerInfo)) {
          if (session.phase == PairingSessionPhase.waitingForAccept) {
            state = const PairingState(
              errorCode: PairingErrorCode.handshakeFailed,
              errorDetail: 'Pairing accept identity did not match the QR',
            );
            _complete(session, false);
          }
          return;
        }
        session.responsePayload = payload;
        session.phase = PairingSessionPhase.persisting;
        state = state.copyWith(isWaitingForAccept: false);
        _complete(session, true);
        break;
      case MessageTypes.pairingReject:
        if (session.phase != PairingSessionPhase.waitingForAccept) return;
        session.phase = PairingSessionPhase.failed;
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: PairingErrorCode.rejected,
        );
        _complete(session, false);
        break;
      case MessageTypes.pairingComplete:
        if (session.phase != PairingSessionPhase.waitingForCompletion) return;
        session.completion.complete(true);
        break;
      case MessageTypes.pairingAbort:
        if (session.phase != PairingSessionPhase.waitingForCompletion) return;
        session.completion.complete(false);
        break;
    }
  }

  // --------------------------------------------------------------------
  // Scanned side  (called from ConnectionFacade._handleIncomingMessage)
  // --------------------------------------------------------------------

  /// Called when a `pairingRequest` message arrives on the *scanned* device.
  /// Updates state so the UI can show a confirmation dialog.
  Future<void> handleIncomingRequest(
    PairingTransport transport,
    Map<String, dynamic> payload,
  ) async {
    final sessionId = payload['sessionId'];
    final peerId = payload['peerId'];
    final publicKey = payload['publicKey'];
    final role = payload['role'];
    if (!transport.isCurrent ||
        sessionId is! String ||
        sessionId.isEmpty ||
        peerId is! String ||
        peerId.isEmpty ||
        publicKey is! String ||
        publicKey.isEmpty ||
        role is! String ||
        role.isEmpty) {
      _logger.w('Rejected malformed or stale pairing request.');
      state = const PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        errorDetail: 'Pairing request is malformed or missing its session ID',
      );
      return;
    }
    if (_session != null) {
      _logger.w('Rejected out-of-order pairing request while session active.');
      return;
    }
    // Left null (not defaulted here) so the UI's own
    // `remoteDeviceName ?? l.pairingUnknownDevice` fallback -- localized to
    // *this* device's language -- is what actually renders, instead of a
    // fixed-language placeholder baked in before the widget ever sees it.
    final deviceName = payload['deviceName'] as String?;
    final scannerIp = payload['ip'] as String?;

    final verificationCode =
        _verificationCodeOverride?.call() ??
        _ref.read(peerFacadeProvider)?.verificationCode ??
        '';

    state = PairingState(
      isShowingRequest: true,
      remoteDeviceName: deviceName,
      remotePeerId: peerId,
      verificationCode: verificationCode,
    );
    _logger.i(
      'Incoming pairing request from $deviceName ($peerId, pubKey=${publicKey.substring(0, publicKey.length > 8 ? 8 : publicKey.length)}..., ip=$scannerIp)',
    );

    final session = _PairingSession(
      id: sessionId,
      role: PairingSessionRole.scanned,
      phase: PairingSessionPhase.awaitingDecision,
      transport: transport,
      peerInfo: {
        'deviceName': deviceName,
        'peerId': peerId,
        'role': role,
        'publicKey': publicKey,
        'ip': scannerIp,
      },
    )..transportToken = transport.connectionToken;
    await _replaceSession(session);
  }

  /// Called by the UI when the *scanned* device user confirms the request.
  ///
  /// [transport] is the live connection port from ConnectionFacade so we
  /// can reply on the same channel.  [scannerInfo] carries the scanner's
  /// identity to persist as our peer.  [myIp] is this device's live local
  /// IP -- sent to the scanner so it can store it as the peer IP (more
  /// reliable than the TCP remote address, which can be wrong on NAT/VLAN
  /// setups).
  ///
  /// Deliberately does NOT persist the paired peer until the scanner's
  /// pairingAck confirms it actually completed its own side too (see
  /// pairingAck's doc comment). Without this, a pairingAccept lost after
  /// being sent (dropped packet, scanner already gave up waiting) used to
  /// leave this device believing it was paired while the scanner had
  /// nothing saved at all -- an asymmetric state a plain re-scan couldn't
  /// cleanly recover from, since this device's permanent socket would then
  /// demand real challenge-response auth the scanner isn't set up to do.
  Future<bool> acceptRequest({
    required PairingTransport transport,
    required String myIp,
  }) async {
    final session = _session;
    if (session == null ||
        session.role != PairingSessionRole.scanned ||
        session.phase != PairingSessionPhase.awaitingDecision ||
        !_matchesTransport(session, transport)) {
      return false;
    }
    final identity = await _localIdentity();
    if (!_ownsCurrent(session)) return false;
    session.phase = PairingSessionPhase.waitingForAck;
    state = state.copyWith(isShowingRequest: false, isFinalizing: true);
    // The session's ACK completer exists before pairingAccept is sent.
    final sent = await transport.send(MessageTypes.pairingAccept, {
      'sessionId': session.id,
      // Sent to the other device as identity data -- locale-neutral
      // fallback, same reasoning as peer_facade.dart's _getDeviceName().
      'deviceName': identity['deviceName'],
      'peerId': identity['peerId'],
      'publicKey': identity['publicKey'],
      'role': identity['role'],
      'ip': myIp,
    });
    if (!sent || !_ownsCurrent(session)) _complete(session, false);
    final acked = await session.response.future.timeout(
      _ackTimeout,
      onTimeout: () => false,
    );
    if (!_owns(session)) return false;
    if (!acked) {
      session.phase = PairingSessionPhase.failed;
      state = const PairingState(errorCode: PairingErrorCode.ackTimeout);
      await _cleanupSession(session);
      return false;
    }
    Future<void> Function()? rollback;
    try {
      session.phase = PairingSessionPhase.persisting;
      rollback = await _persistScanned(session);
      if (!_owns(session)) {
        await rollback();
        return false;
      }
      final completed = await transport.send(MessageTypes.pairingComplete, {
        'sessionId': session.id,
      });
      if (!completed || !_ownsCurrent(session)) {
        throw StateError('Failed to confirm pairing completion');
      }
      session.phase = PairingSessionPhase.completed;
      rollback = null;
      state = const PairingState();
      return true;
    } catch (e) {
      try {
        await rollback?.call();
      } catch (rollbackError) {
        _logger.e('Pairing rollback failed: $rollbackError');
      }
      session.phase = PairingSessionPhase.failed;
      if (transport.isCurrent) {
        await transport.send(MessageTypes.pairingAbort, {
          'sessionId': session.id,
        });
      }
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        errorDetail: '$e',
      );
      return false;
    } finally {
      await _cleanupSession(session);
    }
  }

  /// Scanned side: the scanner confirmed it persisted its own end. Safe to
  /// commit our side now (see acceptRequest).
  void handlePairingAck(
    PairingTransport transport,
    Map<String, dynamic> payload,
  ) {
    final session = _session;
    if (session == null ||
        session.role != PairingSessionRole.scanned ||
        session.phase != PairingSessionPhase.waitingForAck ||
        payload['sessionId'] != session.id ||
        !_matchesTransport(session, transport)) {
      return;
    }
    session.phase = PairingSessionPhase.persisting;
    _complete(session, true);
  }

  void handleTransportDisconnected(PairingTransport transport) {
    final session = _session;
    if (session == null ||
        session.transportToken != transport.connectionToken) {
      return;
    }
    _complete(session, false);
  }

  /// Called by the UI when the *scanned* device user rejects the request.
  Future<void> rejectRequest({required PairingTransport transport}) async {
    final session = _session;
    if (session == null ||
        session.role != PairingSessionRole.scanned ||
        session.phase != PairingSessionPhase.awaitingDecision ||
        !_matchesTransport(session, transport)) {
      return;
    }
    await transport.send(MessageTypes.pairingReject, {'sessionId': session.id});
    state = const PairingState();
    await _cleanupSession(session);
  }

  /// Reset to idle (e.g. dialog dismissed without action).
  void reset() {
    final session = _session;
    state = const PairingState();
    if (session != null) {
      _complete(session, false);
      if (!session.completion.isCompleted) {
        session.completion.complete(false);
      }
      _cleanupSession(session);
    }
  }

  bool _owns(_PairingSession session) => identical(_session, session);

  bool _ownsCurrent(_PairingSession session) =>
      _owns(session) &&
      session.transport.isCurrent &&
      session.transportToken == session.transport.connectionToken;

  bool _matchesTransport(_PairingSession session, PairingTransport transport) =>
      transport.isCurrent &&
      session.transportToken == transport.connectionToken;

  bool _validIdentity(
    Map<String, dynamic>? payload,
    Map<String, dynamic> expected,
  ) =>
      payload != null &&
      payload['peerId'] is String &&
      payload['publicKey'] is String &&
      payload['peerId'] == expected['id'] &&
      payload['publicKey'] == expected['publicKey'];

  void _complete(_PairingSession session, bool result) {
    if (!session.response.isCompleted) session.response.complete(result);
  }

  void _handleDisconnect(_PairingSession session) {
    if (!_owns(session)) return;
    _complete(session, false);
    if (!session.completion.isCompleted) session.completion.complete(false);
  }

  Future<void> _replaceSession(_PairingSession next) async {
    final previous = _session;
    _session = next;
    if (previous != null) {
      _complete(previous, false);
      if (!previous.completion.isCompleted) {
        previous.completion.complete(false);
      }
      await _cleanupSession(previous);
    }
  }

  Future<Future<void> Function()> _persistScanner(
    _PairingSession session,
  ) async {
    final accept = session.responsePayload!;
    final data = {
      ...session.peerInfo,
      'ip': session.transport.remoteAddress ?? session.peerInfo['ip'],
      'deviceName': (accept['deviceName'] as String?)?.isNotEmpty == true
          ? accept['deviceName']
          : session.peerInfo['deviceName'],
    };
    final override = _persistScannerOverride;
    if (override != null) {
      try {
        await override(data);
      } catch (_) {
        await _rollbackScannerOverride?.call(data);
        rethrow;
      }
      return () async => _rollbackScannerOverride?.call(data);
    }
    final peerFacade = _ref.read(peerFacadeProvider.notifier);
    final previous = _ref.read(peerFacadeProvider);
    try {
      await peerFacade.createPeerFromQr(
        id: data['id']! as String,
        ip: data['ip']! as String,
        port: data['port']! as int,
        keyBase64: data['key']! as String,
        role: data['role']! as String,
        deviceName: data['deviceName']! as String,
        publicKey: data['publicKey']! as String,
      );
    } catch (_) {
      await peerFacade.rollbackPairing(
        previous: previous,
        attemptedId: data['id']! as String,
      );
      rethrow;
    }
    return () => peerFacade.rollbackPairing(
      previous: previous,
      attemptedId: data['id']! as String,
    );
  }

  Future<Map<String, dynamic>> _localIdentity() async {
    final override = _localIdentityOverride;
    if (override != null) return override();
    final peer = _ref.read(peerFacadeProvider);
    return {
      'deviceName': peer?.deviceName ?? 'Unknown Device',
      'peerId': peer?.id ?? '',
      'publicKey': await KeyStore.ensureDeviceKeyPair(),
      'role': peer?.role ?? 'main',
    };
  }

  Future<Future<void> Function()> _persistScanned(
    _PairingSession session,
  ) async {
    final data = {...session.peerInfo, 'ip': session.transport.remoteAddress};
    final override = _persistScannedOverride;
    if (override != null) {
      try {
        await override(data);
      } catch (_) {
        await _rollbackScannedOverride?.call(data);
        rethrow;
      }
      return () async => _rollbackScannedOverride?.call(data);
    }
    final peerFacade = _ref.read(peerFacadeProvider.notifier);
    final previous = _ref.read(peerFacadeProvider);
    try {
      await peerFacade.applyPairedPeer(
        id: data['peerId']! as String,
        deviceName: data['deviceName'] as String? ?? 'Unknown Device',
        publicKey: data['publicKey']! as String,
        ip: data['ip'] as String?,
      );
    } catch (_) {
      await peerFacade.rollbackPairing(
        previous: previous,
        attemptedId: data['peerId']! as String,
      );
      rethrow;
    }
    return () => peerFacade.rollbackPairing(
      previous: previous,
      attemptedId: data['peerId']! as String,
    );
  }

  Future<void> _cleanupSession(_PairingSession session) async {
    if (session.cleanedUp) return;
    session.cleanedUp = true;
    if (_owns(session)) _session = null;
    if (session.transport is PairingClientTransport) {
      try {
        await (session.transport as PairingClientTransport).disconnect();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) _cleanupSession(session);
    super.dispose();
  }
}
