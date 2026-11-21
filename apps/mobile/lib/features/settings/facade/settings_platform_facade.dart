import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';

final settingsPlatformFacadeProvider = Provider<SettingsNativeOperations>((
  ref,
) {
  return const SettingsPlatformFacade();
});

abstract interface class SettingsNativeOperations {
  Future<bool> hasKnownAutoStartSettings();
  Future<bool> hasKnownBatterySaverSettings();
  Future<void> openNotificationListenerSettings();
  Future<void> openAutoStartSettings();
  Future<void> openBatterySaverSettings();
}

/// Facade boundary around Settings-related native platform operations.
final class SettingsPlatformFacade implements SettingsNativeOperations {
  const SettingsPlatformFacade();

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
