// AppDatabase resolves its file path via path_provider and
// WatchedAppsNotifier persists via shared_preferences -- both need a
// platform implementation even in plain `flutter_test` unit tests, faked
// here the same way known_network_dao_test.dart fakes path_provider and
// database_migration_test.dart fakes sqflite via sqflite_common_ffi.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
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
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_notification_facade_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer buildContainer(
    List<MapEntry<String, Map<String, dynamic>>> sent, {
    List<int>? notifiedIds,
  }) {
    final container = ProviderContainer(
      overrides: [
        notificationFacadeProvider.overrideWith(
          (ref) => NotificationFacade(
            ref: ref,
            logger: Logger(),
            sendOrQueue: (type, payload) async {
              sent.add(MapEntry(type, payload));
              return true;
            },
            notify:
                ({required id, required title, required body, payload}) async {
                  notifiedIds?.add(id);
                },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('watched apps initialized is the constructor load future', () async {
    SharedPreferences.setMockInitialValues({
      'watched_packages_migrated': true,
      'watched_packages': ['com.example.chat'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(watchedAppsProvider.notifier);
    final initialized = notifier.initialized;

    expect(identical(initialized, notifier.initialized), isTrue);
    await initialized;

    expect(notifier.state.isInitialized, isTrue);
    expect(notifier.state.packages, {'com.example.chat'});
  });

  test('handleNativeEvent is a no-op when the package is unwatched', () async {
    final sent = <MapEntry<String, Map<String, dynamic>>>[];
    final container = buildContainer(sent);
    final facade = container.read(notificationFacadeProvider.notifier);
    final watchedApps = container.read(watchedAppsProvider.notifier);

    await Future.wait([facade.initialized, watchedApps.initialized]);

    await facade.handleNativeEvent(
      {
        'packageName': 'com.example.unwatched',
        'appName': 'Unwatched App',
        'title': 'Hi',
        'text': 'there',
        'id': 'native-1',
      },
      id: 'evt-1',
      now: DateTime.now(),
    );

    expect(facade.state, isEmpty);
    expect(sent, isEmpty);
  });

  test(
    'a native dismissal is ignored -- the stored event is kept (issue #59)',
    () async {
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      final container = buildContainer(sent);
      final facade = container.read(notificationFacadeProvider.notifier);
      await facade.initialized;

      // Seed directly via add() (bypasses the watched-package gate, which
      // is already covered by the test above) so this test only exercises
      // dismissal: native removal is now a no-op, the event must remain.
      await facade.add(
        NotificationEvent(
          id: 'evt-1',
          nativeId: 'native-1',
          sourcePeerId: NotificationEvent.localSourcePeerId,
          packageName: 'com.example.chat',
          appName: 'Chat',
          title: 'New message',
          text: 'Hello',
          encrypted: '',
          timestamp: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
      expect(facade.state, hasLength(1));

      await facade.handleNativeRemoval({
        'packageName': 'com.example.chat',
        'id': 'native-1',
      });

      // Event must still be present -- native removals no longer delete.
      expect(facade.state, hasLength(1));
      expect(
        sent.any((e) => e.key == 'notification_removed'),
        isFalse,
        reason: 'no notificationRemoved peer message should be queued',
      );
    },
  );

  test(
    'sendTestNotification sends regardless of watched-apps state and does not persist locally',
    () async {
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      final container = buildContainer(sent);
      final facade = container.read(notificationFacadeProvider.notifier);
      final watchedApps = container.read(watchedAppsProvider.notifier);
      await Future.wait([facade.initialized, watchedApps.initialized]);

      // No packages watched (default in tests) -- sendTestNotification
      // must not be gated by this, unlike handleNativeEvent.
      expect(watchedApps.isWatched('mirrorline.diagnostics.test'), isFalse);

      final delivered = await facade.sendTestNotification(
        appName: 'Test App',
        title: 'Test Title',
        text: 'Test body',
      );

      expect(delivered, isTrue);
      expect(
        facade.state,
        isEmpty,
        reason: 'sender does not get a local copy of its own test event',
      );
      final message = sent.singleWhere((e) => e.key == 'notification_mirrored');
      expect(message.value['packageName'], 'mirrorline.diagnostics.test');
      expect(message.value['appName'], 'Test App');
      expect(message.value['title'], 'Test Title');
      expect(message.value['text'], 'Test body');
    },
  );

  test('keeps peer notification identities distinct', () async {
    final sent = <MapEntry<String, Map<String, dynamic>>>[];
    final notifiedIds = <int>[];
    final container = buildContainer(sent, notifiedIds: notifiedIds);
    final facade = container.read(notificationFacadeProvider.notifier);
    final payload = {
      'packageName': 'com.example.chat',
      'nativeId': 'shared-native-id',
      'title': 'Hello',
      'text': 'World',
    };
    final now = DateTime(2026, 8, 16, 12);

    for (final peerId in ['peer-a', 'peer-b']) {
      await facade.handleIncomingMessage(
        MessageTypes.notificationMirrored,
        payload,
        MirrorMessage(
          type: MessageTypes.notificationMirrored,
          id: 'message-$peerId',
          timestamp: now.millisecondsSinceEpoch,
          payload: '',
          sourcePeerId: peerId,
        ),
        now,
      );
    }

    expect(facade.state, hasLength(2));
    expect(facade.state.map((event) => event.sourcePeerId), {
      'peer-a',
      'peer-b',
    });
    expect(facade.state.map((event) => event.id).toSet(), hasLength(2));
    expect(notifiedIds.toSet(), hasLength(2));
  });
}
