import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('creates and reuses an isolated 256-bit local database key', () async {
    final first = await KeyStore.ensureLocalDatabaseKey();
    final second = await KeyStore.ensureLocalDatabaseKey();

    expect(await first.extractBytes(), equals(await second.extractBytes()));
    expect((await first.extractBytes()).length, 32);
  });

  test('local database key can be cleared independently', () async {
    await KeyStore.ensureLocalDatabaseKey();
    await KeyStore.clearLocalDatabaseKey();

    expect(await KeyStore.getLocalDatabaseKey(), isNull);
  });
}
