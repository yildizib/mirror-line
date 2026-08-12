import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/features/pairing/peer_provider.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

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

final pairingProvider = StateNotifierProvider<PairingNotifier, PairingState>((
  ref,
) {
  return PairingNotifier(ref);
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
class PairingNotifier extends StateNotifier<PairingState> {
  final Logger _logger = Logger();
  final Ref _ref;

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

  /// Scanned side: resolves once the scanner's pairingAck arrives (or times
  /// out). Persisting the paired peer (applyPairedPeer) is gated on this so
  /// a lost pairingAccept can't leave the scanned device believing it's
  /// paired while the scanner never actually completed its own side --
  /// same reasoning as SocketManager's authOk/authAck two-step commit.
  Completer<bool>? _pairAckCompleter;

  /// Stashed scanner info on the *scanned* side (set by handleIncomingRequest).
  Map<String, dynamic>? _pendingScannerInfo;

  PairingNotifier(this._ref) : super(const PairingState());

  /// Pending scanner info (for UI to pass to acceptRequest).
  Map<String, dynamic>? get pendingScannerInfo => _pendingScannerInfo;

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
    _handshakeKey = key;

    final verificationCode = PeerNotifier.generateVerificationCode(
      scannedKeyBase64,
      scannedId,
    );

    state = PairingState(
      isWaitingForAccept: true,
      remoteDeviceName: scannedDeviceName,
      remotePeerId: scannedId,
      verificationCode: verificationCode,
    );

    _handshakeSocket = SocketManager(
      onMessage: _handleHandshakeMessage,
      onConnected: () {
        _logger.i('Handshake socket connected to $scannedIp:$scannedPort');
      },
      onDisconnected: () {
        _logger.w('Handshake socket disconnected.');
        if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
          _acceptCompleter!.complete(false);
        }
      },
    );

    try {
      final ok = await _handshakeSocket!.connect(scannedIp, scannedPort, key);
      if (!ok) {
        state = const PairingState(
          errorCode: PairingErrorCode.connectionFailed,
        );
        await _cleanupSocket();
        return;
      }

      await _handshakeSocket!.sendMessage(MessageTypes.pairingRequest, {
        'deviceName': myDeviceName,
        'peerId': myPeerId,
        'role': myRole,
        'publicKey': myPublicKey,
        'ip': myIp,
      });

      _acceptCompleter = Completer<bool>();
      final accepted = await _acceptCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );

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
        final peerIp = (accept?['ip'] as String?)?.isNotEmpty == true
            ? accept!['ip'] as String
            : scannedIp;
        final peerDeviceName =
            (accept?['deviceName'] as String?)?.isNotEmpty == true
            ? accept!['deviceName'] as String
            : scannedDeviceName;
        await _ref
            .read(peerProvider.notifier)
            .createPeerFromQr(
              id: scannedId,
              ip: peerIp,
              port: scannedPort,
              keyBase64: scannedKeyBase64,
              role: myRole,
              deviceName: peerDeviceName,
              publicKey: scannedPublicKey,
            );
        // Tell the scanned side we actually persisted our end -- see
        // pairingAck's doc comment in message_protocol.dart. Sent on the
        // same handshake socket before it's torn down below.
        await _handshakeSocket?.sendMessage(MessageTypes.pairingAck, {});
      } else {
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: PairingErrorCode.rejectedOrTimedOut,
        );
      }
    } catch (e) {
      _logger.e('Pairing sendRequest failed: $e');
      state = PairingState(
        errorCode: PairingErrorCode.handshakeFailed,
        errorDetail: '$e',
      );
    } finally {
      await _cleanupSocket();
    }
  }

  void _handleHandshakeMessage(MirrorMessage message) async {
    final key = _handshakeKey;
    if (key == null) return;

    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) return;

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (_) {
      payload = null;
    }

    switch (message.type) {
      case MessageTypes.pairingAccept:
        _logger.i('Pairing accepted by remote.');
        _acceptPayload = payload;
        state = state.copyWith(isWaitingForAccept: false);
        if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
          _acceptCompleter!.complete(true);
        }
        break;

      case MessageTypes.pairingReject:
        _logger.i('Pairing rejected by remote.');
        state = state.copyWith(
          isWaitingForAccept: false,
          errorCode: PairingErrorCode.rejected,
        );
        if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
          _acceptCompleter!.complete(false);
        }
        break;
    }
  }

  // --------------------------------------------------------------------
  // Scanned side  (called from ConnectionFacade._handleIncomingMessage)
  // --------------------------------------------------------------------

  /// Called when a `pairingRequest` message arrives on the *scanned* device.
  /// Updates state so the UI can show a confirmation dialog.
  void handleIncomingRequest(Map<String, dynamic> payload) {
    // Left null (not defaulted here) so the UI's own
    // `remoteDeviceName ?? l.pairingUnknownDevice` fallback -- localized to
    // *this* device's language -- is what actually renders, instead of a
    // fixed-language placeholder baked in before the widget ever sees it.
    final deviceName = payload['deviceName'] as String?;
    final peerId = payload['peerId'] as String? ?? '';
    final publicKey = payload['publicKey'] as String? ?? '';
    final scannerIp = payload['ip'] as String?;

    final peer = _ref.read(peerProvider);
    final verificationCode = peer?.verificationCode ?? '';

    state = PairingState(
      isShowingRequest: true,
      remoteDeviceName: deviceName,
      remotePeerId: peerId,
      verificationCode: verificationCode,
    );
    _logger.i(
      'Incoming pairing request from $deviceName ($peerId, pubKey=${publicKey.substring(0, publicKey.length > 8 ? 8 : publicKey.length)}..., ip=$scannerIp)',
    );

    // Stash the scanner's info for later use in acceptRequest.
    _pendingScannerInfo = {
      'deviceName': deviceName,
      'peerId': peerId,
      'role': payload['role'] as String? ?? 'main',
      'publicKey': publicKey,
      'ip': scannerIp,
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
    final myPeer = _ref.read(peerProvider);
    final myPublicKey = await KeyStore.ensureDeviceKeyPair();

    await socketManager.sendMessage(MessageTypes.pairingAccept, {
      // Sent to the other device as identity data -- locale-neutral
      // fallback, same reasoning as peer_provider.dart's _getDeviceName().
      'deviceName': myPeer?.deviceName ?? 'Unknown Device',
      'peerId': myPeer?.id ?? '',
      'publicKey': myPublicKey,
      'role': myPeer?.role ?? 'main',
      'ip': myIp,
    });

    state = state.copyWith(isShowingRequest: false, isFinalizing: true);

    _pairAckCompleter = Completer<bool>();
    final acked = await _pairAckCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );

    if (!acked) {
      state = const PairingState(errorCode: PairingErrorCode.ackTimeout);
      _pendingScannerInfo = null;
      return;
    }

    // Persist the scanner's full identity (id, name, public key), and its
    // real IP. Prefer the IP the scanner itself claimed in its
    // pairingRequest (more reliable than the TCP remote address, which can
    // be wrong on NAT/VLAN setups) -- fall back to the TCP remote address
    // if the scanner didn't claim an IP.
    final scannerId = scannerInfo['peerId'] as String? ?? '';
    // Persisted identity data -- locale-neutral fallback, same reasoning as
    // peer_provider.dart's _getDeviceName().
    final scannerDeviceName =
        scannerInfo['deviceName'] as String? ?? 'Unknown Device';
    final scannerPublicKey = scannerInfo['publicKey'] as String? ?? '';
    final scannerClaimedIp = scannerInfo['ip'] as String?;
    final scannerIp = (scannerClaimedIp != null && scannerClaimedIp.isNotEmpty)
        ? scannerClaimedIp
        : socketManager.remoteAddress;
    if (scannerId.isNotEmpty && scannerPublicKey.isNotEmpty) {
      await _ref
          .read(peerProvider.notifier)
          .applyPairedPeer(
            id: scannerId,
            deviceName: scannerDeviceName,
            publicKey: scannerPublicKey,
            ip: scannerIp,
          );
    }

    state = const PairingState();
  }

  /// Scanned side: the scanner confirmed it persisted its own end. Safe to
  /// commit our side now (see acceptRequest).
  void handlePairingAck() {
    if (_pairAckCompleter != null && !_pairAckCompleter!.isCompleted) {
      _pairAckCompleter!.complete(true);
    }
  }

  /// Called by the UI when the *scanned* device user rejects the request.
  Future<void> rejectRequest({required SocketManager socketManager}) async {
    await socketManager.sendMessage(MessageTypes.pairingReject, {});
    state = const PairingState();
  }

  /// Reset to idle (e.g. dialog dismissed without action).
  void reset() {
    state = const PairingState();
    if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
      _acceptCompleter!.complete(false);
    }
    if (_pairAckCompleter != null && !_pairAckCompleter!.isCompleted) {
      _pairAckCompleter!.complete(false);
    }
    _pendingScannerInfo = null;
    _cleanupSocket();
  }

  // --------------------------------------------------------------------

  Future<void> _cleanupSocket() async {
    try {
      await _handshakeSocket?.disconnect();
    } catch (_) {}
    _handshakeSocket = null;
    _handshakeKey = null;
    _acceptPayload = null;
  }

  @override
  void dispose() {
    _cleanupSocket();
    super.dispose();
  }
}
