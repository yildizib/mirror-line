import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/calls/call_group_provider.dart';
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
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_call_group_test',
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
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  CallEvent makeEvent({
    required String id,
    required DateTime timestamp,
    String number = '+15555550100',
    String contactName = 'Alice',
    String status = 'missed',
  }) {
    return CallEvent(
      id: id,
      direction: 'incoming',
      number: number,
      contactName: contactName,
      timestamp: timestamp,
      encrypted: '',
      status: status,
      createdAt: timestamp,
    );
  }

  test('loadInitial loads today+yesterday groups', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    await facade.add(
      makeEvent(
        id: 'today1',
        timestamp: now.subtract(const Duration(hours: 1)),
        contactName: 'Alice',
      ),
    );
    await facade.add(
      makeEvent(
        id: 'today2',
        timestamp: now.subtract(const Duration(hours: 2)),
        contactName: 'Bob',
      ),
    );
    await facade.add(
      makeEvent(
        id: 'old',
        timestamp: now.subtract(const Duration(days: 10)),
        contactName: 'Carol',
      ),
    );

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(callGroupsPaginatedProvider);

    expect(state.items.length, 2);
    expect(
      state.items.map((g) => g.key).toList(),
      containsAll(['Alice', 'Bob']),
    );
    expect(state.hasReachedEnd, isTrue);
  });

  test('loadMore appends older groups', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    for (var i = 0; i < 60; i++) {
      await facade.add(
        makeEvent(
          id: 'recent_$i',
          timestamp: yesterdayStart.add(Duration(minutes: i * 20)),
          contactName: 'Recent$i',
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      await facade.add(
        makeEvent(
          id: 'old_$i',
          timestamp: yesterdayStart.subtract(Duration(hours: i + 1)),
          contactName: 'OldContact$i',
        ),
      );
    }

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    var state = container.read(callGroupsPaginatedProvider);
    final initialCount = state.items.length;
    expect(initialCount, lessThanOrEqualTo(25));

    await notifier.loadMore();
    state = container.read(callGroupsPaginatedProvider);
    expect(state.items.length, greaterThan(initialCount));
  });

  test('groups merge correctly on loadMore', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    await facade.add(
      makeEvent(
        id: 'recent_alice',
        timestamp: now.subtract(const Duration(hours: 1)),
        contactName: 'Alice',
      ),
    );
    for (var i = 0; i < 30; i++) {
      await facade.add(
        makeEvent(
          id: 'filler_$i',
          timestamp: yesterdayStart.add(Duration(minutes: i * 30)),
          contactName: 'Filler$i',
        ),
      );
    }
    await facade.add(
      makeEvent(
        id: 'old_alice',
        timestamp: yesterdayStart.subtract(const Duration(days: 10)),
        contactName: 'Alice',
      ),
    );

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    await notifier.loadMore();
    await notifier.loadMore();
    await notifier.loadMore();
    await notifier.loadMore();
    final state = container.read(callGroupsPaginatedProvider);

    final aliceGroup = state.items.where((g) => g.key == 'Alice').first;
    expect(aliceGroup.calls.length, 2);
  });

  test('refresh merges newly arrived calls without duplicates', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    await facade.add(
      makeEvent(
        id: 'call1',
        timestamp: now.subtract(const Duration(hours: 2)),
        contactName: 'Alice',
      ),
    );

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    expect(container.read(callGroupsPaginatedProvider).items.length, 1);

    await facade.add(
      makeEvent(
        id: 'call2',
        timestamp: now.subtract(const Duration(hours: 1)),
        contactName: 'Alice',
      ),
    );
    await facade.add(
      makeEvent(
        id: 'call3',
        timestamp: now.subtract(const Duration(minutes: 30)),
        contactName: 'Bob',
      ),
    );

    await notifier.refresh();
    final state = container.read(callGroupsPaginatedProvider);

    expect(state.items.length, 2);
    final alice = state.items.where((g) => g.key == 'Alice').first;
    final bob = state.items.where((g) => g.key == 'Bob').first;
    expect(alice.calls.map((c) => c.id).toList(), ['call2', 'call1']);
    expect(bob.calls.map((c) => c.id).toList(), ['call3']);
    expect(state.items.first.key, 'Bob');
  });

  test('refresh replaces a stale status for the same call', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    await facade.add(makeEvent(id: 'call1', timestamp: now, status: 'ringing'));

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    expect(
      container.read(callGroupsPaginatedProvider).items.single.hasActive,
      isTrue,
    );

    await facade.updateStatus('call1', 'missed');
    await notifier.refresh();

    final group = container.read(callGroupsPaginatedProvider).items.single;
    expect(group.calls, hasLength(1));
    expect(group.calls.single.status, 'missed');
    expect(group.hasActive, isFalse);
  });

  test(
    'refresh moves an updated call without retaining its old group',
    () async {
      final container = buildContainer();
      final facade = container.read(callFacadeProvider.notifier);
      await facade.load();

      final now = DateTime.now();
      await facade.add(
        makeEvent(
          id: 'call1',
          timestamp: now,
          number: '+15555550100',
          contactName: '',
          status: 'ringing',
        ),
      );

      final notifier = container.read(callGroupsPaginatedProvider.notifier);
      await notifier.loadInitial();

      await facade.add(
        makeEvent(
          id: 'call1',
          timestamp: now,
          number: '+15555550100',
          contactName: 'Alice',
        ),
      );
      await notifier.refresh();

      final groups = container.read(callGroupsPaginatedProvider).items;
      expect(groups.map((group) => group.key), ['Alice']);
      expect(
        groups
            .expand((group) => group.calls)
            .where((call) => call.id == 'call1'),
        hasLength(1),
      );
    },
  );

  test('refresh removes a deleted recent call group', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);
    await facade.load();
    await facade.add(makeEvent(id: 'deleted', timestamp: DateTime.now()));

    final notifier = container.read(callGroupsPaginatedProvider.notifier);
    await notifier.loadInitial();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await facade.remove('deleted');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await notifier.refresh();

    expect(container.read(callGroupsPaginatedProvider).items, isEmpty);
  });

  test('activeCall identifies the ringing call in a mixed group', () {
    final now = DateTime.now();
    final group = CallGroup(
      key: 'Alice',
      displayName: 'Alice',
      calls: [
        makeEvent(id: 'newer', timestamp: now),
        makeEvent(
          id: 'ringing',
          timestamp: now.subtract(const Duration(minutes: 1)),
          status: 'ringing',
        ),
      ],
    );

    expect(group.hasActive, isTrue);
    expect(group.activeCall?.id, 'ringing');
  });
}
