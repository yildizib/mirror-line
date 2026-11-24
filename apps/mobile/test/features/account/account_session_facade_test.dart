import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/secure_account_token_store.dart';
import 'package:mirrorline/features/account/base/account_api_gateway.dart';
import 'package:mirrorline/features/account/domain/account_failure.dart';
import 'package:mirrorline/features/account/domain/account_models.dart';
import 'package:mirrorline/features/account/facade/account_session_facade.dart';
import 'package:mirrorline/features/account/facade/account_token_store.dart';
import 'package:mirrorline/features/account/ui_service/account_controller.dart';

void main() {
  test('register returns only the server-generated user identifier', () async {
    final gateway = _FakeGateway()
      ..registerResponse = {'userId': 'server-user'};
    final facade = AccountSessionFacade(
      gateway: gateway,
      tokenStore: _MemoryTokenStore(),
    );

    final result = await facade.register(
      const AccountCredentials(
        email: 'person@example.com',
        password: 'safe-password-123',
      ),
    );

    expect(result, isA<AccountSuccess<AccountRegistration>>());
    expect(
      (result as AccountSuccess<AccountRegistration>).value.userId,
      'server-user',
    );
  });

  test('maps server errors to neutral typed failures', () async {
    final gateway = _FakeGateway()
      ..loginError = const AccountApiException('AUTH_INVALID_CREDENTIALS');
    final facade = AccountSessionFacade(
      gateway: gateway,
      tokenStore: _MemoryTokenStore(),
    );

    final result = await facade.login(
      const AccountCredentials(
        email: 'person@example.com',
        password: 'wrong-password',
      ),
    );

    expect(result, isA<AccountFailureResult<LoginOutcome>>());
    expect(
      (result as AccountFailureResult<LoginOutcome>).failure.code,
      AccountFailureCode.invalidCredentials,
    );
  });

  test(
    'maps forbidden by operation without disclosing server detail',
    () async {
      final loginGateway = _FakeGateway()
        ..loginError = const AccountApiException('AUTH_FORBIDDEN');
      final deviceGateway = _FakeGateway()
        ..sessionsError = const AccountApiException('AUTH_FORBIDDEN');

      final login =
          await AccountSessionFacade(
            gateway: loginGateway,
            tokenStore: _MemoryTokenStore(),
          ).login(
            const AccountCredentials(
              email: 'person@example.com',
              password: 'password-123456',
            ),
          );
      final sessions = await AccountSessionFacade(
        gateway: deviceGateway,
        tokenStore: _MemoryTokenStore(_tokens()),
      ).listSessions();

      expect(
        (login as AccountFailureResult<LoginOutcome>).failure.code,
        AccountFailureCode.emailVerificationRequired,
      );
      expect(
        (sessions as AccountFailureResult<List<AccountSession>>).failure.code,
        AccountFailureCode.forbidden,
      );
    },
  );

  test('refresh rotation replaces both stored tokens', () async {
    final store = _MemoryTokenStore(
      const AccountTokenSet(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        userId: 'server-user',
        deviceId: 'server-device',
      ),
    );
    final gateway = _FakeGateway()
      ..refreshResponse = {
        'accessToken': 'new-access',
        'refreshToken': 'new-refresh',
        'userId': 'server-user',
        'deviceId': 'server-device',
      };
    final facade = AccountSessionFacade(gateway: gateway, tokenStore: store);

    final result = await facade.refresh();

    expect(result, isA<AccountSuccess<AccountTokenSet>>());
    expect(store.value?.accessToken, 'new-access');
    expect(store.value?.refreshToken, 'new-refresh');
    expect(store.value?.deviceId, 'server-device');
  });

  test('expired refresh clears stale local tokens', () async {
    final store = _MemoryTokenStore(_tokens());
    final gateway = _FakeGateway()
      ..refreshError = const AccountApiException('AUTH_SESSION_EXPIRED');
    final result = await AccountSessionFacade(
      gateway: gateway,
      tokenStore: store,
    ).refresh();

    expect(result, isA<AccountFailureResult<AccountTokenSet>>());
    expect(store.value, isNull);
  });

  test(
    'refresh rejects an identity mismatch without replacing tokens',
    () async {
      final store = _MemoryTokenStore(_tokens());
      final gateway = _FakeGateway()
        ..refreshResponse = {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'userId': 'different-user',
          'deviceId': 'server-device',
        };
      final result = await AccountSessionFacade(
        gateway: gateway,
        tokenStore: store,
      ).refresh();

      expect(result, isA<AccountFailureResult<AccountTokenSet>>());
      expect(store.value, isNull);
    },
  );

  test('secure token storage writes one versioned rotation record', () async {
    final storage = _MemorySecureStore();
    final store = SecureAccountTokenStore(storage: storage);

    await store.write(_tokens());
    final restored = await store.read();

    expect(storage.writeCount, 1);
    expect(storage.values.keys, {'account_session_record_v1'});
    expect(restored?.userId, 'server-user');
    expect(restored?.deviceId, 'server-device');
    expect(storage.values.values.single, isNot(contains('password')));
  });

  test('enrollment stores server-issued device identifier', () async {
    final store = _MemoryTokenStore();
    final facade = AccountSessionFacade(
      gateway: _FakeGateway(),
      tokenStore: store,
    );

    final result = await facade.enroll(
      const DeviceEnrollmentRequest(
        enrollmentToken: 'enrollment-token',
        role: 'MAIN',
        platform: 'android',
        appVersion: '1.0.0',
        displayName: 'Primary',
        signingPublicKey: 'signing-key',
        encryptionPublicKey: 'encryption-key',
        proofSignature: 'proof',
      ),
    );

    expect(result, isA<AccountSuccess<AccountTokenSet>>());
    expect(store.value?.deviceId, 'server-device');
  });

  test('malformed server payload is a typed failure', () async {
    final gateway = _FakeGateway()..registerResponse = const {};
    final result =
        await AccountSessionFacade(
          gateway: gateway,
          tokenStore: _MemoryTokenStore(),
        ).register(
          const AccountCredentials(
            email: 'person@example.com',
            password: 'password-123456',
          ),
        );

    expect(result, isA<AccountFailureResult<AccountRegistration>>());
    expect(
      (result as AccountFailureResult<AccountRegistration>).failure.code,
      AccountFailureCode.malformedResponse,
    );
  });

  test(
    'logout clears local tokens even when server session is unavailable',
    () async {
      final store = _MemoryTokenStore(_tokens());
      final gateway = _FakeGateway()
        ..logoutError = const AccountApiException('AUTH_SESSION_EXPIRED');
      final facade = AccountSessionFacade(gateway: gateway, tokenStore: store);

      final result = await facade.logout();

      expect(result, isA<AccountFailureResult<void>>());
      expect(store.value, isNull);
    },
  );

  test('expired session revocation clears stale local tokens', () async {
    final store = _MemoryTokenStore(_tokens());
    final gateway = _FakeGateway()
      ..revokeSessionError = const AccountApiException('AUTH_SESSION_EXPIRED');
    final result = await AccountSessionFacade(
      gateway: gateway,
      tokenStore: store,
    ).revokeSession('session-1');

    expect(result, isA<AccountFailureResult<void>>());
    expect(store.value, isNull);
  });

  test(
    'stale device and FCM operations clear local tokens centrally',
    () async {
      final deviceStore = _MemoryTokenStore(_tokens());
      final fcmStore = _MemoryTokenStore(_tokens());
      final deviceResult = await AccountSessionFacade(
        gateway: _FakeGateway()
          ..devicesError = const AccountApiException('DEVICE_REVOKED'),
        tokenStore: deviceStore,
      ).listDevices();
      final fcmResult = await AccountSessionFacade(
        gateway: _FakeGateway()
          ..fcmError = const AccountApiException('AUTH_SESSION_EXPIRED'),
        tokenStore: fcmStore,
      ).updateOwnFcmToken('fcm-address');

      expect(deviceResult, isA<AccountFailureResult<List<AccountDevice>>>());
      expect(fcmResult, isA<AccountFailureResult<void>>());
      expect(deviceStore.value, isNull);
      expect(fcmStore.value, isNull);
    },
  );

  test('forgot and reset password remain neutral facade operations', () async {
    final gateway = _FakeGateway();
    final facade = AccountSessionFacade(
      gateway: gateway,
      tokenStore: _MemoryTokenStore(),
    );

    final forgot = await facade.requestPasswordReset('person@example.com');
    final reset = await facade.resetPassword(
      token: 'mail-token',
      password: 'new-password-123',
    );

    expect(forgot, isA<AccountSuccess<void>>());
    expect(reset, isA<AccountSuccess<void>>());
    expect(gateway.passwordResetEmail, 'person@example.com');
    expect(gateway.resetToken, 'mail-token');
  });

  test(
    'lists sessions and devices, updates FCM, and revokes devices safely',
    () async {
      final gateway = _FakeGateway()
        ..sessionsResponse = [
          {
            'sessionId': 'session-1',
            'deviceId': 'server-device',
            'issuedAt': '2026-11-24T00:00:00Z',
            'lastUsedAt': '2026-11-24T01:00:00Z',
            'expiresAt': '2026-12-24T00:00:00Z',
            'status': 'ACTIVE',
          },
        ]
        ..devicesResponse = [
          {
            'deviceId': 'server-device',
            'role': 'MAIN',
            'status': 'ACTIVE',
            'displayName': 'Primary',
            'createdAt': '2026-11-24T00:00:00Z',
          },
        ];
      final store = _MemoryTokenStore(_tokens());
      final facade = AccountSessionFacade(gateway: gateway, tokenStore: store);

      final sessions = await facade.listSessions();
      final devices = await facade.listDevices();
      final fcm = await facade.updateOwnFcmToken('fcm-address');
      final otherRevoke = await facade.revokeDevice('other-device');
      expect(otherRevoke, isA<AccountSuccess<void>>());
      expect(gateway.revokedDeviceId, 'other-device');
      expect(store.value?.deviceId, 'server-device');

      final selfRevoke = await facade.revokeDevice('server-device');

      expect(
        (sessions as AccountSuccess<List<AccountSession>>).value,
        hasLength(1),
      );
      expect(
        (devices as AccountSuccess<List<AccountDevice>>).value.single.role,
        'MAIN',
      );
      expect(fcm, isA<AccountSuccess<void>>());
      expect(gateway.updatedFcmDeviceId, 'server-device');
      expect(selfRevoke, isA<AccountSuccess<void>>());
      expect(gateway.revokedDeviceId, 'server-device');
      expect(store.value, isNull);
    },
  );

  test('ui service has no base or platform implementation imports', () {
    final source = File(
      'lib/features/account/ui_service/account_controller.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/base/')));
    expect(source, isNot(contains('/core/')));
    expect(source, contains('/facade/'));
    expect(source, contains('/domain/'));
  });

  test('models do not expose raw token or password values in diagnostics', () {
    const tokens = AccountTokenSet(
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
      userId: 'server-user',
      deviceId: 'server-device',
    );
    const credentials = AccountCredentials(
      email: 'person@example.com',
      password: 'password-secret',
    );

    expect(tokens.toString(), isNot(contains('access-secret')));
    expect(tokens.toString(), isNot(contains('refresh-secret')));
    expect(credentials.toString(), isNot(contains('password-secret')));
  });

  test('controller clears an old failure after a successful login', () async {
    final gateway = _FakeGateway()
      ..loginError = const AccountApiException('AUTH_INVALID_CREDENTIALS');
    final controller = AccountController(
      AccountSessionFacade(gateway: gateway, tokenStore: _MemoryTokenStore()),
    );

    await controller.login(
      const AccountCredentials(email: 'person@example.com', password: 'wrong'),
    );
    gateway.loginError = null;
    await controller.login(
      const AccountCredentials(
        email: 'person@example.com',
        password: 'correct',
      ),
    );

    expect(controller.state.failure, isNull);
    expect(controller.state.isWorking, isFalse);
  });

  test('controller exposes password reset flow without base imports', () async {
    final gateway = _FakeGateway();
    final controller = AccountController(
      AccountSessionFacade(gateway: gateway, tokenStore: _MemoryTokenStore()),
    );

    final result = await controller.requestPasswordReset('person@example.com');

    expect(result, isA<AccountSuccess<void>>());
    expect(gateway.passwordResetEmail, 'person@example.com');
    expect(controller.state.failure, isNull);
  });
}

