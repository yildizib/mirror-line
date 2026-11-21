import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
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
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_startup_migration_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'production database bootstrap migrates an existing installation',
    () async {
      final path = p.join(tempDir.path, 'mirrorline.db');
      final legacyDb = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          singleInstance: false,
          onCreate: AppDatabase.instance.createTables,
        ),
      );
      await legacyDb.insert('sms_message', {
        'id': 'startup-sms',
        'thread_id': 'thread-1',
        'address': '+905551112233',
        'contact_name': 'Legacy Contact',
        'body': 'legacy body',
        'encrypted': '',
        'direction': 'incoming',
        'status': 'received',
        'timestamp': 1700000000000,
        'created_at': 1700000000000,
      });
      await legacyDb.close();

      final db = await AppDatabase.instance.database;
      final row = (await db.query('sms_message')).single;
      final localKey = await KeyStore.getLocalDatabaseKey();

      expect(localKey, isNotNull);
      expect(row['body'], startsWith(LocalStorageCrypto.currentPrefix));
      expect(
        await LocalStorageCrypto.decrypt(localKey!, row['body']! as String),
        'legacy body',
      );
      expect((await KeyStore.getLocalStorageMigrationState()), 'completed');
    },
  );
}
