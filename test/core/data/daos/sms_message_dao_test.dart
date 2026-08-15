import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
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
  late SmsMessageDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('mirrorline_sms_message_dao_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    dao = SmsMessageDao();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  SmsMessage makeMessage({
    required String id,
    required DateTime timestamp,
    String threadId = 't1',
    String address = '+15555550100',
  }) {
    return SmsMessage(
      id: id,
      threadId: threadId,
      address: address,
      contactName: 'Test',
      body: 'hello',
      encrypted: '',
      direction: 'incoming',
      status: 'received',
      timestamp: timestamp,
      createdAt: timestamp,
    );
  }

  test('getRecent returns newest-first and respects limit', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await dao.insert(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final recent = await dao.getRecent(limit: 10);
    expect(recent.length, 10);
    expect(recent.first.id, 'm29');
    expect(recent.last.id, 'm20');
  });

  test('getRecent filters by since', () async {
    await dao.insert(makeMessage(id: 'old', timestamp: DateTime(2025, 6, 1)));
    await dao.insert(
        makeMessage(id: 'yesterday', timestamp: DateTime(2025, 6, 14, 9)));
    await dao.insert(
        makeMessage(id: 'today', timestamp: DateTime(2025, 6, 15, 8)));

    final since = DateTime(2025, 6, 14);
    final recent = await dao.getRecent(limit: 100, since: since);
    expect(recent.length, 2);
    expect(recent.map((e) => e.id).toList(), ['today', 'yesterday']);
  });

  test('getOlder returns next page after offset', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 50; i++) {
      await dao.insert(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final page1 = await dao.getOlder(limit: 10, offset: 0);
    expect(page1.length, 10);
    expect(page1.first.id, 'm49');
    expect(page1.last.id, 'm40');

    final page2 = await dao.getOlder(limit: 10, offset: 10);
    expect(page2.length, 10);
    expect(page2.first.id, 'm39');
    expect(page2.last.id, 'm30');
  });

  test('getRecentByThread returns newest 25 sorted ASC', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await dao.insert(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
        threadId: 't1',
      ));
    }

    final recent = await dao.getRecentByThread(threadId: 't1', limit: 25);
    expect(recent.length, 25);
    expect(recent.first.id, 'm5');
    expect(recent.last.id, 'm29');
  });

  test('getOlderByThread returns next 25 older messages sorted ASC', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await dao.insert(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
        threadId: 't1',
      ));
    }

    final older =
        await dao.getOlderByThread(threadId: 't1', limit: 25, offset: 25);
    expect(older.length, 5);
    expect(older.first.id, 'm0');
    expect(older.last.id, 'm4');
  });

  test('getByThread returns all messages ASC (back-compat)', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 5; i++) {
      await dao.insert(makeMessage(
        id: 'm$i',
        timestamp: base.add(Duration(minutes: i)),
        threadId: 't1',
      ));
    }
    final all = await dao.getByThread('t1');
    expect(all.length, 5);
    expect(all.first.id, 'm0');
    expect(all.last.id, 'm4');
  });
}