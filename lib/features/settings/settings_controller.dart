import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref);
});

abstract interface class SettingsNativeOperations {
  Future<bool> hasKnownAutoStartSettings();
  Future<bool> hasKnownBatterySaverSettings();
  Future<void> openNotificationListenerSettings();
  Future<void> openAutoStartSettings();
  Future<void> openBatterySaverSettings();
}

class _TelephonySettingsOperations implements SettingsNativeOperations {
  @override
  Future<bool> hasKnownAutoStartSettings() =>
      TelephonyChannel.hasKnownAutoStartSettings();

  @override
  Future<bool> hasKnownBatterySaverSettings() =>
      TelephonyChannel.hasKnownBatterySaverSettings();

  @override
  Future<void> openNotificationListenerSettings() =>
      TelephonyChannel.openNotificationListenerSettings();

  @override
  Future<void> openAutoStartSettings() =>
      TelephonyChannel.openAutoStartSettings();

  @override
  Future<void> openBatterySaverSettings() =>
      TelephonyChannel.openBatterySaverSettings();
}

/// UI Service for SettingsScreen (issue #39's F4): orchestrates the
/// facade calls each action chains together, so the screen itself only
/// ever calls one thing per user action instead of sequencing facades
/// inline. Pure extraction, no behavior change.
class SettingsController {
  final Ref _ref;
  final SettingsNativeOperations _native;

  SettingsController(this._ref, {SettingsNativeOperations? native})
    : _native = native ?? _TelephonySettingsOperations();

  Future<bool> hasKnownAutoStartSettings() =>
      _native.hasKnownAutoStartSettings();

  Future<bool> hasKnownBatterySaverSettings() =>
      _native.hasKnownBatterySaverSettings();

  Future<void> openNotificationListenerSettings() =>
      _native.openNotificationListenerSettings();

  Future<void> openAutoStartSettings() => _native.openAutoStartSettings();

  Future<void> openBatterySaverSettings() => _native.openBatterySaverSettings();

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
