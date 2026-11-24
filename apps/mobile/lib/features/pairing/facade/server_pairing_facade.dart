import 'dart:convert';

import 'package:mirrorline/features/account/facade/account_token_store.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_gateway.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_idempotency_key_provider.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_proof_signer.dart';
import 'package:mirrorline/features/pairing/domain/server_pairing_models.dart';

abstract interface class ServerPairingDeviceManager {
  Future<void> revokeDevice(String accessToken, String deviceId);
}

/// Verifies the password only for the duration of a sensitive device action.
/// Implementations must not retain or log the supplied password.
abstract interface class ServerPairingReauthenticator {
  Future<bool> verifyCurrentPassword(String password);
}

class GatewayServerPairingDeviceManager implements ServerPairingDeviceManager {
  GatewayServerPairingDeviceManager(this._gateway, this._idempotencyKeys);

  final ServerPairingGateway _gateway;
  final ServerPairingIdempotencyKeyProvider _idempotencyKeys;

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) =>
      _gateway.unpair(accessToken, deviceId, _idempotencyKeys.next());
}

class ServerPairingFacade {
  ServerPairingFacade({
    required this.gateway,
    required this.tokenStore,
    required this.signer,
    ServerPairingIdempotencyKeyProvider? idempotencyKeys,
    ServerPairingDeviceManager? deviceManager,
    ServerPairingReauthenticator? reauthenticator,
    DateTime Function()? clock,
  }) : _idempotencyKeys =
           idempotencyKeys ?? SecureServerPairingIdempotencyKeyProvider(),
       _clock = clock ?? DateTime.now {
    _deviceManager =
        deviceManager ??
        GatewayServerPairingDeviceManager(gateway, _idempotencyKeys);
    _reauthenticator = reauthenticator;
  }

  final ServerPairingGateway gateway;
  final AccountTokenStore tokenStore;
  final ServerPairingProofSigner signer;
  final ServerPairingIdempotencyKeyProvider _idempotencyKeys;
  late final ServerPairingDeviceManager _deviceManager;
  late final ServerPairingReauthenticator? _reauthenticator;
  final DateTime Function() _clock;

  Future<ServerPairingResult<ServerPairingTransaction>> createMain() => _auth((
    accessToken,
    userId,
    deviceId,
  ) async {
    final response = await gateway.create(accessToken, _idempotencyKeys.next());
    return _transaction(
      response,
      expectedRole: ServerPairingRole.main,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
    );
  });

  Future<ServerPairingResult<ServerPairingTransaction>> redeem(
    PairingTransferPayload code,
  ) => _auth((accessToken, userId, deviceId) async {
    if (!code.isValid) {
      throw const ServerPairingApiException('MALFORMED_RESPONSE');
    }
    final response = await gateway.redeem(
      accessToken,
      code.pairingId,
      code.code,
      _idempotencyKeys.next(),
    );
    return _transaction(
      response,
      expectedPairingId: code.pairingId,
      expectedRole: ServerPairingRole.source,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
    );
  });

  Future<ServerPairingResult<ServerPairingTransaction>> refresh(
    ServerPairingTransaction previous,
  ) => _auth((accessToken, userId, deviceId) async {
    final response = await gateway.status(accessToken, previous.pairingId);
    return _transaction(
      response,
      expectedPairingId: previous.pairingId,
      expectedRole: previous.localRole,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
      previousCode: previous.code,
    );
  });

  Future<ServerPairingResult<ServerPairingTransaction>> submitProof(
    ServerPairingTransaction transaction,
  ) => _auth((accessToken, userId, deviceId) async {
    if (!transaction.canSubmitProof ||
        transaction.transcript == null ||
        !transaction.transcript!.isComplete) {
      throw const ServerPairingApiException('PAIRING_STATE_INVALID');
    }
    final localIdentity = transaction.localRole == ServerPairingRole.main
        ? transaction.transcript!.main
        : transaction.transcript!.source;
    if (localIdentity.userId != userId || localIdentity.deviceId != deviceId) {
      throw const ServerPairingApiException('MALFORMED_RESPONSE');
    }
    final signature = await signer.sign(
      transaction.transcript!,
      transaction.localRole,
    );
    final response = await gateway.submitProof(
      accessToken,
      transaction.pairingId,
      signature,
      _idempotencyKeys.next(),
    );
    return _transaction(
      response,
      expectedPairingId: transaction.pairingId,
      expectedRole: transaction.localRole,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
    );
  });

