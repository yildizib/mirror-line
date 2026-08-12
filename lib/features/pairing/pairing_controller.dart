import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/pairing/pairing_facade.dart';

final pairingControllerProvider = Provider<PairingController>((ref) {
  return PairingController(ref);
});

/// UI Service for PairingScreen (issue #39's F5): orchestrates the
/// facade calls the accept/send flows each chain together. UI-only
/// concerns (SnackBar text, pairingErrorText, mounted checks, navigation)
/// stay in the screen. Pure extraction, no behavior change.
class PairingController {
  final Ref _ref;

  PairingController(this._ref);

  /// Returns false if there was no live socket to accept on (mirrors the
  /// old inline `socketManager != null` gate) -- the caller combines this
  /// with the facade's post-accept errorCode to know whether pairing
  /// actually succeeded.
  Future<bool> acceptPairingRequest() async {
    final socketManager = _ref
        .read(connectionFacadeProvider.notifier)
        .socketManager;
    if (socketManager == null) return false;

    final notifier = _ref.read(pairingFacadeProvider.notifier);
    final scannerInfo = notifier.pendingScannerInfo ?? {};
    final status = _ref.read(connectionStatusProvider);
    final myIp = status.localIp ?? '';
    await notifier.acceptRequest(
      socketManager: socketManager,
      scannerInfo: scannerInfo,
      myIp: myIp,
    );
    await _ref.read(connectionFacadeProvider.notifier).refresh();
    return true;
  }

  Future<void> sendPairingRequest({
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
    await _ref
        .read(pairingFacadeProvider.notifier)
        .sendRequest(
          scannedId: scannedId,
          scannedIp: scannedIp,
          scannedPort: scannedPort,
          scannedKeyBase64: scannedKeyBase64,
          scannedDeviceName: scannedDeviceName,
          scannedPublicKey: scannedPublicKey,
          myDeviceName: myDeviceName,
          myPeerId: myPeerId,
          myRole: myRole,
          myPublicKey: myPublicKey,
          myIp: myIp,
        );
    await _ref.read(connectionFacadeProvider.notifier).refresh();
  }
}
