import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';

final roleSelectionControllerProvider = Provider<RoleSelectionController>((
  ref,
) {
  return RoleSelectionController(ref);
});

/// UI Service for RoleSelectionScreen (issue #39's F6): wraps the two
/// facade calls _selectRole() chains together. There's no
/// createPeerAndConnect() method to move -- the equivalent logic was
/// always inline in _selectRole(); this extracts just that facade-
/// orchestration part, leaving the battery-exemption dialog and
/// navigation in the screen.
class RoleSelectionController {
  final Ref _ref;

  RoleSelectionController(this._ref);

  Future<void> selectRole(String role) async {
    await _ref.read(peerFacadeProvider.notifier).createPeer(role);
    await _ref.read(connectionFacadeProvider.notifier).refresh();
  }
}
