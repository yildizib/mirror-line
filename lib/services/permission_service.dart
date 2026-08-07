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

  static Future<bool> areAllGranted() async {
    for (final permission in _permissions) {
      if (!await permission.isGranted) return false;
    }
    return true;
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (await Permission.ignoreBatteryOptimizations.isGranted) return true;
    return await Permission.ignoreBatteryOptimizations.request().isGranted;
  }
}
