import 'package:mirrorline/features/pairing/base/server_pairing_transport.dart';

class ServerPairingApiException implements Exception {
  const ServerPairingApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;
}

abstract interface class ServerPairingGateway {
  Future<Map<String, Object?>> create(
    String accessToken,
    String idempotencyKey,
  );
  Future<Map<String, Object?>> redeem(
    String accessToken,
    String pairingId,
    String code,
    String idempotencyKey,
  );
  Future<Map<String, Object?>> status(String accessToken, String pairingId);
  Future<Map<String, Object?>> submitProof(
    String accessToken,
    String pairingId,
    String signature,
    String idempotencyKey,
  );
  Future<Map<String, Object?>> confirmComparison(
    String accessToken,
    String pairingId,
    bool matches,
    String idempotencyKey,
  );
  Future<Map<String, Object?>> cancel(
    String accessToken,
    String pairingId,
    String idempotencyKey,
  );
  Future<List<Map<String, Object?>>> devices(String accessToken);
  Future<void> unpair(
    String accessToken,
    String deviceId,
    String idempotencyKey,
  );
}

class HttpServerPairingGateway implements ServerPairingGateway {
  HttpServerPairingGateway(this._transport);

  final ServerPairingTransport _transport;

  @override
  Future<Map<String, Object?>> create(
    String accessToken,
    String idempotencyKey,
  ) =>
      _map('POST', '/v1/pairings', accessToken, idempotencyKey: idempotencyKey);

  @override
  Future<Map<String, Object?>> redeem(
    String accessToken,
    String pairingId,
    String code,
    String idempotencyKey,
  ) {
    _requireUuid(pairingId);
    return _map(
      'POST',
      '/v1/pairings/$pairingId/redeem',
      accessToken,
      idempotencyKey: idempotencyKey,
      body: {'code': code},
    );
  }

  @override
  Future<Map<String, Object?>> status(String accessToken, String pairingId) {
    _requireUuid(pairingId);
    return _map('GET', '/v1/pairings/$pairingId', accessToken);
  }

  @override
  Future<Map<String, Object?>> submitProof(
    String accessToken,
    String pairingId,
    String signature,
    String idempotencyKey,
  ) {
    _requireUuid(pairingId);
    return _map(
      'POST',
      '/v1/pairings/$pairingId/proofs',
      accessToken,
      idempotencyKey: idempotencyKey,
      body: {'signature': signature},
    );
  }

  @override
  Future<Map<String, Object?>> confirmComparison(
    String accessToken,
    String pairingId,
    bool matches,
    String idempotencyKey,
  ) {
    _requireUuid(pairingId);
    return _map(
      'POST',
      '/v1/pairings/$pairingId/comparison-confirmations',
      accessToken,
      idempotencyKey: idempotencyKey,
      body: {'matches': matches},
    );
  }

  @override
  Future<Map<String, Object?>> cancel(
    String accessToken,
    String pairingId,
    String idempotencyKey,
  ) {
    _requireUuid(pairingId);
    return _map(
      'DELETE',
      '/v1/pairings/$pairingId',
      accessToken,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<List<Map<String, Object?>>> devices(String accessToken) async {
    final response = await _request('GET', '/v1/devices', accessToken);
    if (response.body is! List) _malformed();
    try {
      return (response.body! as List)
          .map((item) => _objectMap(item))
          .toList(growable: false);
    } catch (_) {
      _malformed();
    }
  }

  @override
  Future<void> unpair(
    String accessToken,
    String deviceId,
    String idempotencyKey,
  ) {
    _requireUuid(deviceId);
    return _empty(
      'DELETE',
      '/v1/devices/$deviceId',
      accessToken,
      idempotencyKey,
    );
  }

  Future<Map<String, Object?>> _map(
    String method,
    String path,
    String accessToken, {
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) async {
    final response = await _request(
      method,
      path,
      accessToken,
      idempotencyKey: idempotencyKey,
      body: body,
    );
    if (response.body is! Map) _malformed();
    return _objectMap(response.body);
  }

  Future<void> _empty(
    String method,
    String path,
    String accessToken,
    String idempotencyKey,
  ) async {
    await _request(method, path, accessToken, idempotencyKey: idempotencyKey);
  }

  Future<ServerPairingHttpResponse> _request(
    String method,
    String path,
    String accessToken, {
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) async {
    try {
      final response = await _transport.send(
        ServerPairingHttpRequest(
          method: method,
          path: path,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Idempotency-Key': ?idempotencyKey,
          },
          body: body,
        ),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      final bodyMap = response.body;
      final code = bodyMap is Map ? bodyMap['code'] : null;
      throw ServerPairingApiException(
        code is String ? code : 'SERVICE_UNAVAILABLE',
        statusCode: response.statusCode,
      );
    } on ServerPairingApiException {
      rethrow;
    } catch (_) {
      throw const ServerPairingApiException('NETWORK_ERROR');
    }
  }

  Never _malformed() =>
      throw const ServerPairingApiException('MALFORMED_RESPONSE');

  void _requireUuid(String value) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      _malformed();
    }
  }

  Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map) _malformed();
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) _malformed();
      result[entry.key] = entry.value;
    }
    return result;
  }
}
