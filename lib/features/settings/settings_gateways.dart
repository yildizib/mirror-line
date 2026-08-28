import 'dart:typed_data';

import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/services/permission_service.dart';
import 'package:mirrorline/core/telephony/installed_apps_channel.dart';

abstract interface class DeviceIdentityGateway {
  Future<String?> getDeviceName();
  Future<String?> getPublicKey();
}

class KeyStoreDeviceIdentityGateway implements DeviceIdentityGateway {
  const KeyStoreDeviceIdentityGateway();

  @override
  Future<String?> getDeviceName() => KeyStore.getSelfDeviceName();

  @override
  Future<String?> getPublicKey() => KeyStore.getDevicePublicKey();
}

abstract interface class PermissionGateway {
  Future<bool> requestNotifications();
  Future<bool> isBatteryOptimizationIgnored();
  Future<bool> requestIgnoreBatteryOptimizations();
  Future<bool> openAppInfoSettings();
}

class SystemPermissionGateway implements PermissionGateway {
  const SystemPermissionGateway();

  @override
  Future<bool> requestNotifications() =>
      PermissionService.requestNotifications();

  @override
  Future<bool> isBatteryOptimizationIgnored() =>
      PermissionService.isBatteryOptimizationIgnored();

  @override
  Future<bool> requestIgnoreBatteryOptimizations() =>
      PermissionService.requestIgnoreBatteryOptimizations();

  @override
  Future<bool> openAppInfoSettings() => PermissionService.openAppInfoSettings();
}

abstract interface class InstalledAppsGateway {
  Future<List<InstalledApp>> getInstalledApps();
  Future<Uint8List?> getAppIcon(String packageName);
}

class PlatformInstalledAppsGateway implements InstalledAppsGateway {
  const PlatformInstalledAppsGateway();

  @override
  Future<List<InstalledApp>> getInstalledApps() =>
      InstalledAppsChannel.getInstalledApps();

  @override
  Future<Uint8List?> getAppIcon(String packageName) =>
      InstalledAppsChannel.getAppIcon(packageName);
}

abstract interface class SettingsIdentityGateway {
  Future<void> clearAll();
}

class KeyStoreSettingsIdentityGateway implements SettingsIdentityGateway {
  const KeyStoreSettingsIdentityGateway();

  @override
  Future<void> clearAll() => KeyStore.clearAll();
}

// Keeps the UI-facing types independent from concrete platform services.
typedef SettingsPeer = Peer;
