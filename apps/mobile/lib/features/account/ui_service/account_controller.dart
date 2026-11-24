import 'package:mirrorline/features/account/domain/account_failure.dart';
import 'package:mirrorline/features/account/domain/account_models.dart';
import 'package:mirrorline/features/account/facade/account_session_facade.dart';

class AccountUiState {
  const AccountUiState({
    this.isWorking = false,
    this.failure,
    this.sessions = const [],
    this.devices = const [],
  });

  final bool isWorking;
  final AccountFailure? failure;
  final List<AccountSession> sessions;
  final List<AccountDevice> devices;

  AccountUiState copyWith({
    bool? isWorking,
    AccountFailure? failure,
    List<AccountSession>? sessions,
    List<AccountDevice>? devices,
    bool clearFailure = false,
  }) => AccountUiState(
    isWorking: isWorking ?? this.isWorking,
    failure: clearFailure ? null : failure ?? this.failure,
    sessions: sessions ?? this.sessions,
    devices: devices ?? this.devices,
  );
}

/// UI-only coordinator. It imports facade/domain exclusively, never base or
/// platform implementations, so widgets can use just ui_service and domain.
class AccountController {
  AccountController(this._facade);

  final AccountSessionFacade _facade;
  AccountUiState state = const AccountUiState();

  Future<AccountResult<LoginOutcome>> login(
    AccountCredentials credentials, {
    String? deviceId,
  }) async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await _facade.login(credentials, deviceId: deviceId);
    state = _withResult(result);
    return result;
  }

  Future<AccountResult<AccountRegistration>> register(
    AccountCredentials credentials,
  ) => _run(() => _facade.register(credentials));

  Future<AccountResult<void>> verifyEmail(String token) =>
      _runVoid(() => _facade.verifyEmail(token));

  Future<AccountResult<AccountTokenSet>> enroll(
    DeviceEnrollmentRequest request,
  ) => _run(() => _facade.enroll(request));

  Future<AccountResult<AccountTokenSet>> refresh() =>
      _run(() => _facade.refresh());

  Future<AccountResult<void>> logout() => _runVoid(_facade.logout);

  Future<AccountResult<void>> revokeSession(String sessionId) =>
      _runVoid(() => _facade.revokeSession(sessionId));

  Future<AccountResult<void>> updateOwnFcmToken(String? token) =>
      _runVoid(() => _facade.updateOwnFcmToken(token));

  Future<AccountResult<void>> revokeDevice(String deviceId) =>
      _runVoid(() => _facade.revokeDevice(deviceId));

  Future<void> loadSessionsAndDevices() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final sessions = await _facade.listSessions();
    final devices = await _facade.listDevices();
    final failure = _failureOf(sessions) ?? _failureOf(devices);
    state = state.copyWith(
      isWorking: false,
      failure: failure,
      sessions: sessions is AccountSuccess<List<AccountSession>>
          ? sessions.value
          : null,
      devices: devices is AccountSuccess<List<AccountDevice>>
          ? devices.value
          : null,
    );
  }

  Future<AccountResult<void>> requestPasswordReset(String email) =>
      _runVoid(() => _facade.requestPasswordReset(email));

  Future<AccountResult<void>> resetPassword({
    required String token,
    required String password,
  }) => _runVoid(() => _facade.resetPassword(token: token, password: password));

  Future<AccountResult<void>> _runVoid(
    Future<AccountResult<void>> Function() action,
  ) async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await action();
    state = _withResult(result);
    return result;
  }

  Future<AccountResult<T>> _run<T>(
    Future<AccountResult<T>> Function() action,
  ) async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await action();
    state = _withResult(result);
    return result;
  }

  AccountUiState _withResult<T>(AccountResult<T> result) {
    final failure = _failureOf(result);
    return state.copyWith(
      isWorking: false,
      failure: failure,
      clearFailure: failure == null,
    );
  }

  AccountFailure? _failureOf<T>(AccountResult<T> result) => switch (result) {
    AccountFailureResult<T>(failure: final failure) => failure,
    AccountSuccess<T>() => null,
  };
}
