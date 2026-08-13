import 'package:flutter/services.dart';

class TelephonyChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.thinksolve.mirrorline/telephony',
  );

  static Future<void> startListening() async {
    try {
      await _channel.invokeMethod('startListening');
    } on MissingPluginException {
      // Native side not implemented yet; ignore on non-Android or in tests.
    } on PlatformException catch (e) {
      throw Exception('Failed to start telephony listener: ${e.message}');
    }
  }

  static Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      throw Exception('Failed to stop telephony listener: ${e.message}');
    }
  }

  static Future<bool> rejectCall() async {
    try {
      final result = await _channel.invokeMethod<bool>('rejectCall');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw Exception('Failed to reject call: ${e.message}');
    }
  }

  static Future<void> sendSms(String address, String body) async {
    try {
      await _channel.invokeMethod('sendSms', {
        'address': address,
        'body': body,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      throw Exception('Failed to send SMS: ${e.message}');
    }
  }

  static Future<void> startService() async {
    try {
      await _channel.invokeMethod('startService');
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      throw Exception('Failed to start service: ${e.message}');
    }
  }

  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      throw Exception('Failed to stop telephony listener: ${e.message}');
    }
  }

  static Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isNotificationListenerEnabled',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Whether this device's manufacturer has a known OEM autostart /
  /// background-activity management screen (Xiaomi, Huawei, OPPO, Vivo,
  /// Samsung, OnePlus...). Used to decide whether to show OEM-specific
  /// wording in Settings, versus a generic "App info" fallback.
  static Future<bool> hasKnownAutoStartSettings() async {
    try {
      return await _channel.invokeMethod<bool>('hasKnownAutoStartSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the OEM's autostart/background-activity manager if known for
  /// this device, else falls back to the app's own "App info" screen.
  static Future<void> openAutoStartSettings() async {
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Whether this device's manufacturer has a *separate* known battery-saver
  /// restriction screen on top of stock Android's Doze whitelist and the
  /// OEM autostart manager above (currently MIUI/HyperOS's per-app
  /// "battery saver" list -- not covered by either of those).
  static Future<bool> hasKnownBatterySaverSettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'hasKnownBatterySaverSettings',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the OEM's separate battery-saver screen if known for this
  /// device, else falls back to the app's own "App info" screen.
  static Future<void> openBatterySaverSettings() async {
    try {
      await _channel.invokeMethod('openBatterySaverSettings');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Best-effort local contact lookup on *this* device. Used as a fallback
  /// when the Source device's contact resolution came up empty -- the two
  /// phones' address books aren't guaranteed to be identical, so trying
  /// both sides gives a name a better chance of being found. Returns null
  /// if READ_CONTACTS isn't granted here or nothing matches.
  static Future<String?> resolveContactName(String number) async {
    try {
      return await _channel.invokeMethod<String>('resolveContactName', {
        'number': number,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Returns the active network's IPv4 address from the native side.
  /// Returns null when unavailable (e.g. non-Android platforms).
  static Future<String?> getLocalIp() async {
    try {
      return await _channel.invokeMethod<String>('getLocalIp');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static void setEventHandler(
    void Function(String type, Map<dynamic, dynamic> data) handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCall':
        case 'onSms':
        case 'onNotification':
        case 'onNotificationRemoved':
        case 'onNetworkChanged':
          handler(call.method, (call.arguments as Map? ?? {}));
          return null;
        default:
          return null;
      }
    });
  }
}
