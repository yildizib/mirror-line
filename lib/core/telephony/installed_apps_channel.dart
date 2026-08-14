import 'package:flutter/services.dart';

class InstalledApp {
  final String packageName;
  final String appName;

  InstalledApp({required this.packageName, required this.appName});
}

/// Reuses the existing single "io.github.yildizib.mirrorlink/telephony" channel
/// (see TelephonyChannel) rather than opening a second one -- the native
/// side already routes everything through one MirrorLineChannel singleton.
class InstalledAppsChannel {
  static const MethodChannel _channel = MethodChannel(
    'io.github.yildizib.mirrorlink/telephony',
  );

  static Future<List<InstalledApp>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (result == null) return [];
      return result
          .map((entry) => entry as Map<dynamic, dynamic>)
          .map(
            (entry) => InstalledApp(
              packageName: entry['packageName'] as String? ?? '',
              appName: entry['appName'] as String? ?? '',
            ),
          )
          .where((app) => app.packageName.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      return await _channel.invokeMethod<Uint8List>('getAppIcon', {
        'packageName': packageName,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
