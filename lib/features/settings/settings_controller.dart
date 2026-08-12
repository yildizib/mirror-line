import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref);
});

/// UI Service for SettingsScreen (issue #39's F4): orchestrates the two
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

  /// Order matters: stop networking before clearing peer/key state, same
  /// as the inline code this replaces -- resetting first could let a
  /// stray in-flight connect attempt race the peer record being wiped.
  Future<void> resetDevice() async {
    await _ref.read(connectionFacadeProvider.notifier).stopAll();
    await _ref.read(peerFacadeProvider.notifier).reset();
    _ref.invalidate(pairedPeersProvider);
  }
}
