import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/peer_discovery.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/pairing/pairing_runtime_state.dart';
import 'package:mirrorline/features/pairing/pairing_identity_guard.dart';
import 'package:mirrorline/features/pairing/pairing_endpoint_selector.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/connection/connection_endpoint_guard.dart';
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
  final bool isComplete; // Both sides persisted the completed pairing
  final String? remoteDeviceName; // Other device's name
  final String? remotePeerId; // Other device's peer id
  final String? verificationCode; // 6-digit code shared via QR/key
  final PairingErrorCode? errorCode;
  final String?
  errorDetail; // extra context for PairingErrorCode.handshakeFailed
  final PairingEndpointDiagnostic? endpointDiagnostic;

  const PairingState({
    this.isWaitingForAccept = false,
    this.isShowingRequest = false,
    this.isFinalizing = false,
    this.isComplete = false,
    this.remoteDeviceName,
    this.remotePeerId,
    this.verificationCode,
    this.errorCode,
    this.errorDetail,
    this.endpointDiagnostic,
  });

  PairingState copyWith({
    bool? isWaitingForAccept,
    bool? isShowingRequest,
    bool? isFinalizing,
    bool? isComplete,
    String? remoteDeviceName,
    String? remotePeerId,
    String? verificationCode,
    PairingErrorCode? errorCode,
    String? errorDetail,
    PairingEndpointDiagnostic? endpointDiagnostic,
    bool clearError = false,
    bool clearEndpointDiagnostic = false,
  }) {
    return PairingState(
      isWaitingForAccept: isWaitingForAccept ?? this.isWaitingForAccept,
      isShowingRequest: isShowingRequest ?? this.isShowingRequest,
      isFinalizing: isFinalizing ?? this.isFinalizing,
      isComplete: isComplete ?? this.isComplete,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      remotePeerId: remotePeerId ?? this.remotePeerId,
      verificationCode: verificationCode ?? this.verificationCode,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      errorDetail: clearError ? null : errorDetail ?? this.errorDetail,
      endpointDiagnostic: clearEndpointDiagnostic
          ? null
          : endpointDiagnostic ?? this.endpointDiagnostic,
    );
  }

  PairingRuntimeState runtimeStateFor(Peer? peer) => resolvePairingRuntimeState(
    peer: peer,
    isPairingPending: isWaitingForAccept || isShowingRequest || isFinalizing,
    isPairingComplete: isComplete,
  );
}

final pairingFacadeProvider =
    StateNotifierProvider<PairingFacade, PairingState>((ref) {
      return PairingFacade(ref);
    });

