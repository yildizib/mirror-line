import 'package:mirrorline/core/data/models/peer.dart';

/// Runtime states used at the facade boundary to isolate pairing from normal
/// connection and discovery work.
enum PairingRuntimeState { unpaired, pairingPending, pairingComplete, paired }

PairingRuntimeState resolvePairingRuntimeState({
  required Peer? peer,
  required bool isPairingPending,
  required bool isPairingComplete,
}) {
  if (isPairingPending) return PairingRuntimeState.pairingPending;
  if (isPairingComplete) return PairingRuntimeState.pairingComplete;
  if (peer?.publicKey.isNotEmpty == true) return PairingRuntimeState.paired;
  return PairingRuntimeState.unpaired;
}
