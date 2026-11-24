import 'dart:convert';

enum ServerPairingRole { main, source }

extension ServerPairingRoleWire on ServerPairingRole {
  String get wireValue => this == ServerPairingRole.main ? 'MAIN' : 'SOURCE';
  static ServerPairingRole? fromWire(String value) => switch (value) {
    'MAIN' => ServerPairingRole.main,
    'SOURCE' => ServerPairingRole.source,
    _ => null,
  };
}

/// The complete lifecycle exposed by the server for a registered device.
enum ServerPairingDeviceStatus { active, pending, revoked, retired }

extension ServerPairingDeviceStatusWire on ServerPairingDeviceStatus {
  String get wireValue => switch (this) {
    ServerPairingDeviceStatus.active => 'ACTIVE',
    ServerPairingDeviceStatus.pending => 'PENDING',
    ServerPairingDeviceStatus.revoked => 'REVOKED',
    ServerPairingDeviceStatus.retired => 'RETIRED',
  };

  static ServerPairingDeviceStatus? fromWire(String value) => switch (value) {
    'ACTIVE' => ServerPairingDeviceStatus.active,
    'PENDING' => ServerPairingDeviceStatus.pending,
    'REVOKED' => ServerPairingDeviceStatus.revoked,
    'RETIRED' => ServerPairingDeviceStatus.retired,
    _ => null,
  };
}

enum ServerPairingState {
  created,
  redeemed,
  proofsVerified,
  comparisonConfirmed,
  completed,
  expired,
  cancelled,
  rejected,
  failed;

  bool get isTerminal => switch (this) {
    completed || expired || cancelled || rejected || failed => true,
    _ => false,
  };

  String get wireValue => switch (this) {
    created => 'created',
    redeemed => 'redeemed',
    proofsVerified => 'proofs_verified',
    comparisonConfirmed => 'comparison_confirmed',
    completed => 'completed',
    expired => 'expired',
    cancelled => 'cancelled',
    rejected => 'rejected',
    failed => 'failed',
  };

