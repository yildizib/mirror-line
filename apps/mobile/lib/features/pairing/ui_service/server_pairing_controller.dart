import 'package:mirrorline/features/pairing/domain/server_pairing_models.dart';
import 'package:mirrorline/features/pairing/facade/server_pairing_facade.dart';

enum ServerPairingUiPhase {
  idle,
  checking,
  unavailable,
  capacityLimited,
  awaitingSource,
  awaitingProof,
  comparisonRequired,
  awaitingCompletion,
  completed,
  terminal,
  alreadyPaired,
  reauthenticationRequired,
  unpairing,
}

class ServerPairingUiState {
  const ServerPairingUiState({
    this.transaction,
    this.devices = const [],
    this.failure,
    this.capacity,
    this.phase = ServerPairingUiPhase.idle,
    this.generation = 0,
    this.unpairDeviceId,
  });

  final ServerPairingTransaction? transaction;
  final List<PairingDeviceSummary> devices;
  final ServerPairingFailure? failure;
  final PairingCapacity? capacity;
  final ServerPairingUiPhase phase;
  final int generation;
  final String? unpairDeviceId;

  bool get checking => phase == ServerPairingUiPhase.checking;
  DateTime? get expiresAt => transaction?.expiresAt;
  int? get availableCapacity =>
      capacity?.available ?? transaction?.capacity.available;
}

class ServerPairingController {
  ServerPairingController(this._facade);

  final ServerPairingFacade _facade;
  ServerPairingUiState state = const ServerPairingUiState();

  Future<ServerPairingResult<ServerPairingTransaction>> createMain() {
    if (state.capacity != null && !state.capacity!.isAvailable) {
      return _atCapacity();
    }
    final generation = _startNewTransaction();
    return _applyTransaction(generation, null, _facade.createMain());
  }

  Future<ServerPairingResult<ServerPairingTransaction>> redeem(
    PairingTransferPayload code,
  ) {
    final generation = _startNewTransaction();
    return _applyTransaction(generation, code.pairingId, _facade.redeem(code));
  }

  Future<ServerPairingResult<ServerPairingTransaction>> refresh() {
    final transaction = state.transaction;
    if (transaction == null) return _missingTransaction();
    final generation = _beginOperation(transaction);
    return _applyTransaction(
      generation,
      transaction.pairingId,
      _facade.refresh(transaction),
    );
  }

  Future<ServerPairingResult<ServerPairingTransaction>> submitProof() {
    final transaction = state.transaction;
    if (transaction == null) return _missingTransaction();
    final generation = _beginOperation(transaction);
    return _applyTransaction(
      generation,
      transaction.pairingId,
      _facade.submitProof(transaction),
    );
  }

  Future<ServerPairingResult<ServerPairingTransaction>> confirmComparison(
    bool matches,
  ) {
    final transaction = state.transaction;
    if (transaction == null) return _missingTransaction();
    final generation = _beginOperation(transaction);
    return _applyTransaction(
      generation,
      transaction.pairingId,
      _facade.confirm(transaction, matches),
    );
  }

  Future<ServerPairingResult<ServerPairingTransaction>> cancel() {
    final transaction = state.transaction;
    if (transaction == null) return _missingTransaction();
    final generation = _beginOperation(transaction);
    return _applyTransaction(
      generation,
      transaction.pairingId,
      _facade.cancel(transaction),
    );
  }

  Future<ServerPairingResult<List<PairingDeviceSummary>>> loadDevices() async {
    final generation = _beginOperation(state.transaction);
    _setChecking(generation);
    final result = await _facade.devices();
    if (!_isCurrent(generation, null)) return _staleList();
    switch (result) {
      case ServerPairingSuccess<List<PairingDeviceSummary>>(
        value: final devices,
      ):
        state = ServerPairingUiState(
          transaction: state.transaction,
          devices: devices,
          capacity: _capacityFor(devices),
          phase: _phaseFor(state.transaction, _capacityFor(devices)),
          generation: generation,
        );
      case ServerPairingFailureResult<List<PairingDeviceSummary>>(
        failure: final failure,
      ):
        _setFailure(failure, generation);
    }
    return result;
  }

