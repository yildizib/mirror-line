import 'dart:async';

import 'package:flutter/services.dart';

enum MirroringRole {
  main('main'),
  source('source'),
  unknown('');

  const MirroringRole(this.nativeValue);

  final String nativeValue;

  static MirroringRole fromNative(Object? value) => switch (value) {
    'main' => MirroringRole.main,
    'source' => MirroringRole.source,
    _ => MirroringRole.unknown,
  };
}

enum MirroringServiceOutcome {
  startRequested,
  stopped,
  ineligible,
  permissionsRequired,
  failed,
  unavailable;

  static MirroringServiceOutcome fromNative(Object? value) => switch (value) {
    'start_requested' => MirroringServiceOutcome.startRequested,
    'stopped' => MirroringServiceOutcome.stopped,
    'ineligible' => MirroringServiceOutcome.ineligible,
    'permissions_required' => MirroringServiceOutcome.permissionsRequired,
    'failed' => MirroringServiceOutcome.failed,
    _ => MirroringServiceOutcome.failed,
  };
}

class MirroringLifecycle {
  const MirroringLifecycle({
    required this.initialized,
    required this.enabled,
    required this.role,
    required this.paired,
    required this.permissionsGranted,
    required this.eligible,
    required this.networkMonitoringEligible,
  });

  factory MirroringLifecycle.fromMap(Map<Object?, Object?> map) {
    return MirroringLifecycle(
      initialized: map['initialized'] == true,
      enabled: map['enabled'] == true,
      role: MirroringRole.fromNative(map['role']),
      paired: map['paired'] == true,
      permissionsGranted: map['permissionsGranted'] == true,
      eligible: map['eligible'] == true,
      networkMonitoringEligible: map['networkMonitoringEligible'] == true,
    );
  }

  final bool initialized;
  final bool enabled;
  final MirroringRole role;
  final bool paired;
  final bool permissionsGranted;
  final bool eligible;
  final bool networkMonitoringEligible;
}

class MirroringServiceResult {
  const MirroringServiceResult({required this.outcome, this.error});

  const MirroringServiceResult.unavailable()
    : outcome = MirroringServiceOutcome.unavailable,
      error = null;

  factory MirroringServiceResult.fromMap(Map<Object?, Object?> map) {
    return MirroringServiceResult(
      outcome: MirroringServiceOutcome.fromNative(map['outcome']),
      error: map['error'] as String?,
    );
  }

  final MirroringServiceOutcome outcome;
  final String? error;
}

class TelephonyChannelException implements Exception {
  const TelephonyChannelException({
    required this.operation,
    required this.code,
    this.message,
    this.details,
  });

  factory TelephonyChannelException.fromPlatform(
    String operation,
    PlatformException exception,
  ) {
    return TelephonyChannelException(
      operation: operation,
      code: exception.code,
      message: exception.message,
      details: exception.details,
    );
  }

  final String operation;
  final String code;
  final String? message;
  final Object? details;

  @override
  String toString() =>
      'TelephonyChannelException($operation, $code, $message, $details)';
}

class TelephonyChannel {
  static const MethodChannel _channel = MethodChannel(
    'io.github.yildizib.mirrorline/telephony',
  );
  static int _eventHandlerGeneration = 0;
  static FutureOr<void> Function(String type, Map<dynamic, dynamic> data)?
  _eventHandler;

  static Future<MirroringServiceResult> startListening() =>
      _start('startListening');

