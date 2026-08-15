// No DAO in this repo has a dedicated test yet -- this introduces the
// pattern for KnownNetworkDao since its round-trip logic (and the
// peer+subnet composite key in particular) isn't otherwise covered.
// AppDatabase resolves its file path via path_provider, which needs a
// platform implementation even in plain `flutter_test` unit tests -- faked
// here with a temp directory, the same way sqflite is faked via
// sqflite_common_ffi in database_migration_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/daos/known_network_dao.dart';
import 'package:mirrorline/core/data/database.dart';
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
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_known_network_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  test('lookupIp returns null when nothing was ever recorded', () async {
    final dao = KnownNetworkDao();
    expect(
      await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '192.168.1'),
      isNull,
    );
  });

  test('recordSuccess then lookupIp round-trips the IP', () async {
    final dao = KnownNetworkDao();
    await dao.recordSuccess(
      peerId: 'peer-1',
      subnetPrefix: '192.168.1',
      ip: '192.168.1.42',
      port: 45678,
    );

    expect(
      await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '192.168.1'),
      '192.168.1.42',
    );
  });

  test(
    'recordSuccess overwrites the previous entry for the same peer+subnet',
    () async {
      final dao = KnownNetworkDao();
      await dao.recordSuccess(
        peerId: 'peer-1',
        subnetPrefix: '192.168.1',
        ip: '192.168.1.42',
        port: 45678,
      );
      await dao.recordSuccess(
        peerId: 'peer-1',
        subnetPrefix: '192.168.1',
        ip: '192.168.1.99',
        port: 45678,
      );

      expect(
        await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '192.168.1'),
        '192.168.1.99',
      );
    },
  );

  test('different peers on the same subnet are kept separate', () async {
    final dao = KnownNetworkDao();
    await dao.recordSuccess(
      peerId: 'peer-1',
      subnetPrefix: '192.168.1',
      ip: '192.168.1.10',
      port: 45678,
    );
    await dao.recordSuccess(
      peerId: 'peer-2',
      subnetPrefix: '192.168.1',
      ip: '192.168.1.20',
      port: 45678,
    );

    expect(
      await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '192.168.1'),
      '192.168.1.10',
    );
    expect(
      await dao.lookupIp(peerId: 'peer-2', subnetPrefix: '192.168.1'),
      '192.168.1.20',
    );
  });

  test('the same peer on a different subnet is kept separate', () async {
    final dao = KnownNetworkDao();
    await dao.recordSuccess(
      peerId: 'peer-1',
      subnetPrefix: '192.168.1',
      ip: '192.168.1.10',
      port: 45678,
    );
    await dao.recordSuccess(
      peerId: 'peer-1',
      subnetPrefix: '10.8.0',
      ip: '10.8.0.2',
      port: 45678,
    );

    expect(
      await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '192.168.1'),
      '192.168.1.10',
    );
    expect(
      await dao.lookupIp(peerId: 'peer-1', subnetPrefix: '10.8.0'),
      '10.8.0.2',
    );
  });
}
