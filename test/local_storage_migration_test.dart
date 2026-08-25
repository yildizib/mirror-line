import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/services/local_storage_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('prepare creates a key and starts in the not-started state', () async {
    final preparation = await LocalStorageMigrationCoordinator().prepare();

    expect(preparation.state, LocalStorageMigrationState.notStarted);
    expect(preparation.checkpoint, isNull);
    expect((await preparation.localKey.extractBytes()).length, 32);
  });

  test('prepare recovers in-progress state and checkpoint', () async {
    final coordinator = LocalStorageMigrationCoordinator();
    await coordinator.prepare();
    await coordinator.begin();
    await coordinator.saveCheckpoint('sms_message:42');

    final resumed = await coordinator.prepare();

    expect(resumed.state, LocalStorageMigrationState.inProgress);
    expect(resumed.checkpoint, 'sms_message:42');
  });

  test('complete stores a terminal state and checkpoint', () async {
    final coordinator = LocalStorageMigrationCoordinator();
    await coordinator.prepare();
    await coordinator.begin();
    await coordinator.complete();

    final preparation = await coordinator.prepare();

    expect(preparation.state, LocalStorageMigrationState.completed);
    expect(preparation.checkpoint, 'complete');
  });

  test('empty checkpoints are rejected', () async {
    final coordinator = LocalStorageMigrationCoordinator();

    expect(() => coordinator.saveCheckpoint(''), throwsArgumentError);
  });

  test('invalid persisted state fails closed', () async {
    FlutterSecureStorage.setMockInitialValues({
      'local_storage_migration_state': 'unknown',
    });

    expect(
      () => LocalStorageMigrationCoordinator().prepare(),
      throwsStateError,
    );
  });
}
