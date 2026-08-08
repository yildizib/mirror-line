import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final List<Permission> _permissions = [
    Permission.phone,
    Permission.sms,
    Permission.contacts,
    Permission.notification,
  ];

  static Future<bool> requestAll() async {
    final statuses = await _permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  static Future<bool> requestNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> areAllGranted() async {
    for (final permission in _permissions) {
      if (!await permission.isGranted) return false;
    }
    return true;
  }

  static Future<bool> isBatteryOptimizationIgnored() =>
      Permission.ignoreBatteryOptimizations.isGranted;

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (await isBatteryOptimizationIgnored()) return true;
    return await Permission.ignoreBatteryOptimizations.request().isGranted;
  }

  /// Opens this app's system "App info" screen so the user can turn off
  /// Android's "Remove permissions if app isn't used" (unused-app
  /// hibernation, Android 11+; shown as "Uygulama kullanılmıyorsa..." on
  /// Xiaomi HyperOS). There's no programmatic toggle for this -- only a
  /// deep link to the screen it lives on. If left on, Android can silently
  /// revoke this app's SMS/phone permissions and freeze its background
  /// service after a few months without the app being opened directly,
  /// breaking mirroring even though the devices are still paired.
  static Future<bool> openAppInfoSettings() => openAppSettings();
}