  static ServerPairingState? fromWire(String value) {
    for (final state in ServerPairingState.values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

class PairingCanonicalIdentity {
  const PairingCanonicalIdentity({
    required this.userId,
    required this.deviceId,
    required this.role,
    required this.keyVersion,
    required this.keyFingerprint,
  });

  final String userId;
  final String deviceId;
  final ServerPairingRole role;
  final int keyVersion;
  final String keyFingerprint;

  Map<String, Object?> canonicalFields() => {
    'deviceId': deviceId,
    'keyVersion': keyVersion,
    'keyFingerprint': keyFingerprint,
    'role': role.wireValue,
    'userId': userId,
  };
}

class PairingCapacity {
  const PairingCapacity({required this.current, required this.maximum});

  final int current;
  final int maximum;
  int get available => (maximum - current).clamp(0, maximum).toInt();
  bool get isAvailable => available > 0;

  bool get isValid => current >= 0 && maximum == 5 && current <= maximum;
}

class PairingTransferPayload {
  const PairingTransferPayload({
    required this.pairingId,
    required this.code,
    required this.protocolVersion,
  });

  final String pairingId;
  final String code;
  final int protocolVersion;

  static final _codePattern = RegExp(
    r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$',
  );

  static final _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  bool get isValid =>
      _uuidV4Pattern.hasMatch(pairingId) &&
      protocolVersion == 1 &&
      _codePattern.hasMatch(code);

  factory PairingTransferPayload.fromQrPayload(Map<String, Object?> payload) {
    const permitted = {'pairingId', 'code', 'protocolVersion'};
    if (payload.keys.any((key) => !permitted.contains(key))) {
      throw const FormatException('Unexpected pairing transfer field.');
    }
    final pairingId = payload['pairingId'];
    final code = payload['code'];
    final protocolVersion = payload['protocolVersion'];
    if (pairingId is! String ||
        !_uuidV4Pattern.hasMatch(pairingId) ||
        code is! String ||
        protocolVersion is! int ||
        !_codePattern.hasMatch(code) ||
        protocolVersion != 1) {
      throw const FormatException('Malformed pairing transfer payload.');
    }
    return PairingTransferPayload(
      pairingId: pairingId,
      code: code,
      protocolVersion: protocolVersion,
    );
  }

  /// Contains exactly the QR/manual fields allowed outside the authenticated
  /// pairing session. The server remains authoritative for expiry.
  Map<String, Object?> toQrPayload() => {
    'code': code,
    'pairingId': pairingId,
    'protocolVersion': protocolVersion,
  };
}

class ServerPairingCodePayload extends PairingTransferPayload {
  const ServerPairingCodePayload({
    required super.pairingId,
    required super.code,
    required super.protocolVersion,
    required this.expiresAt,
  });

  final DateTime expiresAt;
}

class PairingComparisonValue {
  const PairingComparisonValue(this.value);

  final String value;
}

class PairingProofTranscript {
  const PairingProofTranscript({
    required this.pairingId,
    required this.challenge,
    required this.main,
    required this.source,
    required this.protocolVersion,
  });

  final String pairingId;
  final String challenge;
  final PairingCanonicalIdentity main;
  final PairingCanonicalIdentity source;
  final int protocolVersion;

  bool get isComplete =>
      PairingTransferPayload._uuidV4Pattern.hasMatch(pairingId) &&
      _isCanonicalBase64Url32(challenge) &&
      protocolVersion == 1 &&
      PairingTransferPayload._uuidV4Pattern.hasMatch(main.userId) &&
      PairingTransferPayload._uuidV4Pattern.hasMatch(main.deviceId) &&
      main.keyVersion > 0 &&
      _isCanonicalBase64Url32(main.keyFingerprint) &&
      PairingTransferPayload._uuidV4Pattern.hasMatch(source.userId) &&
      PairingTransferPayload._uuidV4Pattern.hasMatch(source.deviceId) &&
      source.keyVersion > 0 &&
      _isCanonicalBase64Url32(source.keyFingerprint) &&
      main.role == ServerPairingRole.main &&
      source.role == ServerPairingRole.source &&
      main.deviceId != source.deviceId &&
      main.userId == source.userId;

  Map<String, Object?> canonicalFields() => {
    'challenge': challenge,
    'main': main.canonicalFields(),
    'pairingId': pairingId,
    'protocolVersion': protocolVersion,
    'source': source.canonicalFields(),
  };
}

class ServerPairingTransaction {
  const ServerPairingTransaction({
    required this.pairingId,
    required this.state,
    required this.localRole,
    required this.expiresAt,
    required this.capacity,
    this.code,
    this.comparison,
    this.transcript,
  });

  final String pairingId;
  final ServerPairingState state;
  final ServerPairingRole localRole;
  final DateTime expiresAt;
  final PairingCapacity capacity;
  final ServerPairingCodePayload? code;
  final PairingComparisonValue? comparison;
  final PairingProofTranscript? transcript;

  bool get canSubmitProof => state == ServerPairingState.redeemed;
  bool get needsComparison => state == ServerPairingState.proofsVerified;
  bool get canRecover =>
      state.isTerminal && state != ServerPairingState.completed;
}

class PairingDeviceSummary {
  const PairingDeviceSummary({
    required this.deviceId,
    required this.role,
    required this.status,
    required this.displayName,
    required this.createdAt,
  });

  final String deviceId;
  final ServerPairingRole role;
  final ServerPairingDeviceStatus status;
  final String displayName;
  final DateTime createdAt;
}

bool _isCanonicalBase64Url32(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
  try {
    final decoded = base64Url.decode('$value=');
    return decoded.length == 32 &&
        base64UrlEncode(decoded).replaceAll('=', '') == value;
  } on FormatException {
    return false;
  }
}

enum ServerPairingFailureCode {
  validation,
  notFound,
  codeInvalid,
  codeExpired,
  codeUsed,
  stateInvalid,
  proofInvalid,
  comparisonMismatch,
  deviceLimitReached,
  alreadyPaired,
  sessionExpired,
  forbidden,
  rateLimited,
  unavailable,
  malformedResponse,
  staleTransaction,
}

class ServerPairingFailure {
  const ServerPairingFailure(this.code);

  final ServerPairingFailureCode code;
}

sealed class ServerPairingResult<T> {
  const ServerPairingResult();
}

class ServerPairingSuccess<T> extends ServerPairingResult<T> {
  const ServerPairingSuccess(this.value);

  final T value;
}

class ServerPairingFailureResult<T> extends ServerPairingResult<T> {
  const ServerPairingFailureResult(this.failure);

  final ServerPairingFailure failure;
}