  Future<ServerPairingResult<ServerPairingTransaction>> confirm(
    ServerPairingTransaction transaction,
    bool matches,
  ) => _auth((accessToken, userId, deviceId) async {
    if (!transaction.needsComparison || transaction.comparison == null) {
      throw const ServerPairingApiException('PAIRING_STATE_INVALID');
    }
    final response = await gateway.confirmComparison(
      accessToken,
      transaction.pairingId,
      matches,
      _idempotencyKeys.next(),
    );
    return _transaction(
      response,
      expectedPairingId: transaction.pairingId,
      expectedRole: transaction.localRole,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
    );
  });

  Future<ServerPairingResult<ServerPairingTransaction>> cancel(
    ServerPairingTransaction transaction,
  ) => _auth((accessToken, userId, deviceId) async {
    final response = await gateway.cancel(
      accessToken,
      transaction.pairingId,
      _idempotencyKeys.next(),
    );
    final value = _transaction(
      response,
      expectedPairingId: transaction.pairingId,
      expectedRole: transaction.localRole,
      expectedUserId: userId,
      expectedDeviceId: deviceId,
    );
    if (value.state != ServerPairingState.cancelled) _malformed();
    return value;
  });

  Future<ServerPairingResult<List<PairingDeviceSummary>>> devices() => _auth(
    (accessToken, _, _) async => (await gateway.devices(
      accessToken,
    )).map(_device).toList(growable: false),
  );

  Future<ServerPairingResult<void>> unpair(
    String deviceId,
    String password,
  ) async {
    if (!_isUuid(deviceId)) {
      return const ServerPairingFailureResult(
        ServerPairingFailure(ServerPairingFailureCode.validation),
      );
    }
    final saved = await tokenStore.read();
    final result = await _auth((accessToken, _, _) async {
      final reauthenticator = _reauthenticator;
      if (reauthenticator == null ||
          password.isEmpty ||
          !await reauthenticator.verifyCurrentPassword(password)) {
        throw const ServerPairingApiException('AUTH_FORBIDDEN');
      }
      await _deviceManager.revokeDevice(accessToken, deviceId);
    });
    if (saved?.deviceId == deviceId && result is ServerPairingSuccess<void>) {
      await tokenStore.clear();
    }
    return result;
  }

  Future<ServerPairingResult<T>> _auth<T>(
    Future<T> Function(String accessToken, String userId, String deviceId)
    request,
  ) async {
    final tokens = await tokenStore.read();
    if (tokens == null) {
      return const ServerPairingFailureResult(
        ServerPairingFailure(ServerPairingFailureCode.sessionExpired),
      );
    }
    try {
      return ServerPairingSuccess(
        await request(tokens.accessToken, tokens.userId, tokens.deviceId),
      );
    } on ServerPairingApiException catch (error) {
      final failure = _failure(error);
      if (failure.code == ServerPairingFailureCode.sessionExpired) {
        await tokenStore.clear();
      }
      return ServerPairingFailureResult(failure);
    } on Exception {
      return const ServerPairingFailureResult(
        ServerPairingFailure(ServerPairingFailureCode.unavailable),
      );
    }
  }

