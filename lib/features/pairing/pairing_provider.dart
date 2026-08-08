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

/// Pairing state visible to the UI.
class PairingState {
  final bool isWaitingForAccept; // Scanner side: sent request, waiting reply
  final bool isShowingRequest; // Scanned side: incoming request, awaiting user
  final String? remoteDeviceName; // Other device's name
  final String? remotePeerId; // Other device's peer id
  final String? verificationCode; // 6-digit code shared via QR/key
  final String? errorMessage;

  const PairingState({
    this.isWaitingForAccept = false,
    this.isShowingRequest = false,
    this.remoteDeviceName,
    this.remotePeerId,
    this.verificationCode,
    this.errorMessage,
  });

  PairingState copyWith({
    bool? isWaitingForAccept,
    bool? isShowingRequest,
    String? remoteDeviceName,
    String? remotePeerId,
    String? verificationCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PairingState(
      isWaitingForAccept: isWaitingForAccept ?? this.isWaitingForAccept,
      isShowingRequest: isShowingRequest ?? this.isShowingRequest,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      remotePeerId: remotePeerId ?? this.remotePeerId,
      verificationCode: verificationCode ?? this.verificationCode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier(ref);
});

/// Coordinates the two-way QR pairing handshake.
///
/// Flow:
///   1. Scanner reads QR -> calls [sendRequest] with scanned info.
///   2. Scanner opens a temporary TCP connection to the scanned device
///      and sends `pairingRequest` with its own device name + peer id.
///   3. Scanned device receives `pairingRequest` via ConnectionNotifier,
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
  /// [scannedIp]/[scannedPort] come from the QR.  [scannedKeyBase64] is the
  /// shared AES key (also from the QR).  [myDeviceName] and [myPeerId] are
  /// this device's identity.
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
  }) async {
    final keyBytes = base64Decode(scannedKeyBase64);
    final key = SecretKey(keyBytes);
    _handshakeKey = key;

    final verificationCode =
        PeerNotifier.generateVerificationCode(scannedKeyBase64, scannedId);

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
        state = const PairingState(errorMessage: 'Bağlantı kurulamadı.');
        await _cleanupSocket();
        return;
      }

      await _handshakeSocket!.sendMessage(MessageTypes.pairingRequest, {
        'deviceName': myDeviceName,
        'peerId': myPeerId,
        'role': myRole,
        'publicKey': myPublicKey,
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
        // (so ConnectionNotifier knows whether to start as source or main).
        // `key` is the shared AES key from the QR.  `publicKey` is the
        // scanned device's Ed25519 public key for auth.
        await _ref.read(peerProvider.notifier).createPeerFromQr(
              id: scannedId,
              ip: scannedIp,
              port: scannedPort,
              keyBase64: scannedKeyBase64,
              role: myRole,
              deviceName: scannedDeviceName,
              publicKey: scannedPublicKey,
            );
      } else {
        state = state.copyWith(
          isWaitingForAccept: false,
          errorMessage: 'Eşleşme reddedildi veya zaman aşımına uğradı.',
        );
      }
    } catch (e) {
      _logger.e('Pairing sendRequest failed: $e');
      state = PairingState(errorMessage: 'Eşleşme hatası: $e');
    } finally {
      await _cleanupSocket();
    }
  }

  void _handleHandshakeMessage(MirrorMessage message) async {
    final key = _handshakeKey;
    if (key == null) return;

    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) return;

    switch (message.type) {
      case MessageTypes.pairingAccept:
        _logger.i('Pairing accepted by remote.');
        state = state.copyWith(isWaitingForAccept: false);
        if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
          _acceptCompleter!.complete(true);
        }
        break;

      case MessageTypes.pairingReject:
        _logger.i('Pairing rejected by remote.');
        state = state.copyWith(
          isWaitingForAccept: false,
          errorMessage: 'Eşleşme reddedildi.',
        );
        if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
          _acceptCompleter!.complete(false);
        }
        break;
    }
  }

  // --------------------------------------------------------------------
  // Scanned side  (called from ConnectionNotifier._handleIncomingMessage)
  // --------------------------------------------------------------------

  /// Called when a `pairingRequest` message arrives on the *scanned* device.
  /// Updates state so the UI can show a confirmation dialog.
  void handleIncomingRequest(Map<String, dynamic> payload) {
    final deviceName = payload['deviceName'] as String? ?? 'Bilinmeyen Cihaz';
    final peerId = payload['peerId'] as String? ?? '';
    final publicKey = payload['publicKey'] as String? ?? '';

    final peer = _ref.read(peerProvider);
    final verificationCode = peer?.verificationCode ?? '';

    state = PairingState(
      isShowingRequest: true,
      remoteDeviceName: deviceName,
      remotePeerId: peerId,
      verificationCode: verificationCode,
    );
    _logger.i('Incoming pairing request from $deviceName ($peerId, pubKey=${publicKey.substring(0, publicKey.length > 8 ? 8 : publicKey.length)}...)');

    // Stash the scanner's info for later use in acceptRequest.
    _pendingScannerInfo = {
      'deviceName': deviceName,
      'peerId': peerId,
      'role': payload['role'] as String? ?? 'main',
      'publicKey': publicKey,
    };
  }

  /// Called by the UI when the *scanned* device user confirms the request.
  ///
  /// [socketManager] is the live connection from ConnectionNotifier so we
  /// can reply on the same channel.  [scannerInfo] carries the scanner's
  /// identity to persist as our peer.
  Future<void> acceptRequest({
    required SocketManager socketManager,
    required Map<String, dynamic> scannerInfo,
  }) async {
    final myPeer = _ref.read(peerProvider);
    final myPublicKey = await KeyStore.ensureDeviceKeyPair();

    await socketManager.sendMessage(MessageTypes.pairingAccept, {
      'deviceName': myPeer?.deviceName ?? 'Bilinmeyen',
      'peerId': myPeer?.id ?? '',
      'publicKey': myPublicKey,
    });

    // Persist the scanner's full identity (id, name, public key), and its
    // real IP straight from the live TCP socket (more trustworthy than
    // anything it claims about itself). This makes `peer` consistently
    // represent the other device after pairing, on both sides, regardless
    // of who scanned whom.
    final scannerId = scannerInfo['peerId'] as String? ?? '';
    final scannerDeviceName = scannerInfo['deviceName'] as String? ?? 'Bilinmeyen Cihaz';
    final scannerPublicKey = scannerInfo['publicKey'] as String? ?? '';
    if (scannerId.isNotEmpty && scannerPublicKey.isNotEmpty) {
      await _ref.read(peerProvider.notifier).applyPairedPeer(
            id: scannerId,
            deviceName: scannerDeviceName,
            publicKey: scannerPublicKey,
            ip: socketManager.remoteAddress,
          );
    }

    state = const PairingState();
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
  }

  @override
  void dispose() {
    _cleanupSocket();
    super.dispose();
  }
}