  void requestUnpair(String deviceId) {
    state = ServerPairingUiState(
      transaction: state.transaction,
      devices: state.devices,
      capacity: state.capacity,
      phase: ServerPairingUiPhase.reauthenticationRequired,
      generation: state.generation,
      unpairDeviceId: deviceId,
    );
  }

  Future<ServerPairingResult<void>> confirmUnpair(String password) {
    final deviceId = state.unpairDeviceId;
    if (deviceId == null) return _missingVoidTransaction();
    final generation = _beginOperation(state.transaction);
    state = ServerPairingUiState(
      transaction: state.transaction,
      devices: state.devices,
      capacity: state.capacity,
      phase: ServerPairingUiPhase.unpairing,
      generation: generation,
      unpairDeviceId: deviceId,
    );
    return _applyVoid(
      generation,
      null,
      _facade.unpair(deviceId, password),
      onSuccess: () {
        state = ServerPairingUiState(
          transaction: state.transaction,
          devices: state.devices
              .where((device) => device.deviceId != deviceId)
              .toList(growable: false),
          capacity: _capacityFor(
            state.devices
                .where((device) => device.deviceId != deviceId)
                .toList(growable: false),
          ),
          generation: generation,
        );
      },
    );
  }

  Future<ServerPairingResult<ServerPairingTransaction>> recoverAsMain() {
    final transaction = state.transaction;
    if (transaction == null || !transaction.canRecover) {
      return _missingTransaction();
    }
    return createMain();
  }

  Future<ServerPairingResult<ServerPairingTransaction>> recoverAsSource(
    PairingTransferPayload freshCode,
  ) {
    final transaction = state.transaction;
    if (transaction == null ||
        !transaction.canRecover ||
        freshCode.pairingId == transaction.pairingId) {
      return _missingTransaction();
    }
    return redeem(freshCode);
  }

  int _startNewTransaction() {
    final generation = state.generation + 1;
    state = ServerPairingUiState(
      devices: state.devices,
      capacity: state.capacity,
      phase: ServerPairingUiPhase.checking,
      generation: generation,
    );
    return generation;
  }

  int _beginOperation(ServerPairingTransaction? transaction) {
    final generation = state.generation + 1;
    state = ServerPairingUiState(
      transaction: transaction,
      devices: state.devices,
      capacity: state.capacity,
      phase: ServerPairingUiPhase.checking,
      generation: generation,
      unpairDeviceId: state.unpairDeviceId,
    );
    return generation;
  }

  Future<ServerPairingResult<ServerPairingTransaction>> _applyTransaction(
    int generation,
    String? expectedPairingId,
    Future<ServerPairingResult<ServerPairingTransaction>> request,
  ) async {
    _setChecking(generation);
    final result = await request;
    if (!_isCurrent(generation, expectedPairingId)) return _staleTransaction();
    switch (result) {
      case ServerPairingSuccess<ServerPairingTransaction>(
        value: final transaction,
      ):
        if (expectedPairingId != null &&
            transaction.pairingId != expectedPairingId) {
          return _staleTransaction();
        }
        state = ServerPairingUiState(
          transaction: transaction,
          devices: state.devices,
          capacity: transaction.capacity,
          phase: _phaseFor(transaction),
          generation: generation,
        );
      case ServerPairingFailureResult<ServerPairingTransaction>(
        failure: final failure,
      ):
        _setFailure(failure, generation);
    }
    return result;
  }

  Future<ServerPairingResult<void>> _applyVoid(
    int generation,
    String? expectedPairingId,
    Future<ServerPairingResult<void>> request, {
    required void Function() onSuccess,
  }) async {
    final result = await request;
    if (!_isCurrent(generation, expectedPairingId)) return _staleVoid();
    switch (result) {
      case ServerPairingSuccess<void>():
        onSuccess();
      case ServerPairingFailureResult<void>(failure: final failure):
        _setFailure(failure, generation);
    }
    return result;
  }

  bool _isCurrent(int generation, String? expectedPairingId) =>
      generation == state.generation &&
      (expectedPairingId == null ||
          state.transaction == null ||
          state.transaction!.pairingId == expectedPairingId);