  static Future<MirroringServiceResult> _start(String method) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(method);
      return MirroringServiceResult.fromMap(result ?? const {});
    } on MissingPluginException {
      return const MirroringServiceResult.unavailable();
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform(method, e);
    }
  }

  static Future<MirroringServiceResult> stopListening({
    bool enabled = false,
    MirroringRole role = MirroringRole.unknown,
    bool paired = false,
  }) => _stop('stopListening', enabled: enabled, role: role, paired: paired);

  static Future<MirroringServiceResult> _stop(
    String method, {
    required bool enabled,
    required MirroringRole role,
    required bool paired,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(method, {
        'enabled': enabled,
        'role': role.nativeValue,
        'paired': paired,
      });
      return MirroringServiceResult.fromMap(result ?? const {});
    } on MissingPluginException {
      return const MirroringServiceResult.unavailable();
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform(method, e);
    }
  }

  static Future<MirroringLifecycle?> syncMirroringEligibility({
    required bool enabled,
    required MirroringRole role,
    required bool paired,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'syncMirroringEligibility',
        {'enabled': enabled, 'role': role.nativeValue, 'paired': paired},
      );
      return result == null ? null : MirroringLifecycle.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform(
        'syncMirroringEligibility',
        e,
      );
    }
  }

  static Future<MirroringLifecycle?> getMirroringLifecycle() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getMirroringLifecycle',
      );
      return result == null ? null : MirroringLifecycle.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform('getMirroringLifecycle', e);
    }
  }

  static Future<void> nativeEventsReady() => _setNativeReadiness(true);

  /// Marks Dart unavailable and clears native's pending event queue.
  static Future<void> nativeEventsNotReady() => _setNativeReadiness(false);

  static Future<void> _setNativeReadiness(bool ready) async {
    final method = ready ? 'nativeEventsReady' : 'nativeEventsNotReady';
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Graceful on non-Android platforms and unit tests without a handler.
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform(method, e);
    }
  }

  static Future<bool> rejectCall() async {
    try {
      final result = await _channel.invokeMethod<bool>('rejectCall');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform('rejectCall', e);
    }
  }

  static Future<void> sendSms(
    String address,
    String body, {
    required String operationId,
  }) async {
    try {
      await _channel.invokeMethod('sendSms', {
        'address': address,
        'body': body,
        'operationId': operationId,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform('sendSms', e);
    }
  }

  /// Replays completed native SMS callbacks retained across process death.
  /// Each result is removed from Android only after [handler] completes.
  static Future<void> consumePendingSmsResults() async {
    try {
      final results = await _channel.invokeListMethod<Object?>(
        'fetchSmsResults',
      );
      final handler = _eventHandler;
      if (handler == null) return;
      for (final value in results ?? const <Object?>[]) {
        final result = value as Map?;
        final operationId = result?['operationId'] as String?;
        final kind = result?['kind'] as String?;
        if (operationId == null || (kind != 'sent' && kind != 'delivered')) {
          continue;
        }
        await _handleSmsResultEvent(
          kind == 'sent' ? 'onSmsSent' : 'onSmsDelivered',
          Map<dynamic, dynamic>.from(result!),
        );
      }
    } on MissingPluginException {
      // Graceful on non-Android platforms.
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform('fetchSmsResults', e);
    }
  }

  static Future<void> _handleSmsResultEvent(
    String type,
    Map<dynamic, dynamic> data,
  ) async {
    final operationId = data['operationId'] as String?;
    if (operationId == null) return;
    await _eventHandler?.call(type, data);
    final kind = type == 'onSmsSent' ? 'sent' : 'delivered';
    try {
      await _channel.invokeMethod<void>('ackSmsResult', {
        'operationId': operationId,
        'kind': kind,
      });
    } on MissingPluginException {
      // Graceful on non-Android platforms.
    } on PlatformException catch (e) {
      throw TelephonyChannelException.fromPlatform('ackSmsResult', e);
    }
  }

  static Future<MirroringServiceResult> startService() =>
      _start('startService');

  static Future<MirroringServiceResult> stopService({
    bool enabled = false,
    MirroringRole role = MirroringRole.unknown,
    bool paired = false,
  }) => _stop('stopService', enabled: enabled, role: role, paired: paired);

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

  static void Function() setEventHandler(
    FutureOr<void> Function(String type, Map<dynamic, dynamic> data) handler,
  ) {
    final generation = ++_eventHandlerGeneration;
    _eventHandler = handler;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCall':
        case 'onSms':
        case 'onNotification':
        case 'onNotificationRemoved':
        case 'onNetworkChanged':
          await handler(call.method, (call.arguments as Map? ?? {}));
          return null;
        case 'onSmsSent':
        case 'onSmsDelivered':
          await _handleSmsResultEvent(
            call.method,
            (call.arguments as Map? ?? {}),
          );
          return null;
        default:
          return null;
      }
    });
    return () {
      if (generation != _eventHandlerGeneration) return;
      _eventHandlerGeneration++;
      _eventHandler = null;
      _channel.setMethodCallHandler(null);
    };
  }
}
