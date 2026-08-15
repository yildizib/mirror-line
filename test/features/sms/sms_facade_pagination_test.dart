import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
    tempDir =
        await Directory.systemTemp.createTemp('mirrorline_sms_facade_test');
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
            notify: ({
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
  }) {
    return SmsMessage(
      id: id,
      threadId: threadId,
      address: '+15555550100',
      contactName: 'Test',
      body: 'hello',
      encrypted: '',
      direction: 'incoming',
      status: 'received',
      timestamp: timestamp,
      createdAt: timestamp,
    );
  }

  test('loadRecent returns newest-first with limit', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await facade.add(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final recent = await facade.loadRecent(limit: 10);
    expect(recent.length, 10);
    expect(recent.first.id, 'm29');
  });

  test('loadRecent filters by since', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);

    await facade.add(makeMessage(id: 'old', timestamp: DateTime(2025, 6, 1)));
    await facade.add(
        makeMessage(id: 'yesterday', timestamp: DateTime(2025, 6, 14, 9)));
    await facade.add(
        makeMessage(id: 'today', timestamp: DateTime(2025, 6, 15, 8)));

    final since = DateTime(2025, 6, 14);
    final recent = await facade.loadRecent(limit: 100, since: since);
    expect(recent.length, 2);
    expect(recent.map((e) => e.id).toList(), ['today', 'yesterday']);
  });

  test('loadOlder paginates with offset', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 50; i++) {
      await facade.add(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final page1 = await facade.loadOlder(limit: 10, offset: 0);
    expect(page1.length, 10);
    expect(page1.first.id, 'm49');

    final page2 = await facade.loadOlder(limit: 10, offset: 10);
    expect(page2.length, 10);
    expect(page2.first.id, 'm39');
  });

  test('loadRecentByThread returns newest 25 sorted ASC', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await facade.add(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
        threadId: 't1',
      ));
    }

    final recent = await facade.loadRecentByThread(threadId: 't1', limit: 25);
    expect(recent.length, 25);
    expect(recent.first.id, 'm5');
    expect(recent.last.id, 'm29');
  });

  test('loadOlderByThread returns next 25 older messages sorted ASC', () async {
    final container = buildContainer();
    final facade = container.read(smsFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await facade.add(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
        threadId: 't1',
      ));
    }

    final older =
        await facade.loadOlderByThread(threadId: 't1', limit: 25, offset: 25);
    expect(older.length, 5);
    expect(older.first.id, 'm0');
    expect(older.last.id, 'm4');
  });
}