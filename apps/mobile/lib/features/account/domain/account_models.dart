class AccountCredentials {
  const AccountCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

class AccountTokenSet {
  const AccountTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String deviceId;
}

class AccountRegistration {
  const AccountRegistration(this.userId);

  final String userId;
}

class DeviceEnrollmentChallenge {
  const DeviceEnrollmentChallenge({
    required this.enrollmentToken,
    required this.challenge,
  });

  final String enrollmentToken;
  final String challenge;
}

sealed class LoginOutcome {
  const LoginOutcome();
}

class AuthenticatedLogin extends LoginOutcome {
  const AuthenticatedLogin(this.tokens);

  final AccountTokenSet tokens;
}

class EnrollmentRequiredLogin extends LoginOutcome {
  const EnrollmentRequiredLogin(this.challenge);

  final DeviceEnrollmentChallenge challenge;
}

class DeviceEnrollmentRequest {
  const DeviceEnrollmentRequest({
    required this.enrollmentToken,
    required this.role,
    required this.platform,
    required this.appVersion,
    required this.displayName,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.proofSignature,
  });

  final String enrollmentToken;
  final String role;
  final String platform;
  final String appVersion;
  final String displayName;
  final String signingPublicKey;
  final String encryptionPublicKey;
  final String proofSignature;
}

class AccountSession {
  const AccountSession({
    required this.sessionId,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
    required this.status,
    this.lastUsedAt,
  });

  final String sessionId;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? lastUsedAt;
  final String status;
}

class AccountDevice {
  const AccountDevice({
    required this.deviceId,
    required this.role,
    required this.status,
    required this.displayName,
    required this.createdAt,
  });

  final String deviceId;
  final String role;
  final String status;
  final String displayName;
  final DateTime createdAt;
}
