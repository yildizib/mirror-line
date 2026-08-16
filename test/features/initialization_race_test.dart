import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/daos/notification_event_dao.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCallEventDao extends CallEventDao {
  _FakeCallEventDao(this.initialEvents);

  final Future<List<CallEvent>> initialEvents;
  bool insertCalled = false;

  @override
  Future<List<CallEvent>> getAll() => initialEvents;

  @override
  Future<void> insert(CallEvent event) async {
    insertCalled = true;
  }
}

class _FakeNotificationEventDao extends NotificationEventDao {
  _FakeNotificationEventDao([Future<List<NotificationEvent>>? initialEvents])
    : initialEvents = initialEvents ?? Future.value([]);

  final Future<List<NotificationEvent>> initialEvents;
  final List<NotificationEvent> inserted = [];

  @override
  Future<List<NotificationEvent>> getAll() => initialEvents;

  @override
  Future<void> insert(NotificationEvent event) async {
    inserted.add(event);
  }
}

class _FakePeerDao extends PeerDao {
  _FakePeerDao(this.initialPeer);

  final Future<Peer?> initialPeer;

  @override
  Future<Peer?> getPeer() => initialPeer;
}

CallEvent _call(String id) {
  final timestamp = DateTime(2026, 8, 16, 12);
  return CallEvent(
    id: id,
    direction: 'incoming',
    number: '+15555550100',
    contactName: 'Test',
    timestamp: timestamp,
    encrypted: '',
    status: 'ringing',
    createdAt: timestamp,
  );
}

NotificationEvent _notification(String id) {
  final timestamp = DateTime(2026, 8, 16, 12);
  return NotificationEvent(
    id: id,
    nativeId: 'native-$id',
    sourcePeerId: NotificationEvent.localSourcePeerId,
    packageName: 'com.example.chat',
    appName: 'Chat',
    title: 'Message',
    text: 'Hello',
    encrypted: '',
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

Peer _peer(String id) => Peer(
  id: id,
  deviceName: id,
  role: 'main',
  ip: '192.168.1.2',
  port: 45678,
  key: 'key',
  publicKey: 'public-key',
  createdAt: DateTime(2026, 8, 16, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'watched_packages_migrated': true,
      'watched_packages': <String>[],
    });
  });

  test('CallFacade waits for constructor load before adding', () async {
    final load = Completer<List<CallEvent>>();
    final dao = _FakeCallEventDao(load.future);
    final container = ProviderContainer(
      overrides: [
        callFacadeProvider.overrideWith(
          (ref) => CallFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
            sendOrQueue: (_, _) async => true,
            notify: _ignoreNotification,
            dao: dao,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final facade = container.read(callFacadeProvider.notifier);

    final add = facade.add(_call('new'));
    await Future<void>.delayed(Duration.zero);
    expect(dao.insertCalled, isFalse);

    load.complete([_call('old')]);
    await add;

    expect(facade.state.map((event) => event.id), ['old', 'new']);
  });

  test('NotificationFacade waits for constructor load before adding', () async {
    final load = Completer<List<NotificationEvent>>();
    final dao = _FakeNotificationEventDao(load.future);
    final container = ProviderContainer(
      overrides: [
        notificationFacadeProvider.overrideWith(
          (ref) => NotificationFacade(
            ref: ref,
            logger: Logger(),
            sendOrQueue: (_, _) async => true,
            notify: _ignoreNotification,
            dao: dao,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final facade = container.read(notificationFacadeProvider.notifier);

    final add = facade.add(_notification('new'));
    await Future<void>.delayed(Duration.zero);
    expect(dao.inserted, isEmpty);

    load.complete([_notification('old')]);
    await add;

    expect(facade.state.map((event) => event.id), ['new', 'old']);
  });

  test(
    'PeerFacade waits for constructor load before applying an update',
    () async {
      final load = Completer<Peer?>();
      final facade = PeerFacade(dao: _FakePeerDao(load.future));
      addTearDown(facade.dispose);

      final update = facade.applyUpdate(_peer('new'));
      await Future<void>.delayed(Duration.zero);
      expect(facade.state, isNull);

      load.complete(_peer('old'));
      await update;

      expect(facade.state?.id, 'new');
    },
  );

  test(
    'watched-app mutations wait for initialization and stay ordered',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final load = Completer<SharedPreferences>();
      final notifier = WatchedAppsNotifier(getPreferences: () => load.future);
      addTearDown(notifier.dispose);

      final watch = notifier.setWatched('com.example.chat', true);
      final unwatch = notifier.setWatched('com.example.mail', false);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isInitialized, isFalse);

      load.complete(preferences);
      await Future.wait([watch, unwatch]);

      expect(notifier.state.isInitialized, isTrue);
      expect(notifier.state.packages, {'com.example.chat'});
      expect(preferences.getStringList('watched_packages'), [
        'com.example.chat',
      ]);
    },
  );

  test(
    'eligible startup notification is buffered until watched apps load',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('watched_packages', ['com.example.chat']);
      final watchedLoad = Completer<SharedPreferences>();
      final dao = _FakeNotificationEventDao();
      final sent = <String>[];
      final container = ProviderContainer(
        overrides: [
          watchedAppsProvider.overrideWith(
            (ref) =>
                WatchedAppsNotifier(getPreferences: () => watchedLoad.future),
          ),
          notificationFacadeProvider.overrideWith(
            (ref) => NotificationFacade(
              ref: ref,
              logger: Logger(),
              sendOrQueue: (type, _) async {
                sent.add(type);
                return true;
              },
              notify: _ignoreNotification,
              dao: dao,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final facade = container.read(notificationFacadeProvider.notifier);

      final handling = facade.handleNativeEvent(
        {
          'packageName': 'com.example.chat',
          'appName': 'Chat',
          'title': 'Message',
          'text': 'Hello',
          'id': 'native-1',
        },
        id: 'event-1',
        now: DateTime(2026, 8, 16, 12),
      );
      await Future<void>.delayed(Duration.zero);
      expect(dao.inserted, isEmpty);
      expect(sent, isEmpty);

      watchedLoad.complete(preferences);
      await handling;

      expect(dao.inserted.single.id, 'event-1');
      expect(sent, ['notification_mirrored']);
    },
  );
}

Future<void> _ignoreNotification({
  required int id,
  required String title,
  required String body,
  NotificationPayload? payload,
}) async {}
