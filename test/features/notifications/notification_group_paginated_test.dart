import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/notifications/notification_group_provider.dart';
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
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_notification_group_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        notificationFacadeProvider.overrideWith((ref) {
          return NotificationFacade(
            ref: ref,
            logger: Logger(),
            sendOrQueue: (type, payload) async => true,
            notify:
                ({
                  required int id,
                  required String title,
                  required String body,
                  NotificationPayload? payload,
                }) async {},
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  NotificationEvent makeEvent({
    required String id,
    required DateTime timestamp,
    String packageName = 'com.test.app',
    String appName = 'TestApp',
  }) {
    return NotificationEvent(
      id: id,
      nativeId: id,
      packageName: packageName,
      appName: appName,
      title: 'Title',
      text: 'Body',
      encrypted: '',
      timestamp: timestamp,
      createdAt: timestamp,
    );
  }

  test('loadInitial loads today+yesterday groups', () async {
    final container = buildContainer();
    final facade = container.read(notificationFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    await facade.add(
      makeEvent(
        id: 'today1',
        timestamp: now.subtract(const Duration(hours: 1)),
        packageName: 'com.app1',
        appName: 'App1',
      ),
    );
    await facade.add(
      makeEvent(
        id: 'today2',
        timestamp: now.subtract(const Duration(hours: 2)),
        packageName: 'com.app2',
        appName: 'App2',
      ),
    );
    await facade.add(
      makeEvent(
        id: 'old',
        timestamp: now.subtract(const Duration(days: 10)),
        packageName: 'com.app3',
        appName: 'App3',
      ),
    );

    final notifier = container.read(
      notificationGroupsPaginatedProvider.notifier,
    );
    await notifier.loadInitial();
    final state = container.read(notificationGroupsPaginatedProvider);

    expect(state.items.length, 2);
    expect(
      state.items.map((g) => g.key).toList(),
      containsAll(['com.app1', 'com.app2']),
    );
    expect(state.hasReachedEnd, isTrue);
  });

  test('loadMore appends older groups', () async {
    final container = buildContainer();
    final facade = container.read(notificationFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    for (var i = 0; i < 60; i++) {
      await facade.add(
        makeEvent(
          id: 'recent_$i',
          timestamp: yesterdayStart.add(Duration(minutes: i * 20)),
          packageName: 'com.recent$i',
          appName: 'Recent$i',
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      await facade.add(
        makeEvent(
          id: 'old_$i',
          timestamp: yesterdayStart.subtract(Duration(hours: i + 1)),
          packageName: 'com.old$i',
          appName: 'OldApp$i',
        ),
      );
    }

    final notifier = container.read(
      notificationGroupsPaginatedProvider.notifier,
    );
    await notifier.loadInitial();
    var state = container.read(notificationGroupsPaginatedProvider);
    final initialCount = state.items.length;
    expect(initialCount, lessThanOrEqualTo(25));

    await notifier.loadMore();
    state = container.read(notificationGroupsPaginatedProvider);
    expect(state.items.length, greaterThan(initialCount));
  });

  test('groups merge correctly on loadMore', () async {
    final container = buildContainer();
    final facade = container.read(notificationFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    await facade.add(
      makeEvent(
        id: 'recent_app1',
        timestamp: now.subtract(const Duration(hours: 1)),
        packageName: 'com.app1',
        appName: 'App1',
      ),
    );
    for (var i = 0; i < 30; i++) {
      await facade.add(
        makeEvent(
          id: 'filler_$i',
          timestamp: yesterdayStart.add(Duration(minutes: i * 30)),
          packageName: 'com.filler$i',
          appName: 'Filler$i',
        ),
      );
    }
    await facade.add(
      makeEvent(
        id: 'old_app1',
        timestamp: yesterdayStart.subtract(const Duration(days: 10)),
        packageName: 'com.app1',
        appName: 'App1',
      ),
    );

    final notifier = container.read(
      notificationGroupsPaginatedProvider.notifier,
    );
    await notifier.loadInitial();
    await notifier.loadMore();
    await notifier.loadMore();
    await notifier.loadMore();
    await notifier.loadMore();
    final state = container.read(notificationGroupsPaginatedProvider);

    final app1Group = state.items.where((g) => g.key == 'com.app1').first;
    expect(app1Group.events.length, 2);
  });
}
