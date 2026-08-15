import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
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
  late CallEventDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mirrorline_call_event_dao_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    dao = CallEventDao();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  CallEvent makeEvent({
    required String id,
    required DateTime timestamp,
    String number = '+15555550100',
  }) {
    return CallEvent(
      id: id,
      direction: 'incoming',
      number: number,
      contactName: 'Test',
      timestamp: timestamp,
      encrypted: '',
      status: 'missed',
      createdAt: timestamp,
    );
  }

  test('getRecent returns newest-first and respects limit', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await dao.insert(makeEvent(
        id: 'c$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final recent = await dao.getRecent(limit: 10);
    expect(recent.length, 10);
    expect(recent.first.id, 'c29');
    expect(recent.last.id, 'c20');
  });

  test('getRecent filters by since (today+yesterday)', () async {
    await dao.insert(makeEvent(id: 'old', timestamp: DateTime(2025, 6, 1)));
    await dao.insert(
        makeEvent(id: 'yesterday', timestamp: DateTime(2025, 6, 14, 9)));
    await dao.insert(
        makeEvent(id: 'today', timestamp: DateTime(2025, 6, 15, 8)));

    final since = DateTime(2025, 6, 14);
    final recent = await dao.getRecent(limit: 100, since: since);
    expect(recent.length, 2);
    expect(recent.map((e) => e.id).toList(), ['today', 'yesterday']);
  });

  test('getOlder returns next page after offset', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 50; i++) {
      await dao.insert(makeEvent(
        id: 'c$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final page1 = await dao.getOlder(limit: 10, offset: 0);
    expect(page1.length, 10);
    expect(page1.first.id, 'c49');
    expect(page1.last.id, 'c40');

    final page2 = await dao.getOlder(limit: 10, offset: 10);
    expect(page2.length, 10);
    expect(page2.first.id, 'c39');
    expect(page2.last.id, 'c30');
  });

  test('getOlder filters by before', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 10; i++) {
      await dao.insert(makeEvent(
        id: 'c$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }

    final cutoff = base.add(const Duration(minutes: 5));
    final older = await dao.getOlder(limit: 100, offset: 0, before: cutoff);
    expect(older.length, 5);
    expect(older.first.id, 'c4');
    expect(older.last.id, 'c0');
  });

  test('getAll still returns all events (back-compat)', () async {
    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 5; i++) {
      await dao.insert(makeEvent(
        id: 'c$i',
        timestamp: base.add(Duration(minutes: i)),
      ));
    }
    final all = await dao.getAll();
    expect(all.length, 5);
  });
}