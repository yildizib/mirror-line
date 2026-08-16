import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/home/home_feed_provider.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
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
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_home_feed_test',
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
        callFacadeProvider.overrideWith((ref) {
          return CallFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
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
        smsFacadeProvider.overrideWith((ref) {
          return SmsFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
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

  CallEvent makeCall(String id, DateTime ts) => CallEvent(
    id: id,
    direction: 'incoming',
    number: '+111',
    contactName: 'Alice',
    timestamp: ts,
    encrypted: '',
    status: 'missed',
    createdAt: ts,
  );

  SmsMessage makeSms(String id, DateTime ts) => SmsMessage(
    id: id,
    threadId: 't1',
    address: '+222',
    contactName: 'Bob',
    body: 'hi',
    encrypted: '',
    direction: 'incoming',
    status: 'received',
    timestamp: ts,
    createdAt: ts,
  );

  NotificationEvent makeNotif(String id, DateTime ts) => NotificationEvent(
    id: id,
    nativeId: id,
    sourcePeerId: NotificationEvent.localSourcePeerId,
    packageName: 'com.app',
    appName: 'App',
    title: 'Title',
    text: 'Body',
    encrypted: '',
    timestamp: ts,
    createdAt: ts,
  );

  test('loadInitial merges 3 sources by timestamp DESC', () async {
    final container = buildContainer();
    final callFacade = container.read(callFacadeProvider.notifier);
    final smsFacade = container.read(smsFacadeProvider.notifier);
    final notifFacade = container.read(notificationFacadeProvider.notifier);
    await callFacade.load();
    await smsFacade.load();
    await notifFacade.load();

    final now = DateTime.now();
    await callFacade.add(
      makeCall('c1', now.subtract(const Duration(hours: 1))),
    );
    await smsFacade.add(makeSms('s1', now.subtract(const Duration(hours: 2))));
    await notifFacade.add(
      makeNotif('n1', now.subtract(const Duration(hours: 3))),
    );

    final notifier = container.read(homeFeedPaginatedProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(homeFeedPaginatedProvider);

    expect(state.items.length, 3);
    expect(state.items[0].timestamp.isAfter(state.items[1].timestamp), isTrue);
    expect(state.items[1].timestamp.isAfter(state.items[2].timestamp), isTrue);
  });

  test('loadMore appends older items from all 3 sources', () async {
    final container = buildContainer();
    final callFacade = container.read(callFacadeProvider.notifier);
    final smsFacade = container.read(smsFacadeProvider.notifier);
    final notifFacade = container.read(notificationFacadeProvider.notifier);
    await callFacade.load();
    await smsFacade.load();
    await notifFacade.load();

    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      await callFacade.add(
        makeCall('c$i', now.subtract(Duration(hours: i + 1))),
      );
      await smsFacade.add(makeSms('s$i', now.subtract(Duration(hours: i + 2))));
      await notifFacade.add(
        makeNotif('n$i', now.subtract(Duration(hours: i + 3))),
      );
    }

    final notifier = container.read(homeFeedPaginatedProvider.notifier);
    await notifier.loadInitial();
    var state = container.read(homeFeedPaginatedProvider);
    final initialCount = state.items.length;
    expect(initialCount, lessThanOrEqualTo(25));

    await notifier.loadMore();
    state = container.read(homeFeedPaginatedProvider);
    expect(state.items.length, greaterThan(initialCount));
  });

  test('hasReachedEnd when all sources exhausted', () async {
    final container = buildContainer();
    final callFacade = container.read(callFacadeProvider.notifier);
    final smsFacade = container.read(smsFacadeProvider.notifier);
    final notifFacade = container.read(notificationFacadeProvider.notifier);
    await callFacade.load();
    await smsFacade.load();
    await notifFacade.load();

    final now = DateTime.now();
    await callFacade.add(
      makeCall('c1', now.subtract(const Duration(hours: 1))),
    );
    await smsFacade.add(makeSms('s1', now.subtract(const Duration(hours: 2))));
    await notifFacade.add(
      makeNotif('n1', now.subtract(const Duration(hours: 3))),
    );

    final notifier = container.read(homeFeedPaginatedProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(homeFeedPaginatedProvider);

    expect(state.hasReachedEnd, isTrue);
  });

  test('retains all 75 fetched records across home-feed pages', () async {
    final container = buildContainer();
    final callFacade = container.read(callFacadeProvider.notifier);
    final smsFacade = container.read(smsFacadeProvider.notifier);
    final notifFacade = container.read(notificationFacadeProvider.notifier);
    await callFacade.load();
    await smsFacade.load();
    await notifFacade.load();

    final now = DateTime.now();
    for (var i = 0; i < 25; i++) {
      await callFacade.add(makeCall('c$i', now.subtract(Duration(minutes: i))));
      await smsFacade.add(
        makeSms('s$i', now.subtract(Duration(minutes: i + 25))),
      );
      await notifFacade.add(
        makeNotif('n$i', now.subtract(Duration(minutes: i + 50))),
      );
    }

    final notifier = container.read(homeFeedPaginatedProvider.notifier);
    await notifier.loadInitial();
    await notifier.loadMore();
    await notifier.loadMore();
    await notifier.loadMore();
    final state = container.read(homeFeedPaginatedProvider);

    expect(state.items, hasLength(75));
    expect(state.items.map((item) => item.id).toSet(), hasLength(75));
    expect(state.hasReachedEnd, isTrue);
  });
}
