import 'package:cryptography/cryptography.dart';
import 'package:mirrorline/core/security/key_store.dart';

enum LocalStorageMigrationState { notStarted, inProgress, completed }

class LocalStorageMigrationPreparation {
  final SecretKey localKey;
  final LocalStorageMigrationState state;
  final String? checkpoint;

  const LocalStorageMigrationPreparation({
    required this.localKey,
    required this.state,
    required this.checkpoint,
  });
}

/// Coordinates local-storage key recovery and resumable migration progress.
///
/// Record transformation is intentionally delegated to a later migration
/// task. This service owns only the durable key, phase, and checkpoint state so
/// an interrupted transformation can safely resume.
class LocalStorageMigrationCoordinator {
  static const _notStarted = 'not_started';
  static const _inProgress = 'in_progress';
  static const _completed = 'completed';

  Future<LocalStorageMigrationPreparation> prepare() async {
    final localKey = await KeyStore.ensureLocalDatabaseKey();
    final state = _decodeState(await KeyStore.getLocalStorageMigrationState());
    final checkpoint = await KeyStore.getLocalStorageMigrationCheckpoint();

    return LocalStorageMigrationPreparation(
      localKey: localKey,
      state: state,
      checkpoint: checkpoint,
    );
  }

  Future<void> begin() => KeyStore.setLocalStorageMigrationState(_inProgress);

  Future<void> saveCheckpoint(String checkpoint) async {
    if (checkpoint.isEmpty) {
      throw ArgumentError.value(checkpoint, 'checkpoint');
    }
    await KeyStore.setLocalStorageMigrationCheckpoint(checkpoint);
  }

  Future<void> complete() async {
    await KeyStore.setLocalStorageMigrationState(_completed);
    await KeyStore.setLocalStorageMigrationCheckpoint('complete');
  }

  LocalStorageMigrationState _decodeState(String? state) {
    return switch (state) {
      null || _notStarted => LocalStorageMigrationState.notStarted,
      _inProgress => LocalStorageMigrationState.inProgress,
      _completed => LocalStorageMigrationState.completed,
      _ => throw StateError('Invalid local storage migration state.'),
    };
  }
}
