import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
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
      'mirrorline_sms_thread_test',
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
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  SmsMessage makeMessage({
    required String id,
    required DateTime timestamp,
    String threadId = 't1',
    String address = '+15555550100',
    String contactName = 'Alice',
    String direction = 'incoming',
    String status = 'received',
  }) {
    return SmsMessage(
      id: id,
      threadId: threadId,
      address: address,
      contactName: contactName,
      body: 'hello',
      encrypted: '',
      direction: direction,
      status: status,
      timestamp: timestamp,
      createdAt: timestamp,
    );
  }

  test('loadInitial loads today+yesterday threads', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);
    await facade.load();

    final now = DateTime.now();
    await facade.add(
      makeMessage(
        id: 'today1',
        timestamp: now.subtract(const Duration(hours: 1)),
        address: '+111',
        contactName: 'Alice',
      ),
    );
    await facade.add(
      makeMessage(
        id: 'today2',
        timestamp: now.subtract(const Duration(hours: 2)),
        address: '+222',
        contactName: 'Bob',
      ),
    );
    await facade.add(
      makeMessage(
        id: 'old',
        timestamp: now.subtract(const Duration(days: 10)),
        address: '+333',
        contactName: 'Carol',
      ),
    );

    final notifier = container.read(smsThreadsPaginatedProvider.notifier);
    await notifier.loadInitial();
    final state = container.read(smsThreadsPaginatedProvider);

    expect(state.items.length, 2);
    expect(
      state.items.map((t) => t.address).toList(),
      containsAll(['+111', '+222']),
    );
  });

  test('thread detail preserves ASC order', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);
    await facade.load();

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 10; i++) {
      await facade.add(
        makeMessage(
          id: 'm$i',
          timestamp: base.add(Duration(minutes: i)),
          threadId: 'thread_alice',
          address: '+111',
          contactName: 'Alice',
        ),
      );
    }

    final notifier = container.read(
      smsThreadDetailPaginatedProvider('+111').notifier,
    );
    await notifier.loadInitial();
    final state = container.read(smsThreadDetailPaginatedProvider('+111'));

    expect(state.items.length, 10);
    expect(state.items.first.id, 'm0');
    expect(state.items.last.id, 'm9');
  });

  test(
    'thread detail distinguishes initial loading from confirmed empty',
    () async {
      final container = buildContainer();
      final facade = container.read(smsFacadeProvider.notifier);
      await facade.load();

      final notifier = container.read(
        smsThreadDetailPaginatedProvider('+111').notifier,
      );
      expect(
        container
            .read(smsThreadDetailPaginatedProvider('+111'))
            .hasLoadedInitial,
        isFalse,
      );

      await notifier.loadInitial();

      final state = container.read(smsThreadDetailPaginatedProvider('+111'));
      expect(state.hasLoadedInitial, isTrue);
      expect(state.items, isEmpty);
    },
  );

  test('thread detail loadOlder prepends older messages', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);
    await facade.load();

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await facade.add(
        makeMessage(
          id: 'm$i',
          timestamp: base.add(Duration(minutes: i)),
          threadId: 'thread_alice',
          address: '+111',
          contactName: 'Alice',
        ),
      );
    }

    final notifier = container.read(
      smsThreadDetailPaginatedProvider('+111').notifier,
    );
    await notifier.loadInitial();
    var state = container.read(smsThreadDetailPaginatedProvider('+111'));
    expect(state.items.length, 25);
    expect(state.items.first.id, 'm5');
    expect(state.items.last.id, 'm29');

    await notifier.loadOlder();
    state = container.read(smsThreadDetailPaginatedProvider('+111'));
    expect(state.items.length, 30);
    expect(state.items.first.id, 'm0');
    expect(state.items.last.id, 'm29');
  });

  test('thread detail is keyed by address not threadId', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);
    await facade.load();

    final base = DateTime(2025, 1, 1, 12);
    await facade.add(
      makeMessage(
        id: 'a1',
        timestamp: base,
        threadId: '',
        address: '+111',
        contactName: 'Alice',
      ),
    );
    await facade.add(
      makeMessage(
        id: 'a2',
        timestamp: base.add(const Duration(minutes: 1)),
        threadId: '',
        address: '+111',
        contactName: 'Alice',
      ),
    );
    await facade.add(
      makeMessage(
        id: 'other',
        timestamp: base.add(const Duration(minutes: 2)),
        threadId: '',
        address: '+222',
        contactName: 'Bob',
      ),
    );

    final notifier = container.read(
      smsThreadDetailPaginatedProvider('+111').notifier,
    );
    await notifier.loadInitial();
    final state = container.read(smsThreadDetailPaginatedProvider('+111'));

    expect(state.items.length, 2);
    expect(state.items.map((m) => m.id).toList(), ['a1', 'a2']);
  });

  test(
    'thread detail refresh merges new messages without duplicates',
    () async {
      final container = buildContainer();
      final facade = container.read(smsFacadeProvider.notifier);
      await facade.load();

      final base = DateTime(2025, 1, 1, 12);
      await facade.add(
        makeMessage(
          id: 'm0',
          timestamp: base,
          address: '+111',
          contactName: 'Alice',
        ),
      );

      final notifier = container.read(
        smsThreadDetailPaginatedProvider('+111').notifier,
      );
      await notifier.loadInitial();

      await facade.add(
        makeMessage(
          id: 'm1',
          timestamp: base.add(const Duration(minutes: 1)),
          address: '+111',
          contactName: 'Alice',
        ),
      );
      await notifier.refresh();

      final state = container.read(smsThreadDetailPaginatedProvider('+111'));
      expect(state.items.map((m) => m.id).toList(), ['m0', 'm1']);

      await notifier.refresh();
      final state2 = container.read(smsThreadDetailPaginatedProvider('+111'));
      expect(state2.items.map((m) => m.id).toList(), ['m0', 'm1']);
    },
  );

  for (final status in ['sent', 'failed']) {
    test('refresh replaces pending with $status in list and detail', () async {
      final container = buildContainer();
      final facade = container.read(smsFacadeProvider.notifier);
      await facade.load();

      await facade.add(
        makeMessage(
          id: 'reply',
          timestamp: DateTime.now(),
          address: '+111',
          direction: 'outgoing',
          status: 'pending',
        ),
      );

      final listNotifier = container.read(smsThreadsPaginatedProvider.notifier);
      final detailNotifier = container.read(
        smsThreadDetailPaginatedProvider('+111').notifier,
      );
      await listNotifier.loadInitial();
      await detailNotifier.loadInitial();

      await facade.updateStatus('reply', status);
      await listNotifier.refresh();
      await detailNotifier.refresh();

      final listState = container.read(smsThreadsPaginatedProvider);
      final detailState = container.read(
        smsThreadDetailPaginatedProvider('+111'),
      );
      expect(listState.items.single.lastMessage.status, status);
      expect(detailState.items.single.status, status);
    });
  }
}