AccountTokenSet _tokens() => const AccountTokenSet(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  userId: 'server-user',
  deviceId: 'server-device',
);

class _MemoryTokenStore implements AccountTokenStore {
  _MemoryTokenStore([this.value]);

  AccountTokenSet? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AccountTokenSet?> read() async => value;

  @override
  Future<void> write(AccountTokenSet tokens) async => value = tokens;
}

class _MemorySecureStore implements AccountSecureKeyValueStore {
  final Map<String, String> values = {};
  int writeCount = 0;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    values[key] = value;
  }
}

class _FakeGateway implements AccountApiGateway {
  Map<String, Object?> registerResponse = const {'userId': 'server-user'};
  Map<String, Object?> refreshResponse = const {
    'accessToken': 'access-token',
    'refreshToken': 'refresh-token',
    'userId': 'server-user',
    'deviceId': 'server-device',
  };
  List<Map<String, Object?>> sessionsResponse = const [];
  List<Map<String, Object?>> devicesResponse = const [];
  AccountApiException? loginError;
  AccountApiException? logoutError;
  AccountApiException? refreshError;
  AccountApiException? sessionsError;
  AccountApiException? devicesError;
  AccountApiException? fcmError;
  AccountApiException? revokeSessionError;
  String? updatedFcmDeviceId;
  String? revokedDeviceId;
  String? passwordResetEmail;
  String? resetToken;

