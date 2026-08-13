import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref);
});

/// UI Service for SettingsScreen (issue #39's F4): orchestrates the
/// facade calls each action chains together, so the screen itself only
/// ever calls one thing per user action instead of sequencing facades
/// inline. Pure extraction, no behavior change.
class SettingsController {
  final Ref _ref;

  SettingsController(this._ref);

  Future<void> deletePeer(Peer peer) async {
    await _ref.read(peerFacadeProvider.notifier).deletePeer(peer);
    _ref.invalidate(pairedPeersProvider);
    await _ref.read(connectionFacadeProvider.notifier).refresh();
  }

  /// Full device reset: a real fresh start, not just unpair. Stops
  /// networking and clears the offline queue, wipes all call / SMS /
  /// notification history, drops the peer record, and finally clears
  /// this device's own Ed25519 keypair + self identity (KeyStore.clearAll)
  /// so the next pairing generates a brand new QR with a new keypair.
  ///
  /// Order matters: stop networking and clear the queue before wiping
  /// state, same reasoning as the old inline code -- resetting first
  /// could let a stray in-flight connect attempt race the peer record
  /// being wiped.
  Future<void> resetDevice() async {
    await _ref.read(connectionFacadeProvider.notifier).stopAll();
    await _ref.read(connectionFacadeProvider.notifier).clearQueue();
    await _ref.read(callFacadeProvider.notifier).removeAll();
    await _ref.read(smsFacadeProvider.notifier).removeAll();
    await _ref.read(notificationFacadeProvider.notifier).removeAll();
    await _ref.read(peerFacadeProvider.notifier).reset();
    await KeyStore.clearAll();
    _ref.invalidate(pairedPeersProvider);
  }
}
