// CallFacade/SmsFacade/NotificationFacade all touch AppDatabase (via their
// own DAOs) on construction -- same path_provider fake as
// notification_facade_test.dart / known_network_dao_test.dart.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/settings/diagnostics_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_diagnostics_facade_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // appL10n(ref) reads localeProvider, which also persists via
    // SharedPreferences -- same reasoning as notification_facade_test.dart.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  /// [deliver] controls whether the fake sendOrQueue reports immediate
  /// delivery (true) or queued (false), for both delivered/queued test
  /// cases below.
  ProviderContainer buildContainer(
    List<MapEntry<String, Map<String, dynamic>>> sent, {
    bool deliver = true,
  }) {
    Future<bool> sendOrQueue(String type, Map<String, dynamic> payload) async {
      sent.add(MapEntry(type, payload));
      return deliver;
    }

    Future<void> notify({
      required int id,
      required String title,
      required String body,
      dynamic payload,
    }) async {}

    final container = ProviderContainer(
      overrides: [
        callFacadeProvider.overrideWith(
          (ref) => CallFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
            sendOrQueue: sendOrQueue,
            notify: notify,
          ),
        ),
        smsFacadeProvider.overrideWith(
          (ref) => SmsFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
            sendOrQueue: sendOrQueue,
            notify: notify,
          ),
        ),
        notificationFacadeProvider.overrideWith(
          (ref) => NotificationFacade(
            ref: ref,
            logger: Logger(),
            sendOrQueue: sendOrQueue,
            notify: notify,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Each of the three facades' constructors kicks off a fire-and-forget
  /// initial load; awaiting them explicitly (idempotent) makes the test
  /// deterministic instead of racing the container's disposal in tearDown.
  Future<void> settleFacades(ProviderContainer container) async {
    await container.read(callFacadeProvider.notifier).load();
    await container.read(smsFacadeProvider.notifier).load();
    await container.read(notificationFacadeProvider.notifier).load();
  }

  test(
    'runTests sends one call, one SMS and one notification, in order',
    () async {
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      final container = buildContainer(sent);
      await settleFacades(container);

      await container.read(diagnosticsFacadeProvider.notifier).runTests();

      expect(sent.map((e) => e.key).toList(), [
        'call_incoming',
        'sms_incoming',
        'notification_mirrored',
      ]);
    },
  );

  test(
    'runTests records one entry per type, newest first, marked delivered',
    () async {
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      final container = buildContainer(sent, deliver: true);
      await settleFacades(container);

      await container.read(diagnosticsFacadeProvider.notifier).runTests();

      final records = container.read(diagnosticsFacadeProvider);
      expect(records, hasLength(3));
      expect(records.every((r) => r.delivered), isTrue);
      // Newest first: the last-sent type (notification) is at index 0.
      expect(records[0].type, TestEventType.notification);
      expect(records[1].type, TestEventType.sms);
      expect(records[2].type, TestEventType.call);
    },
  );

  test(
    'runTests marks records as queued (not delivered) when disconnected',
    () async {
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      final container = buildContainer(sent, deliver: false);
      await settleFacades(container);

      await container.read(diagnosticsFacadeProvider.notifier).runTests();

      final records = container.read(diagnosticsFacadeProvider);
      expect(records, hasLength(3));
      expect(records.every((r) => !r.delivered), isTrue);
    },
  );
}
