import 'package:mirrorline/features/account/base/account_api_gateway.dart';
import 'package:mirrorline/features/account/domain/account_failure.dart';
import 'package:mirrorline/features/account/domain/account_models.dart';
import 'package:mirrorline/features/account/facade/account_token_store.dart';

class AccountSessionFacade {
  AccountSessionFacade({
    required this.gateway,
    required this.tokenStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AccountApiGateway gateway;
  final AccountTokenStore tokenStore;
  final DateTime Function() _clock;

  /// Injectable time source reserved for expiry-aware UI refresh policies.
  DateTime now() => _clock();

  Future<AccountResult<AccountRegistration>> register(
    AccountCredentials credentials,
  ) => _guard(_AccountOperation.registration, () async {
    final body = await gateway.register({
      'email': credentials.email,
      'password': credentials.password,
    });
    return AccountRegistration(_requiredString(body, 'userId'));
  });

  Future<AccountResult<void>> verifyEmail(String token) =>
      _guard(_AccountOperation.verification, () => gateway.verifyEmail(token));

  Future<AccountResult<LoginOutcome>> login(
    AccountCredentials credentials, {
    String? deviceId,
  }) => _guard(_AccountOperation.login, () async {
    final body = await gateway.login({
      'email': credentials.email,
      'password': credentials.password,
      'deviceId': ?deviceId,
    });
    final tokens = body['tokens'];
    if (tokens is Map) {
      final tokenSet = _tokens(Map<String, Object?>.from(tokens));
      await tokenStore.write(tokenSet);
      return AuthenticatedLogin(tokenSet);
    }
    final enrollment = body['enrollment'];
    if (enrollment is Map) {
      final value = Map<String, Object?>.from(enrollment);
      return EnrollmentRequiredLogin(
        DeviceEnrollmentChallenge(
          enrollmentToken: _requiredString(value, 'enrollmentToken'),
          challenge: _requiredString(value, 'enrollmentChallenge'),
        ),
      );
    }
    throw const AccountApiException('MALFORMED_RESPONSE');
  });

  /// Deliberately returns the same accepted result for known and unknown
  /// emails; the server is the authority that prevents account enumeration.
  Future<AccountResult<void>> requestPasswordReset(String email) => _guard(
    _AccountOperation.passwordReset,
    () => gateway.requestPasswordReset(email),
  );

  Future<AccountResult<void>> resetPassword({
    required String token,
    required String password,
  }) => _guard(
    _AccountOperation.passwordReset,
    () => gateway.resetPassword(token, password),
  );

  Future<AccountResult<AccountTokenSet>> enroll(
    DeviceEnrollmentRequest request,
  ) => _guard(_AccountOperation.enrollment, () async {
    final body = await gateway.enroll({
      'enrollmentToken': request.enrollmentToken,
      'role': request.role,
      'platform': request.platform,
      'appVersion': request.appVersion,
      'displayName': request.displayName,
      'signingPublicKey': request.signingPublicKey,
      'encryptionPublicKey': request.encryptionPublicKey,
      'proofSignature': request.proofSignature,
    });
    final tokens = _tokens(body);
    await tokenStore.write(tokens);
    return tokens;
  });

  Future<AccountResult<AccountTokenSet>> refresh() async {
    final saved = await tokenStore.read();
    if (saved == null) {
      return const AccountFailureResult(
        AccountFailure(AccountFailureCode.sessionExpired),
      );
    }
    final result = await _guard(_AccountOperation.refresh, () async {
      final rotated = _tokens(await gateway.refresh(saved.refreshToken));
      if (rotated.userId != saved.userId ||
          rotated.deviceId != saved.deviceId) {
        await tokenStore.clear();
        throw const AccountApiException('MALFORMED_RESPONSE');
      }
      await tokenStore.write(rotated);
      return rotated;
    });
    await _clearStaleTokens(result);
    return result;
  }

  Future<AccountResult<void>> logout() async {
    final saved = await tokenStore.read();
    try {
      if (saved != null) await gateway.logout(saved.accessToken);
      return const AccountSuccess(null);
    } on AccountApiException catch (error) {
      return AccountFailureResult(_failure(error, _AccountOperation.logout));
    } catch (_) {
      return const AccountFailureResult(
        AccountFailure(AccountFailureCode.network),
      );
    } finally {
      await tokenStore.clear();
    }
  }

  Future<AccountResult<List<AccountSession>>> listSessions() => _authorized(
    _AccountOperation.session,
    (token) async =>
        (await gateway.sessions(token)).map(_session).toList(growable: false),
  );

  Future<AccountResult<void>> revokeSession(String sessionId) async {
    final result = await _authorized(
      _AccountOperation.session,
      (token) => gateway.revokeSession(token, sessionId),
    );
    return result;
  }

  Future<AccountResult<List<AccountDevice>>> listDevices() => _authorized(
    _AccountOperation.device,
    (token) async =>
        (await gateway.devices(token)).map(_device).toList(growable: false),
  );

  Future<AccountResult<void>> updateOwnFcmToken(String? fcmToken) async {
    final saved = await tokenStore.read();
    if (saved == null) {
      return const AccountFailureResult(
        AccountFailure(AccountFailureCode.sessionExpired),
      );
    }
    return _authorized(
      _AccountOperation.device,
      (token) => gateway.updateFcmToken(token, saved.deviceId, fcmToken),
    );
  }

  Future<AccountResult<void>> revokeDevice(String deviceId) async {
    final saved = await tokenStore.read();
    final result = await _authorized(
      _AccountOperation.device,
      (token) => gateway.revokeDevice(token, deviceId),
    );
    final code = result is AccountFailureResult ? result.failure.code : null;
    if (saved?.deviceId == deviceId &&
        (result is AccountSuccess ||
            code == AccountFailureCode.deviceRevoked ||
            code == AccountFailureCode.sessionExpired)) {
      await tokenStore.clear();
    }
    return result;
  }

  Future<AccountResult<T>> _authorized<T>(
    _AccountOperation operation,
    Future<T> Function(String accessToken) request,
  ) async {
    final saved = await tokenStore.read();
    if (saved == null) {
      return const AccountFailureResult(
        AccountFailure(AccountFailureCode.sessionExpired),
      );
    }
    final result = await _guard(operation, () => request(saved.accessToken));
    await _clearStaleTokens(result);
    return result;
  }

  Future<AccountResult<T>> _guard<T>(
    _AccountOperation operation,
    Future<T> Function() request,
  ) async {
    try {
      return AccountSuccess(await request());
    } on AccountApiException catch (error) {
      return AccountFailureResult(_failure(error, operation));
    } catch (_) {
      return const AccountFailureResult(
        AccountFailure(AccountFailureCode.network),
      );
    }
  }

  AccountTokenSet _tokens(Map<String, Object?> body) => AccountTokenSet(
    accessToken: _requiredString(body, 'accessToken'),
    refreshToken: _requiredString(body, 'refreshToken'),
    userId: _requiredString(body, 'userId'),
    deviceId: _requiredString(body, 'deviceId'),
  );

  Future<void> _clearStaleTokens<T>(AccountResult<T> result) async {
    final failure = switch (result) {
      AccountFailureResult<T>(failure: final value) => value,
      AccountSuccess<T>() => null,
    };
    if (failure?.code == AccountFailureCode.sessionExpired ||
        failure?.code == AccountFailureCode.deviceRevoked) {
      await tokenStore.clear();
    }
  }

  AccountSession _session(Map<String, Object?> body) => AccountSession(
    sessionId: _requiredString(body, 'sessionId'),
    deviceId: _requiredString(body, 'deviceId'),
    issuedAt: _date(body, 'issuedAt'),
    lastUsedAt: body['lastUsedAt'] is String
        ? DateTime.tryParse(body['lastUsedAt'] as String)
        : null,
    expiresAt: _date(body, 'expiresAt'),
    status: _requiredString(body, 'status'),
  );

  AccountDevice _device(Map<String, Object?> body) => AccountDevice(
    deviceId: _requiredString(body, 'deviceId'),
    role: _requiredString(body, 'role'),
    status: _requiredString(body, 'status'),
    displayName: _requiredString(body, 'displayName'),
    createdAt: _date(body, 'createdAt'),
  );

  DateTime _date(Map<String, Object?> body, String field) {
    final value = _requiredString(body, field);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const AccountApiException('MALFORMED_RESPONSE');
    return parsed;
  }

  String _requiredString(Map<String, Object?> body, String field) {
    final value = body[field];
    if (value is! String || value.isEmpty) {
      throw const AccountApiException('MALFORMED_RESPONSE');
    }
    return value;
  }

  AccountFailure _failure(
    AccountApiException error,
    _AccountOperation operation,
  ) => AccountFailure(switch (error.code) {
    'VALIDATION_FAILED' => AccountFailureCode.validation,
    'AUTH_INVALID_CREDENTIALS' => AccountFailureCode.invalidCredentials,
    'AUTH_FORBIDDEN' =>
      operation == _AccountOperation.login
          ? AccountFailureCode.emailVerificationRequired
          : AccountFailureCode.forbidden,
    'AUTH_SESSION_EXPIRED' => AccountFailureCode.sessionExpired,
    'DEVICE_REVOKED' => AccountFailureCode.deviceRevoked,
    'DEVICE_NOT_FOUND' => AccountFailureCode.deviceNotFound,
    'DEVICE_LIMIT_REACHED' => AccountFailureCode.deviceLimitReached,
    'MALFORMED_RESPONSE' => AccountFailureCode.malformedResponse,
    'NETWORK_ERROR' => AccountFailureCode.network,
    _ =>
      error.statusCode == 403
          ? AccountFailureCode.forbidden
          : AccountFailureCode.unavailable,
  });
}

enum _AccountOperation {
  registration,
  verification,
  login,
  passwordReset,
  enrollment,
  refresh,
  logout,
  session,
  device,
}