  ServerPairingTransaction _transaction(
    Map<String, Object?> body, {
    required ServerPairingRole expectedRole,
    required String expectedUserId,
    required String expectedDeviceId,
    String? expectedPairingId,
    ServerPairingCodePayload? previousCode,
  }) {
    _allowFields(body, {
      'pairingId',
      'localRole',
      'state',
      'protocolVersion',
      'expiresAt',
      'capacity',
      'transcript',
      'code',
      'comparisonValue',
    });
    _requireFields(body, {
      'pairingId',
      'localRole',
      'state',
      'protocolVersion',
      'expiresAt',
      'capacity',
      'transcript',
      'comparisonValue',
    });
    final pairingId = _string(body, 'pairingId');
    if (!_isUuid(pairingId) ||
        !_isUuid(expectedUserId) ||
        !_isUuid(expectedDeviceId)) {
      _malformed();
    }
    if (expectedPairingId != null && pairingId != expectedPairingId) {
      _malformed();
    }
    if (_integer(body, 'protocolVersion') != 1) _malformed();

    final localRole =
        ServerPairingRoleWire.fromWire(_string(body, 'localRole')) ??
        _malformed();
    if (localRole != expectedRole) _malformed();

    final state =
        ServerPairingState.fromWire(_string(body, 'state')) ?? _malformed();

    final expiresValue = _string(body, 'expiresAt');
    if (!RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(expiresValue)) {
      _malformed();
    }
    final expiresAt = (DateTime.tryParse(expiresValue) ?? _malformed()).toUtc();
    if (!state.isTerminal && !expiresAt.isAfter(_clock())) {
      throw const ServerPairingApiException('PAIRING_CODE_EXPIRED');
    }

    final rawCapacity = body['capacity'];
    if (rawCapacity is! Map) _malformed();
    final capacityFields = _objectMap(rawCapacity);
    _allowFields(capacityFields, {'current', 'max'});
    final capacity = PairingCapacity(
      current: _integer(capacityFields, 'current'),
      maximum: _integer(capacityFields, 'max'),
    );
    if (!capacity.isValid) _malformed();

    final rawTranscript = body['transcript'];
    final requiresTranscript = switch (state) {
      ServerPairingState.redeemed ||
      ServerPairingState.proofsVerified ||
      ServerPairingState.comparisonConfirmed ||
      ServerPairingState.completed ||
      ServerPairingState.rejected => true,
      _ => false,
    };
    if (rawTranscript != null && rawTranscript is! Map) _malformed();
    final transcript = rawTranscript is Map
        ? _transcript(
            _objectMap(rawTranscript),
            expectedUserId,
            expectedDeviceId,
            localRole,
          )
        : null;
    if (requiresTranscript && transcript == null) _malformed();
    if (transcript != null && transcript.pairingId != pairingId) _malformed();

    final rawCode = body['code'];
    final isMainCreated =
        expectedRole == ServerPairingRole.main &&
        state == ServerPairingState.created;
    if (state == ServerPairingState.created && !isMainCreated) _malformed();
    final isCreateResponse = isMainCreated && previousCode == null;
    if (isCreateResponse != body.containsKey('code') ||
        (isCreateResponse && rawCode is! String) ||
        (!isCreateResponse && rawCode != null)) {
      _malformed();
    }
    final code = rawCode is String
        ? ServerPairingCodePayload(
            pairingId: pairingId,
            code: _string(body, 'code'),
            expiresAt: expiresAt,
            protocolVersion: 1,
          )
        : null;
    final preservedCode = isMainCreated && rawCode == null
        ? previousCode
        : code;
    if (preservedCode != null &&
        (preservedCode.pairingId != pairingId ||
            preservedCode.expiresAt != expiresAt)) {
      _malformed();
    }
    if (isMainCreated && (preservedCode == null || !preservedCode.isValid)) {
      _malformed();
    }

    final rawComparison = body['comparisonValue'];
    final needsComparison =
        state == ServerPairingState.proofsVerified ||
        state == ServerPairingState.comparisonConfirmed ||
        state == ServerPairingState.completed ||
        state == ServerPairingState.rejected;
    if (rawComparison != null && rawComparison is! String) {
      _malformed();
    }
    if (needsComparison &&
        (rawComparison is! String ||
            !RegExp(r'^[0-9]{6}$').hasMatch(rawComparison))) {
      _malformed();
    }
    if (!needsComparison &&
        state != ServerPairingState.expired &&
        state != ServerPairingState.cancelled &&
        state != ServerPairingState.failed &&
        rawComparison != null) {
      _malformed();
    }
    if (rawComparison is String &&
        !RegExp(r'^[0-9]{6}$').hasMatch(rawComparison)) {
      _malformed();
    }

    return ServerPairingTransaction(
      pairingId: pairingId,
      state: state,
      localRole: localRole,
      expiresAt: expiresAt,
      capacity: capacity,
      code: preservedCode,
      comparison: rawComparison is String
          ? PairingComparisonValue(rawComparison)
          : null,
      transcript: transcript,
    );
  }

  PairingProofTranscript _transcript(
    Map<String, Object?> body,
    String expectedUserId,
    String expectedDeviceId,
    ServerPairingRole localRole,
  ) {
    _allowFields(body, {
      'pairingId',
      'challenge',
      'main',
      'source',
      'protocolVersion',
    });
    PairingCanonicalIdentity identity(
      String field,
      ServerPairingRole expectedRole,
    ) {
      final raw = body[field];
      if (raw is! Map) _malformed();
      final value = _objectMap(raw);
      _allowFields(value, {
        'userId',
        'deviceId',
        'role',
        'keyVersion',
        'keyFingerprint',
      });
      final role = ServerPairingRoleWire.fromWire(_string(value, 'role'));
      final verifiedRole = role ?? _malformed();
      final userId = _string(value, 'userId');
      final deviceId = _string(value, 'deviceId');
      final fingerprint = _string(value, 'keyFingerprint');
      _base64Url32(fingerprint);
      if (verifiedRole != expectedRole ||
          _integer(value, 'keyVersion') < 1 ||
          !_isUuid(userId) ||
          !_isUuid(deviceId)) {
        _malformed();
      }
      return PairingCanonicalIdentity(
        userId: userId,
        deviceId: deviceId,
        role: verifiedRole,
        keyVersion: _integer(value, 'keyVersion'),
        keyFingerprint: fingerprint,
      );
    }

    final transcript = PairingProofTranscript(
      pairingId: _string(body, 'pairingId'),
      challenge: _base64Url32(_string(body, 'challenge')),
      main: identity('main', ServerPairingRole.main),
      source: identity('source', ServerPairingRole.source),
      protocolVersion: _integer(body, 'protocolVersion'),
    );
    if (!transcript.isComplete ||
        transcript.main.userId != expectedUserId ||
        transcript.source.userId != expectedUserId ||
        transcript.main.deviceId == transcript.source.deviceId) {
      _malformed();
    }
    final localIdentity = localRole == ServerPairingRole.main
        ? transcript.main
        : transcript.source;
    if (localIdentity.userId != expectedUserId ||
        localIdentity.deviceId != expectedDeviceId) {
      _malformed();
    }
    return transcript;
  }