  @override
  Future<List<Map<String, Object?>>> devices(String accessToken) async {
    if (devicesError != null) throw devicesError!;
    return devicesResponse;
  }

  @override
  Future<Map<String, Object?>> enroll(Map<String, Object?> request) async =>
      const {
        'deviceId': 'server-device',
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'server-user',
      };

  @override
  Future<Map<String, Object?>> login(Map<String, Object?> request) async {
    if (loginError != null) throw loginError!;
    return const {
      'tokens': {
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'server-user',
        'deviceId': 'server-device',
      },
    };
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    passwordResetEmail = email;
  }

  @override
  Future<void> resetPassword(String token, String password) async {
    resetToken = token;
  }

  @override
  Future<void> logout(String accessToken) async {
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<Map<String, Object?>> refresh(String refreshToken) async {
    if (refreshError != null) throw refreshError!;
    return refreshResponse;
  }

  @override
  Future<Map<String, Object?>> register(Map<String, Object?> request) async =>
      registerResponse;

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) async =>
      revokedDeviceId = deviceId;

  @override
  Future<void> revokeSession(String accessToken, String sessionId) async {
    if (revokeSessionError != null) throw revokeSessionError!;
  }

  @override
  Future<List<Map<String, Object?>>> sessions(String accessToken) async {
    if (sessionsError != null) throw sessionsError!;
    return sessionsResponse;
  }

  @override
  Future<void> updateFcmToken(
    String accessToken,
    String deviceId,
    String? fcmToken,
  ) async {
    if (fcmError != null) throw fcmError!;
    updatedFcmDeviceId = deviceId;
  }

  @override
  Future<void> verifyEmail(String token) async {}
}
