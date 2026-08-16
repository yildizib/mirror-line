import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.github.yildizib.mirrorline/telephony');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    TelephonyChannel.setEventHandler((_, _) {})();
  });

  test('decodes lifecycle maps from sync and get', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(
        call.arguments,
        call.method == 'syncMirroringEligibility'
            ? {'enabled': true, 'role': 'source', 'paired': true}
            : null,
      );
      return {
        'initialized': true,
        'enabled': true,
        'role': 'source',
        'paired': true,
        'permissionsGranted': true,
        'eligible': true,
        'networkMonitoringEligible': true,
      };
    });

    final synced = await TelephonyChannel.syncMirroringEligibility(
      enabled: true,
      role: MirroringRole.source,
      paired: true,
    );
    final loaded = await TelephonyChannel.getMirroringLifecycle();

    for (final lifecycle in [synced, loaded]) {
      expect(lifecycle?.initialized, true);
      expect(lifecycle?.enabled, true);
      expect(lifecycle?.role, MirroringRole.source);
      expect(lifecycle?.paired, true);
      expect(lifecycle?.permissionsGranted, true);
      expect(lifecycle?.eligible, true);
      expect(lifecycle?.networkMonitoringEligible, true);
    }
  });

  test('decodes start and stop outcomes and forwards stop state', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'startListening'
          ? {'outcome': 'start_requested', 'error': null}
          : {'outcome': 'stopped', 'error': null};
    });

    final started = await TelephonyChannel.startListening();
    final stopped = await TelephonyChannel.stopService(
      enabled: false,
      role: MirroringRole.main,
      paired: false,
    );

    expect(started.outcome, MirroringServiceOutcome.startRequested);
    expect(stopped.outcome, MirroringServiceOutcome.stopped);
    expect(calls.last.method, 'stopService');
    expect(calls.last.arguments, {
      'enabled': false,
      'role': 'main',
      'paired': false,
    });
  });

  test('preserves PlatformException fields in typed failures', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'START_FAILED',
        message: 'service unavailable',
        details: {'attempt': 2},
      );
    });

    await expectLater(
      TelephonyChannel.startService(),
      throwsA(
        isA<TelephonyChannelException>()
            .having((e) => e.operation, 'operation', 'startService')
            .having((e) => e.code, 'code', 'START_FAILED')
            .having((e) => e.message, 'message', 'service unavailable')
            .having((e) => e.details, 'details', {'attempt': 2}),
      ),
    );
  });

  test('sends ready and queue-clearing not-ready lifecycle calls', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });

    await TelephonyChannel.nativeEventsReady();
    await TelephonyChannel.nativeEventsNotReady();

    expect(methods, ['nativeEventsReady', 'nativeEventsNotReady']);
  });

  test('sends the stable operation ID with an SMS submission', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sendSms');
      expect(call.arguments, {
        'address': '+905551112233',
        'body': 'hello',
        'operationId': 'message-123',
      });
      return null;
    });

    await TelephonyChannel.sendSms(
      '+905551112233',
      'hello',
      operationId: 'message-123',
    );
  });

  testWidgets('forwards SMS operation result events', (tester) async {
    final events = <(String, Map<dynamic, dynamic>)>[];
    TelephonyChannel.setEventHandler((type, data) => events.add((type, data)));

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSmsSent', {
          'operationId': 'message-123',
          'success': true,
        }),
      ),
      (_) {},
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onSmsDelivered', {
          'operationId': 'message-123',
          'success': false,
        }),
      ),
      (_) {},
    );

    expect(events.map((event) => event.$1), ['onSmsSent', 'onSmsDelivered']);
    expect(events[0].$2, {'operationId': 'message-123', 'success': true});
    expect(events[1].$2, {'operationId': 'message-123', 'success': false});
  });

  testWidgets('native response waits for async Dart event handling', (
    tester,
  ) async {
    final handlerDone = Completer<void>();
    var completed = false;
    TelephonyChannel.setEventHandler((type, data) async {
      expect(type, 'onCall');
      expect(data['state'], 'RINGING');
      await handlerDone.future;
      completed = true;
    });

    final response = Completer<ByteData?>();
    final dispatch = tester.binding.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onCall', {'state': 'RINGING'}),
          ),
          response.complete,
        );

    expect(response.isCompleted, false);
    handlerDone.complete();
    await dispatch;
    final envelope = await response.future;
    expect(const StandardMethodCodec().decodeEnvelope(envelope!), isNull);
    expect(completed, true);
  });

  testWidgets('event handler disposer clears only its own registration', (
    tester,
  ) async {
    var firstCalls = 0;
    var secondCalls = 0;
    final clearFirst = TelephonyChannel.setEventHandler((_, _) {
      firstCalls++;
    });
    final clearSecond = TelephonyChannel.setEventHandler((_, _) {
      secondCalls++;
    });

    clearFirst();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onCall', {'state': 'RINGING'}),
      ),
      (_) {},
    );
    expect(firstCalls, 0);
    expect(secondCalls, 1);

    clearSecond();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onCall', {'state': 'RINGING'}),
      ),
      (_) {},
    );
    expect(secondCalls, 1);
  });
}