  PairingDeviceSummary _device(Map<String, Object?> body) {
    _allowFields(body, {
      'deviceId',
      'role',
      'status',
      'displayName',
      'createdAt',
    });
    _requireFields(body, {
      'deviceId',
      'role',
      'status',
      'displayName',
      'createdAt',
    });
    final role = ServerPairingRoleWire.fromWire(_string(body, 'role'));
    final status = ServerPairingDeviceStatusWire.fromWire(
      _string(body, 'status'),
    );
    if (role == null || status == null) {
      _malformed();
    }
    final deviceId = _string(body, 'deviceId');
    if (!_isUuid(deviceId)) _malformed();
    return PairingDeviceSummary(
      deviceId: deviceId,
      role: role,
      status: status,
      displayName: _string(body, 'displayName'),
      createdAt: _timezoneDate(body, 'createdAt'),
    );
  }

  String _string(Map<String, Object?> body, String field) {
    final value = body[field];
    if (value is! String || value.isEmpty) _malformed();
    return value;
  }

  int _integer(Map<String, Object?> body, String field) {
    final value = body[field];
    if (value is! int) _malformed();
    return value;
  }

  DateTime _timezoneDate(Map<String, Object?> body, String field) {
    final value = _string(body, field);
    if (!RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value)) {
      _malformed();
    }
    return (DateTime.tryParse(value) ?? _malformed()).toUtc();
  }

  Map<String, Object?> _objectMap(Object? raw) {
    if (raw is! Map) _malformed();
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) _malformed();
      result[entry.key] = entry.value;
    }
    return result;
  }

  void _allowFields(Map<String, Object?> body, Set<String> allowed) {
    if (body.keys.any((key) => !allowed.contains(key))) _malformed();
  }

  void _requireFields(Map<String, Object?> body, Set<String> required) {
    if (required.any((key) => !body.containsKey(key))) _malformed();
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);

  String _base64Url32(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) _malformed();
    try {
      final decoded = base64Url.decode('$value=');
      if (decoded.length != 32 ||
          base64UrlEncode(decoded).replaceAll('=', '') != value) {
        _malformed();
      }
      return value;
    } on FormatException {
      _malformed();
    }
  }

  Never _malformed() =>
      throw const ServerPairingApiException('MALFORMED_RESPONSE');

  ServerPairingFailure _failure(ServerPairingApiException error) =>
      ServerPairingFailure(switch (error.code) {
        'PAIRING_NOT_FOUND' => ServerPairingFailureCode.notFound,
        'PAIRING_CODE_INVALID' => ServerPairingFailureCode.codeInvalid,
        'PAIRING_CODE_EXPIRED' => ServerPairingFailureCode.codeExpired,
        'PAIRING_CODE_USED' => ServerPairingFailureCode.codeUsed,
        'PAIRING_EXPIRED' => ServerPairingFailureCode.codeExpired,
        'PAIRING_CANCELLED' ||
        'PAIRING_REJECTED' ||
        'PAIRING_FAILED' => ServerPairingFailureCode.stateInvalid,
        'PAIRING_STATE_INVALID' => ServerPairingFailureCode.stateInvalid,
        'PAIRING_PROOF_INVALID' => ServerPairingFailureCode.proofInvalid,
        'PAIRING_COMPARISON_MISMATCH' =>
          ServerPairingFailureCode.comparisonMismatch,
        'DEVICE_LIMIT_REACHED' => ServerPairingFailureCode.deviceLimitReached,
        'DEVICE_NOT_FOUND' => ServerPairingFailureCode.notFound,
        'DEVICE_ROLE_CONFLICT' => ServerPairingFailureCode.alreadyPaired,
        'AUTH_SESSION_EXPIRED' ||
        'DEVICE_REVOKED' => ServerPairingFailureCode.sessionExpired,
        'AUTH_FORBIDDEN' => ServerPairingFailureCode.forbidden,
        'RATE_LIMITED' => ServerPairingFailureCode.rateLimited,
        'VALIDATION_FAILED' => ServerPairingFailureCode.validation,
        'MALFORMED_RESPONSE' => ServerPairingFailureCode.malformedResponse,
        _ => ServerPairingFailureCode.unavailable,
      });
}
