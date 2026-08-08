import 'package:flutter/services.dart';

class TelephonyChannel {
  static const MethodChannel _channel = MethodChannel('com.thinksolve.mirrorline/telephony');

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
      return await _channel.invokeMethod<bool>('isNotificationListenerEnabled') ?? false;
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

  static void setEventHandler(void Function(String type, Map<dynamic, dynamic> data) handler) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCall':
        case 'onSms':
        case 'onNotification':
        case 'onNotificationRemoved':
          handler(call.method, (call.arguments as Map? ?? {}));
          return null;
        default:
          return null;
      }
    });
  }
}
