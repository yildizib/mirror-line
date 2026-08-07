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

  static Future<void> rejectCall() async {
    try {
      await _channel.invokeMethod('rejectCall');
    } on MissingPluginException {
      // ignore
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

  static void setEventHandler(void Function(String type, Map<dynamic, dynamic> data) handler) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCall':
        case 'onSms':
          handler(call.method, (call.arguments as Map? ?? {}));
          break;
        default:
          break;
      }
    });
  }
}