typedef PairingHandshakeSocketFactory =
    SocketManager Function({
      required void Function(MirrorMessage) onMessage,
      required void Function() onConnected,
      required void Function() onDisconnected,
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
  static const _defaultPairingPort = 45678;

  final Logger _logger;
  final Ref _ref;
  final Future<Iterable<String>?> Function() _getLocalAddresses;
  final Future<({String id, String publicKey})> Function() _getLocalIdentity;
  final Future<void> Function() _invalidateNormalConnectionWork;
  final Future<bool> Function(SocketManager, String, int, SecretKey)
  _connectHandshakeSocket;
  final PairingHandshakeSocketFactory _createHandshakeSocket;

  /// Temporary socket used by the *scanner* side during handshake.
  SocketManager? _handshakeSocket;
  SecretKey? _handshakeKey;
  Completer<bool>? _acceptCompleter;

  /// Stashed accept payload from the scanned device (set by
  /// _handleHandshakeMessage when pairingAccept arrives). Holds the
  /// scanned device's real IP/role/deviceName as it claims them -- used
  /// to overwrite the QR-derived values (which may be stale or wrong on
  /// NAT/VLAN setups) when persisting the peer.
  Map<String, dynamic>? _acceptPayload;
  String? _acceptRemoteAddress;

  /// Scanned side: resolves once the scanner's pairingAck arrives (or times
  /// out). Persisting the paired peer (applyPairedPeer) is gated on this so
  /// a lost pairingAccept can't leave the scanned device believing it's
  /// paired while the scanner never actually completed its own side --
  /// same reasoning as SocketManager's authOk/authAck two-step commit.
  Completer<bool>? _pairAckCompleter;
  SocketManager? _pairAckSocket;

  /// Stashed scanner info on the *scanned* side (set by handleIncomingRequest).
  Map<String, dynamic>? _pendingScannerInfo;
  String? _transactionId;
  String? _expectedPeerId;
  String? _expectedPeerPublicKey;
  String? _expectedAckPeerId;
  String? _expectedAckPeerPublicKey;
  int _incomingRequestGeneration = 0;

  PairingFacade(
    Ref ref, {
    Logger? logger,
    Future<Iterable<String>?> Function()? getLocalAddresses,
    Future<({String id, String publicKey})> Function()? getLocalIdentity,
    Future<void> Function()? invalidateNormalConnectionWork,
    Future<bool> Function(SocketManager, String, int, SecretKey)?
    connectHandshakeSocket,
    PairingHandshakeSocketFactory? createHandshakeSocket,
  }) : _ref = ref,
       _logger = logger ?? Logger(),
       _getLocalAddresses =
           getLocalAddresses ?? PeerDiscovery().getAllLocalAddresses,
       _getLocalIdentity = getLocalIdentity ?? _readLocalIdentity,
       _invalidateNormalConnectionWork =
           invalidateNormalConnectionWork ??
           (() => ref
               .read(connectionFacadeProvider.notifier)
               .invalidateNormalConnectionWork()),
       _connectHandshakeSocket =
           connectHandshakeSocket ??
           ((socket, ip, port, key) => socket.connect(ip, port, key)),
       _createHandshakeSocket =
           createHandshakeSocket ??
           (({
             required onMessage,
             required onConnected,
             required onDisconnected,
           }) => SocketManager(
             onMessage: onMessage,
             onConnected: onConnected,
             onDisconnected: onDisconnected,
           )),
       super(const PairingState());

  /// Pending scanner info (for UI to pass to acceptRequest).
  Map<String, dynamic>? get pendingScannerInfo => _pendingScannerInfo;

  // --------------------------------------------------------------------
  // Scanner side
  // --------------------------------------------------------------------

  /// Called by the scanner after reading the other device's QR code.
  ///
  /// [scannedIp]/[scannedPort] come from the QR (used only for the *initial*
  /// TCP connection). [scannedKeyBase64] is the shared AES key (also from
  /// the QR). [myIp] is this device's live local IP. The remaining local
  /// identity fields are resolved from self identity storage so a remote peer
  /// record can never be advertised as this device.
  Future<void> sendRequest({
    required String scannedId,
    required String scannedIp,
    required int scannedPort,
    required String scannedKeyBase64,
    required String scannedDeviceName,
    required String scannedPublicKey,
    required String myIp,
  }) async {
    final localIdentity = await _ref
        .read(peerFacadeProvider.notifier)
        .getLocalPairingIdentity(ip: myIp);
    if (localIdentity == null) {
      _logPairingFailure(
        stage: 'qr-validation',
        reason: 'local-identity-unavailable',
      );
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    if (!isValidRemoteIdentity(
      remoteId: scannedId,
      remotePublicKey: scannedPublicKey,
      localId: localIdentity.id,
      localPublicKey: localIdentity.publicKey,
    )) {
      _logPairingFailure(
        stage: 'qr-validation',
        reason: 'invalid-remote-identity',
      );
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    _logger.i('Pairing QR identity validated.');
    final localAddresses = await _getLocalAddresses();
    if (localAddresses == null ||
        localAddresses.isEmpty ||
        !isUsableEndpoint(
          ip: scannedIp,
          port: scannedPort,
          localIps: localAddresses,
        )) {
      _logPairingFailure(
        stage: 'qr-validation',
        reason: 'invalid-remote-endpoint',
      );
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    await _invalidateNormalConnectionWork();
    late final SecretKey key;
    try {
      key = SecretKey(base64Decode(scannedKeyBase64));
    } on FormatException catch (error) {
      _logPairingFailure(
        stage: 'qr-validation',
        reason: 'invalid-key-encoding',
        error: error,
      );
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    _handshakeKey = key;
    _clearOutgoingTransaction();
    final acceptCompleter = Completer<bool>();
    _acceptCompleter = acceptCompleter;
    final transactionId = const Uuid().v4();
    _transactionId = transactionId;
    _expectedPeerId = scannedId;
    _expectedPeerPublicKey = scannedPublicKey;

    final verificationCode = PeerFacade.generateVerificationCode(
      scannedKeyBase64,
      scannedId,
      expectedPublicKeys: [localIdentity.publicKey, scannedPublicKey],
    );

    state = PairingState(
      isWaitingForAccept: true,
      remoteDeviceName: scannedDeviceName,
      remotePeerId: scannedId,
      verificationCode: verificationCode,
    );

    late final SocketManager handshakeSocket;
    handshakeSocket = _createHandshakeSocket(
      onMessage: (message) {
        if (_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) {
          _handleHandshakeMessage(message, handshakeSocket, acceptCompleter);
        }
      },
      onConnected: () {
        _logger.i('Handshake socket connected to $scannedIp:$scannedPort');
      },
      onDisconnected: () {
        _logger.w('Handshake socket disconnected.');
        if (identical(_handshakeSocket, handshakeSocket) &&
            identical(_acceptCompleter, acceptCompleter) &&
            !acceptCompleter.isCompleted) {
          acceptCompleter.complete(false);
        }
      },
    );
    _handshakeSocket = handshakeSocket;

    try {
      final ok = await _connectHandshakeSocket(
        handshakeSocket,
        scannedIp,
        scannedPort,
        key,
      );
      if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
      if (!ok) {
        _logPairingFailure(
          stage: 'bootstrap-connect',
          reason: 'connection-failed',
        );
        state = const PairingState(
          errorCode: PairingErrorCode.connectionFailed,
        );
        await _cleanupSocket(owner: handshakeSocket);
        return;
      }

      final requestSent = await handshakeSocket
          .sendMessage(MessageTypes.pairingRequest, {
            'transactionId': transactionId,
            'deviceName': localIdentity.deviceName,
            'peerId': localIdentity.id,
            'role': localIdentity.role,
            'publicKey': localIdentity.publicKey,
            'ip': localIdentity.ip,
          });
      if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
      if (!requestSent) {
        _logPairingFailure(
          stage: 'request-write',
          reason: 'socket-write-failed',
        );
        state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
        return;
      }
      _logger.i('Pairing request delivered.');

      final accepted = await acceptCompleter.future.timeout(
        SecurityConstants.pairingTimeout,
        onTimeout: () => false,
      );
      if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;

      if (accepted) {
        // Scanner side: save the scanned device's info as our peer record.
        // The Peer record represents the *other* device: id/ip/port/name are
        // the scanned device's.  But `role` is THIS device's own role
        // (so ConnectionFacade knows whether to start as source or main).
        // `key` is the shared AES key from the QR.  `publicKey` is the
        // scanned device's Ed25519 public key for auth.
        //
        // Prefer the IP/deviceName the scanned device itself reported in
        // its pairingAccept (more reliable than the QR's IP, which may be
        // stale or wrong on NAT/VLAN setups) -- fall back to the QR values
        // if the scanned device didn't claim an IP.
        final accept = _acceptPayload;
        final endpoint = await _selectEndpoint(
          stage: PairingEndpointStage.accept,
          claimedIp: accept?['ip'],
          liveIp: _acceptRemoteAddress,
          fallbackIp: scannedIp,
          port: scannedPort,
        );
        if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
        if (!endpoint.isUsable) {
          _logEndpointDiagnostic(endpoint.diagnostic);
          _logPairingFailure(
            stage: 'accept-endpoint-selection',
            reason: endpoint.diagnostic?.issue.name ?? 'no-usable-endpoint',
          );
          state = PairingState(
            errorCode: PairingErrorCode.handshakeFailed,
            endpointDiagnostic: endpoint.diagnostic,
          );
          return;
        }
        _logEndpointDiagnostic(endpoint.diagnostic);
        final peerDeviceName =
            (accept?['deviceName'] as String?)?.isNotEmpty == true
            ? accept!['deviceName'] as String
            : scannedDeviceName;
        try {
          await _ref
              .read(peerFacadeProvider.notifier)
              .createPeerFromQr(
                id: scannedId,
                ip: endpoint.ip!,
                port: scannedPort,
                keyBase64: scannedKeyBase64,
                role: localIdentity.role,
                deviceName: peerDeviceName,
                publicKey: scannedPublicKey,
              );
        } catch (error) {
          if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) {
            return;
          }
          _logPairingFailure(
            stage: 'scanner-persist',
            reason: 'persistence-failed',
            error: error,
          );
          state = PairingState(
            errorCode: PairingErrorCode.handshakeFailed,
            errorDetail: error.runtimeType.toString(),
          );
          return;
        }
        if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
        // Tell the scanned side we actually persisted our end -- see
        // pairingAck's doc comment in message_protocol.dart. Sent on the
        // same handshake socket before it's torn down below.
        _logger.i('Sending pairingAck on handshake socket...');
        final ackSent = await handshakeSocket
            .sendMessage(MessageTypes.pairingAck, {
              'transactionId': transactionId,
              'peerId': localIdentity.id,
              'publicKey': localIdentity.publicKey,
            });
        if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
        if (!ackSent) {
          _logPairingFailure(stage: 'ack-write', reason: 'socket-write-failed');
          state = const PairingState(
            errorCode: PairingErrorCode.handshakeFailed,
          );
          return;
        }
        state = state.copyWith(
          isComplete: true,
          endpointDiagnostic: endpoint.diagnostic,
        );
      } else {
        if (state.errorCode != PairingErrorCode.rejected) {
          _logPairingFailure(
            stage: 'accept-wait',
            reason: 'timeout-or-disconnect',
          );
        }
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: PairingErrorCode.rejectedOrTimedOut,
        );
      }
    } catch (e) {
      if (!_ownsOutgoingTransaction(handshakeSocket, acceptCompleter)) return;
      _logPairingFailure(
        stage: 'scanner-transaction',
        reason: 'unexpected-failure',
        error: e,
      );
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        errorDetail: e.runtimeType.toString(),
      );
    } finally {
      _clearOutgoingTransaction(owner: acceptCompleter);
      await _cleanupSocket(owner: handshakeSocket);
    }
  }

  void _handleHandshakeMessage(
    MirrorMessage message,
    SocketManager socket,
    Completer<bool> completer,
  ) async {
    final key = _handshakeKey;
    if (key == null) {
      _logPairingFailure(stage: 'handshake-decrypt', reason: 'key-unavailable');
      return;
    }

    final metadata = CryptoManager.canonicalMessageMetadata(
      version: message.protocolVersion,
      type: message.type,
      id: message.id,
      timestamp: message.timestamp,
    );
    String? decrypted;
    try {
      decrypted = await CryptoManager.decryptWithAad(
        key,
        message.payload,
        aad: utf8.encode(metadata),
      );
    } catch (error) {
      if (!_ownsOutgoingTransaction(socket, completer)) return;
      _logPairingFailure(
        stage: 'handshake-decrypt',
        reason: 'decrypt-failed',
        error: error,
      );
      return;
    }
    if (!_ownsOutgoingTransaction(socket, completer)) return;
    if (decrypted == null) {
      _logPairingFailure(stage: 'handshake-decrypt', reason: 'decrypt-failed');
      return;
    }

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (error) {
      if (!_ownsOutgoingTransaction(socket, completer)) return;
      _logPairingFailure(
        stage: 'handshake-decode',
        reason: 'invalid-payload',
        error: error,
      );
      payload = null;
    }
    if (!_ownsOutgoingTransaction(socket, completer)) return;
    if (payload == null) return;

    switch (message.type) {
      case MessageTypes.pairingAccept:
        if (!_isMatchingTransaction(payload) ||
            payload['peerId'] != _expectedPeerId ||
            payload['publicKey'] != _expectedPeerPublicKey ||
            !_isSupportedRole(payload['role'])) {
          _logPairingFailure(
            stage: 'accept-validation',
            reason: 'transaction-or-identity-mismatch',
          );
          break;
        }
        _logger.i('Pairing accepted by remote.');
        _acceptPayload = payload;
        _acceptRemoteAddress = _handshakeSocket?.remoteAddress;
        state = state.copyWith(isWaitingForAccept: false);
        if (!completer.isCompleted) completer.complete(true);
        break;

      case MessageTypes.pairingReject:
        _logPairingFailure(stage: 'accept-wait', reason: 'remote-rejected');
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: PairingErrorCode.rejected,
        );
        if (!completer.isCompleted) completer.complete(false);
        break;
    }
  }

  // --------------------------------------------------------------------
  // Scanned side  (called from ConnectionFacade._handleIncomingMessage)
  // --------------------------------------------------------------------

  /// Called when a `pairingRequest` message arrives on the *scanned* device.
  /// Updates state so the UI can show a confirmation dialog.
  Future<void> handleIncomingRequest(
    Map<String, dynamic> payload, {
    String? liveRemoteAddress,
  }) async {
    await _invalidateNormalConnectionWork();
    // Left null (not defaulted here) so the UI's own
    // `remoteDeviceName ?? l.pairingUnknownDevice` fallback -- localized to
    // *this* device's language -- is what actually renders, instead of a
    // fixed-language placeholder baked in before the widget ever sees it.
    final deviceName = payload['deviceName'] as String?;
    final peerId = payload['peerId'] as String? ?? '';
    final publicKey = payload['publicKey'] as String? ?? '';
    final role = payload['role'] as String? ?? '';
    final transactionId = payload['transactionId'] as String? ?? '';
    if (transactionId.isEmpty ||
        peerId.isEmpty ||
        publicKey.isEmpty ||
        !_isSupportedRole(role)) {
      _logPairingFailure(
        stage: 'request-validation',
        reason: 'invalid-transaction-or-identity',
      );
      return;
    }

    final localIdentity = await _getLocalIdentity();
    final localId = localIdentity.id;
    final localPublicKey = localIdentity.publicKey;
    if (localId.isEmpty) {
      _logPairingFailure(
        stage: 'request-validation',
        reason: 'local-identity-unavailable',
      );
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    if (isSelfRemoteIdentity(
      remoteId: peerId,
      remotePublicKey: publicKey,
      localId: localId,
      localPublicKey: localPublicKey,
    )) {
      _logPairingFailure(stage: 'request-validation', reason: 'self-identity');
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    final requestGeneration = ++_incomingRequestGeneration;

    final endpoint = await _selectEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: payload['ip'],
      liveIp: liveRemoteAddress,
      fallbackIp: null,
      port: _defaultPairingPort,
    );
    if (requestGeneration != _incomingRequestGeneration) return;
    if (!endpoint.isUsable) {
      _logEndpointDiagnostic(endpoint.diagnostic);
      _logPairingFailure(
        stage: 'request-endpoint-selection',
        reason: endpoint.diagnostic?.issue.name ?? 'no-usable-endpoint',
      );
      if (_pendingScannerInfo != null || _pairAckCompleter != null) {
        _logger.w('Rejected unsafe request while another pairing is active.');
        return;
      }
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        endpointDiagnostic: endpoint.diagnostic,
      );
      return;
    }
    _logEndpointDiagnostic(endpoint.diagnostic);

    final peer = _ref.read(peerFacadeProvider);
    final verificationCode = peer == null || localId.isEmpty
        ? ''
        : PeerFacade.generateVerificationCode(
            peer.key,
            localId,
            expectedPublicKeys: [
              await _ref.read(peerFacadeProvider.notifier).getMyPublicKey(),
              publicKey,
            ],
          );
    if (requestGeneration != _incomingRequestGeneration) return;

    _clearIncomingTransaction();
    state = PairingState(
      isShowingRequest: true,
      remoteDeviceName: deviceName,
      remotePeerId: peerId,
      verificationCode: verificationCode,
      endpointDiagnostic: endpoint.diagnostic,
    );
    _logger.i('Incoming pairing request validated: transport=qr-bootstrap');

    // Stash the scanner's info for later use in acceptRequest.
    _pendingScannerInfo = {
      'deviceName': deviceName,
      'peerId': peerId,
      'role': role,
      'publicKey': publicKey,
      'ip': endpoint.ip,
      'transactionId': transactionId,
    };
  }

  /// Called by the UI when the *scanned* device user confirms the request.
  ///
  /// [socketManager] is the live connection from ConnectionFacade so we
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
  Future<void> acceptRequest({
    required SocketManager socketManager,
    required Map<String, dynamic> scannerInfo,
    required String myIp,
  }) async {
    final localIdentity = await _ref
        .read(peerFacadeProvider.notifier)
        .getLocalPairingIdentity(ip: myIp);
    if (localIdentity == null) {
      _logPairingFailure(
        stage: 'accept-validation',
        reason: 'local-identity-unavailable',
      );
      _clearIncomingTransaction();
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    final transactionId = scannerInfo['transactionId'] as String? ?? '';
    final scannerId = scannerInfo['peerId'] as String? ?? '';
    final scannerPublicKey = scannerInfo['publicKey'] as String? ?? '';
    final scannerRole = scannerInfo['role'] as String? ?? '';
    if (transactionId.isEmpty ||
        transactionId != _pendingScannerInfo?['transactionId'] ||
        scannerId.isEmpty ||
        scannerPublicKey.isEmpty ||
        !_isSupportedRole(scannerRole)) {
      _logPairingFailure(
        stage: 'accept-validation',
        reason: 'invalid-transaction-or-identity',
      );
      _clearIncomingTransaction();
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }
    final localId = localIdentity.id;
    if (isSelfRemoteIdentity(
      remoteId: scannerId,
      remotePublicKey: scannerPublicKey,
      localId: localId,
      localPublicKey: localIdentity.publicKey,
    )) {
      _logPairingFailure(stage: 'accept-validation', reason: 'self-identity');
      _clearIncomingTransaction();
      state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
      return;
    }

    final endpoint = await _selectEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: scannerInfo['ip'],
      liveIp: socketManager.remoteAddress,
      fallbackIp: null,
      port: _defaultPairingPort,
    );
    if (_pendingScannerInfo?['transactionId'] != transactionId) return;
    if (!endpoint.isUsable) {
      _logEndpointDiagnostic(endpoint.diagnostic);
      _logPairingFailure(
        stage: 'request-endpoint-selection',
        reason: endpoint.diagnostic?.issue.name ?? 'no-usable-endpoint',
      );
      _clearIncomingTransaction();
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        endpointDiagnostic: endpoint.diagnostic,
      );
      return;
    }
    _logEndpointDiagnostic(endpoint.diagnostic);
    final endpointDiagnostic = endpoint.diagnostic ?? state.endpointDiagnostic;

    _clearIncomingTransaction(clearPendingInfo: false);
    _expectedAckPeerId = scannerId;
    _expectedAckPeerPublicKey = scannerPublicKey;
    final ackCompleter = Completer<bool>();
    _pairAckCompleter = ackCompleter;
    _pairAckSocket = socketManager;
    state = state.copyWith(isShowingRequest: false, isFinalizing: true);

    try {
      _logger.i('Sending pairingAccept to scanner...');
      final acceptSent = await socketManager.sendMessage(
        MessageTypes.pairingAccept,
        {
          'transactionId': transactionId,
          // Sent to the other device as identity data -- locale-neutral
          // fallback, same reasoning as peer_facade.dart's _getDeviceName().
          'deviceName': localIdentity.deviceName,
          'peerId': localIdentity.id,
          'publicKey': localIdentity.publicKey,
          'role': localIdentity.role,
          'ip': localIdentity.ip,
        },
      );
      if (!identical(_pairAckCompleter, ackCompleter)) return;
      if (!acceptSent) {
        _logPairingFailure(
          stage: 'accept-write',
          reason: 'socket-write-failed',
        );
        state = const PairingState(errorCode: PairingErrorCode.handshakeFailed);
        return;
      }

      final acked = await ackCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      if (!identical(_pairAckCompleter, ackCompleter)) return;

      if (!acked) {
        _logPairingFailure(stage: 'ack-wait', reason: 'timeout-or-disconnect');
        state = const PairingState(errorCode: PairingErrorCode.ackTimeout);
        return;
      }

      // Persist the scanner's full identity (id, name, public key), and its
      // real IP. Prefer the IP the scanner itself claimed in its
      // pairingRequest (more reliable than the TCP remote address, which can
      // be wrong on NAT/VLAN setups) -- fall back to the TCP remote address
      // if the scanner didn't claim an IP.
      // Persisted identity data -- locale-neutral fallback, same reasoning as
      // peer_facade.dart's _getDeviceName().
      final scannerDeviceName =
          scannerInfo['deviceName'] as String? ?? 'Unknown Device';
      try {
        await _ref
            .read(peerFacadeProvider.notifier)
            .applyPairedPeer(
              id: scannerId,
              deviceName: scannerDeviceName,
              publicKey: scannerPublicKey,
              ip: endpoint.ip,
            );
      } catch (error) {
        if (!identical(_pairAckCompleter, ackCompleter)) return;
        _logPairingFailure(
          stage: 'scanned-persist',
          reason: 'persistence-failed',
          error: error,
        );
        state = PairingState(
          errorCode: PairingErrorCode.handshakeFailed,
          errorDetail: error.runtimeType.toString(),
        );
        return;
      }
      if (!identical(_pairAckCompleter, ackCompleter)) return;

      state = state.copyWith(
        isFinalizing: false,
        isComplete: true,
        endpointDiagnostic: endpointDiagnostic,
      );
    } finally {
      _clearIncomingTransaction(owner: ackCompleter);
    }
  }

  /// Scanned side: the scanner confirmed it persisted its own end. Safe to
  /// commit our side now (see acceptRequest).
  void handlePairingAck(Map<String, dynamic> payload) {
    if (!isExpectedPairingAck(
      transactionId: payload['transactionId'],
      peerId: payload['peerId'],
      peerPublicKey: payload['publicKey'],
      expectedTransactionId: _pendingScannerInfo?['transactionId'] as String?,
      expectedPeerId: _expectedAckPeerId,
      expectedPeerPublicKey: _expectedAckPeerPublicKey,
    )) {
      _logPairingFailure(
        stage: 'ack-validation',
        reason: 'transaction-or-identity-mismatch',
      );
      return;
    }
    if (_pairAckCompleter != null && !_pairAckCompleter!.isCompleted) {
      _pairAckCompleter!.complete(true);
    }
  }

  void handleSocketDisconnected(SocketManager socketManager) {
    final completer = _pairAckCompleter;
    if (!identical(_pairAckSocket, socketManager) ||
        completer == null ||
        completer.isCompleted) {
      return;
    }
    state = const PairingState(errorCode: PairingErrorCode.ackTimeout);
    completer.complete(false);
  }

  /// Called by the UI when the *scanned* device user rejects the request.
  Future<void> rejectRequest({required SocketManager socketManager}) async {
    final requestGeneration = _incomingRequestGeneration;
    final pendingRequest = _pendingScannerInfo;
    var rejected = false;
    var ownsRequest = false;
    try {
      rejected = await socketManager.sendMessage(
        MessageTypes.pairingReject,
        {},
      );
    } finally {
      ownsRequest =
          requestGeneration == _incomingRequestGeneration &&
          identical(_pendingScannerInfo, pendingRequest);
      if (ownsRequest) {
        _clearIncomingTransaction();
      }
    }
    if (!ownsRequest) return;
    if (!rejected) {
      _logPairingFailure(stage: 'reject-write', reason: 'socket-write-failed');
    }
    state = rejected
        ? const PairingState()
        : const PairingState(errorCode: PairingErrorCode.handshakeFailed);
  }

  /// Reset to idle (e.g. dialog dismissed without action).
  void reset() {
    _incomingRequestGeneration++;
    _ref
        .read(connectionFacadeProvider.notifier)
        .invalidateNormalConnectionWork();
    state = const PairingState();
    _clearOutgoingTransaction();
    _clearIncomingTransaction();
    _cleanupSocket();
  }

  // --------------------------------------------------------------------

  Future<void> _cleanupSocket({SocketManager? owner}) async {
    final socket = owner ?? _handshakeSocket;
    try {
      await socket?.disconnect();
    } catch (_) {}
    if (!identical(_handshakeSocket, socket)) return;
    _handshakeSocket = null;
    _handshakeKey = null;
    _acceptPayload = null;
    _acceptRemoteAddress = null;
  }

  bool _isMatchingTransaction(Map<String, dynamic>? payload) =>
      payload?['transactionId'] == _transactionId;

  bool _ownsOutgoingTransaction(
    SocketManager socket,
    Completer<bool> completer,
  ) =>
      identical(_handshakeSocket, socket) &&
      identical(_acceptCompleter, completer);

  bool _isSupportedRole(Object? role) => role == 'main' || role == 'source';

  void _clearOutgoingTransaction({Completer<bool>? owner}) {
    if (owner != null && !identical(_acceptCompleter, owner)) return;
    final completer = _acceptCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    _acceptCompleter = null;
    _transactionId = null;
    _expectedPeerId = null;
    _expectedPeerPublicKey = null;
    _acceptPayload = null;
    _acceptRemoteAddress = null;
  }

  void _clearIncomingTransaction({
    Completer<bool>? owner,
    bool clearPendingInfo = true,
  }) {
    if (owner != null && !identical(_pairAckCompleter, owner)) return;
    final completer = _pairAckCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    _pairAckCompleter = null;
    _pairAckSocket = null;
    if (clearPendingInfo) _pendingScannerInfo = null;
    _expectedAckPeerId = null;
    _expectedAckPeerPublicKey = null;
  }

  Future<PairingEndpointSelection> _selectEndpoint({
    required PairingEndpointStage stage,
    required Object? claimedIp,
    required String? liveIp,
    required String? fallbackIp,
    required int port,
  }) async {
    final localAddresses = await _getLocalAddresses();
    if (localAddresses == null || localAddresses.isEmpty) {
      return PairingEndpointSelection(
        diagnostic: PairingEndpointDiagnostic(
          stage: stage,
          issue: PairingEndpointIssue.localInventoryUnavailable,
        ),
      );
    }
    return selectPairingEndpoint(
      stage: stage,
      claimedIp: claimedIp,
      liveIp: liveIp,
      fallbackIp: fallbackIp,
      port: port,
      localIps: localAddresses,
    );
  }

  void _logEndpointDiagnostic(PairingEndpointDiagnostic? diagnostic) {
    if (diagnostic == null) return;
    _logger.w(
      'Pairing endpoint diagnostic: stage=${diagnostic.stage.name}, '
      'issue=${diagnostic.issue.name}',
    );
  }

  void _logPairingFailure({
    required String stage,
    required String reason,
    Object? error,
  }) {
    final errorType = error == null ? '' : ', errorType=${error.runtimeType}';
    _logger.w('Pairing failure: stage=$stage, reason=$reason$errorType');
  }

  @override
  void dispose() {
    _incomingRequestGeneration++;
    _clearOutgoingTransaction();
    _clearIncomingTransaction();
    _cleanupSocket();
    super.dispose();
  }
}

Future<({String id, String publicKey})> _readLocalIdentity() async => (
  id: await KeyStore.getSelfId() ?? '',
  publicKey: await KeyStore.ensureDeviceKeyPair(),
);
