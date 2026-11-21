import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/features/pairing/domain/peer.dart';
import 'package:mirrorline/features/calls/facade/call_facade.dart';
import 'package:mirrorline/features/sync/facade/sync_facade.dart';
import 'package:mirrorline/features/notifications/facade/notification_facade.dart';
import 'package:mirrorline/features/pairing/facade/peer_facade.dart';
import 'package:mirrorline/features/sms/facade/sms_facade.dart';
import 'package:mirrorline/features/settings/facade/settings_gateways.dart';
import 'package:mirrorline/features/settings/facade/settings_platform_facade.dart';

export 'package:mirrorline/features/settings/facade/settings_platform_facade.dart'
    show SettingsNativeOperations;
export 'package:mirrorline/features/pairing/facade/peer_facade.dart'
    show pairedPeersProvider, peerFacadeProvider;
export 'package:mirrorline/features/settings/facade/diagnostics_facade.dart'
    show TestEventType, TestRunRecord, diagnosticsFacadeProvider;
export 'package:mirrorline/features/settings/facade/settings_gateways.dart';
export 'package:mirrorline/features/settings/facade/watched_apps_facade.dart'
    show watchedAppsProvider;
export 'package:mirrorline/features/sync/facade/sync_facade.dart'
    show syncConnectingProvider, syncFacadeProvider;

final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(
    ref,
    native: ref.read(settingsPlatformFacadeProvider),
  );
});

/// UI Service for SettingsScreen (issue #39's F4): orchestrates the
/// facade calls each action chains together, so the screen itself only
/// ever calls one thing per user action instead of sequencing facades
/// inline. Pure extraction, no behavior change.
class SettingsController {
  final Ref _ref;
  final SettingsNativeOperations _native;
  final SettingsIdentityGateway _identity;
  final PermissionGateway _permissions;

  SettingsController(
    this._ref, {
    SettingsNativeOperations? native,
    SettingsIdentityGateway? identity,
    PermissionGateway? permissions,
  }) : _native = native ?? const SettingsPlatformFacade(),
       _identity = identity ?? const KeyStoreSettingsIdentityGateway(),
       _permissions = permissions ?? const SystemPermissionGateway();

  Future<bool> isBatteryOptimizationIgnored() =>
      _permissions.isBatteryOptimizationIgnored();

  Future<bool> requestIgnoreBatteryOptimizations() =>
      _permissions.requestIgnoreBatteryOptimizations();

  Future<bool> openAppInfoSettings() => _permissions.openAppInfoSettings();

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
    await _ref.read(syncFacadeProvider.notifier).refresh();
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
    await _ref.read(syncFacadeProvider.notifier).stopAll();
    await _ref.read(syncFacadeProvider.notifier).clearQueue();
    await _ref.read(callFacadeProvider.notifier).removeAll();
    await _ref.read(smsFacadeProvider.notifier).removeAll();
    await _ref.read(notificationFacadeProvider.notifier).removeAll();
    await _ref.read(peerFacadeProvider.notifier).reset();
    await _identity.clearAll();
    _ref.invalidate(pairedPeersProvider);
  }
}