  void _setChecking(int generation) {
    state = ServerPairingUiState(
      transaction: state.transaction,
      devices: state.devices,
      capacity: state.capacity,
      phase: ServerPairingUiPhase.checking,
      generation: generation,
      unpairDeviceId: state.unpairDeviceId,
    );
  }

  void _setFailure(ServerPairingFailure failure, int generation) {
    state = ServerPairingUiState(
      transaction: state.transaction,
      devices: state.devices,
      capacity: state.capacity,
      failure: failure,
      phase: switch (failure.code) {
        ServerPairingFailureCode.alreadyPaired =>
          ServerPairingUiPhase.alreadyPaired,
        ServerPairingFailureCode.deviceLimitReached =>
          ServerPairingUiPhase.capacityLimited,
        ServerPairingFailureCode.forbidden =>
          ServerPairingUiPhase.reauthenticationRequired,
        ServerPairingFailureCode.codeExpired ||
        ServerPairingFailureCode.comparisonMismatch =>
          ServerPairingUiPhase.terminal,
        ServerPairingFailureCode.unavailable =>
          ServerPairingUiPhase.unavailable,
        _ => ServerPairingUiPhase.idle,
      },
      generation: generation,
    );
  }

  PairingCapacity _capacityFor(List<PairingDeviceSummary> devices) {
    final activeSources = devices.where(
      (device) =>
          device.role == ServerPairingRole.source &&
          device.status == ServerPairingDeviceStatus.active,
    );
    return PairingCapacity(current: activeSources.length, maximum: 5);
  }

  ServerPairingUiPhase _phaseFor(
    ServerPairingTransaction? transaction, [
    PairingCapacity? capacity,
  ]) {
    if (transaction == null) {
      return capacity?.isAvailable == false
          ? ServerPairingUiPhase.capacityLimited
          : ServerPairingUiPhase.idle;
    }
    if (!(capacity ?? transaction.capacity).isAvailable &&
        transaction.state == ServerPairingState.created) {
      return ServerPairingUiPhase.capacityLimited;
    }
    return switch (transaction.state) {
      ServerPairingState.created => ServerPairingUiPhase.awaitingSource,
      ServerPairingState.redeemed => ServerPairingUiPhase.awaitingProof,
      ServerPairingState.proofsVerified =>
        ServerPairingUiPhase.comparisonRequired,
      ServerPairingState.comparisonConfirmed =>
        ServerPairingUiPhase.awaitingCompletion,
      ServerPairingState.completed => ServerPairingUiPhase.completed,
      ServerPairingState.expired ||
      ServerPairingState.cancelled ||
      ServerPairingState.rejected ||
      ServerPairingState.failed => ServerPairingUiPhase.terminal,
    };
  }

  Future<ServerPairingResult<ServerPairingTransaction>>
  _missingTransaction() async {
    const result = ServerPairingFailureResult<ServerPairingTransaction>(
      ServerPairingFailure(ServerPairingFailureCode.stateInvalid),
    );
    _setFailure(result.failure, state.generation);
    return result;
  }

  Future<ServerPairingResult<void>> _missingVoidTransaction() async {
    const result = ServerPairingFailureResult<void>(
      ServerPairingFailure(ServerPairingFailureCode.stateInvalid),
    );
    _setFailure(result.failure, state.generation);
    return result;
  }

  Future<ServerPairingResult<ServerPairingTransaction>> _atCapacity() async {
    const result = ServerPairingFailureResult<ServerPairingTransaction>(
      ServerPairingFailure(ServerPairingFailureCode.deviceLimitReached),
    );
    _setFailure(result.failure, state.generation);
    return result;
  }

  ServerPairingResult<ServerPairingTransaction> _staleTransaction() =>
      const ServerPairingFailureResult(
        ServerPairingFailure(ServerPairingFailureCode.staleTransaction),
      );

  ServerPairingResult<void> _staleVoid() => const ServerPairingFailureResult(
    ServerPairingFailure(ServerPairingFailureCode.staleTransaction),
  );

  ServerPairingResult<List<PairingDeviceSummary>> _staleList() =>
      const ServerPairingFailureResult(
        ServerPairingFailure(ServerPairingFailureCode.staleTransaction),
      );
}
