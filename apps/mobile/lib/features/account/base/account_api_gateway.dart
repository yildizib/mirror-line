import 'package:mirrorline/features/account/base/account_http_transport.dart';

class AccountApiException implements Exception {
  const AccountApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;
}

abstract interface class AccountApiGateway {
  Future<Map<String, Object?>> register(Map<String, Object?> request);
  Future<void> verifyEmail(String token);
  Future<Map<String, Object?>> login(Map<String, Object?> request);
  Future<void> requestPasswordReset(String email);
  Future<void> resetPassword(String token, String password);
  Future<Map<String, Object?>> enroll(Map<String, Object?> request);
  Future<Map<String, Object?>> refresh(String refreshToken);
  Future<void> logout(String accessToken);
  Future<List<Map<String, Object?>>> sessions(String accessToken);
  Future<void> revokeSession(String accessToken, String sessionId);
  Future<List<Map<String, Object?>>> devices(String accessToken);
  Future<void> updateFcmToken(
    String accessToken,
    String deviceId,
    String? fcmToken,
  );
  Future<void> revokeDevice(String accessToken, String deviceId);
}

/// HTTP adapter kept behind [AccountApiGateway] so the facade remains
/// deterministic and can be tested without network or platform dependencies.
class HttpAccountApiGateway implements AccountApiGateway {
  HttpAccountApiGateway(this._transport);

  final AccountHttpTransport _transport;

  @override
  Future<Map<String, Object?>> register(Map<String, Object?> request) =>
      _map('POST', '/v1/auth/register', body: request);

  @override
  Future<void> verifyEmail(String token) =>
      _empty('POST', '/v1/auth/verify-email', body: {'token': token});

  @override
  Future<Map<String, Object?>> login(Map<String, Object?> request) =>
      _map('POST', '/v1/auth/login', body: request);

  @override
  Future<void> requestPasswordReset(String email) =>
      _empty('POST', '/v1/auth/forgot-password', body: {'email': email});

  @override
  Future<void> resetPassword(String token, String password) => _empty(
    'POST',
    '/v1/auth/reset-password',
    body: {'token': token, 'password': password},
  );

  @override
  Future<Map<String, Object?>> enroll(Map<String, Object?> request) =>
      _map('POST', '/v1/devices/enroll', body: request);

  @override
  Future<Map<String, Object?>> refresh(String refreshToken) =>
      _map('POST', '/v1/auth/refresh', body: {'refreshToken': refreshToken});

  @override
  Future<void> logout(String accessToken) =>
      _empty('POST', '/v1/auth/logout', accessToken: accessToken);

  @override
  Future<List<Map<String, Object?>>> sessions(String accessToken) =>
      _list('GET', '/v1/sessions', accessToken: accessToken);

  @override
  Future<void> revokeSession(String accessToken, String sessionId) =>
      _empty('DELETE', '/v1/sessions/$sessionId', accessToken: accessToken);

  @override
  Future<List<Map<String, Object?>>> devices(String accessToken) =>
      _list('GET', '/v1/devices', accessToken: accessToken);

  @override
  Future<void> updateFcmToken(
    String accessToken,
    String deviceId,
    String? fcmToken,
  ) => _empty(
    'POST',
    '/v1/devices/$deviceId/fcm-token',
    accessToken: accessToken,
    body: {'fcmToken': fcmToken},
  );

  @override
  Future<void> revokeDevice(String accessToken, String deviceId) =>
      _empty('DELETE', '/v1/devices/$deviceId', accessToken: accessToken);

  Future<Map<String, Object?>> _map(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final response = await _send(
      method,
      path,
      accessToken: accessToken,
      body: body,
    );
    if (response.body is! Map) _malformed();
    return Map<String, Object?>.from(response.body! as Map);
  }

  Future<List<Map<String, Object?>>> _list(
    String method,
    String path, {
    required String accessToken,
  }) async {
    final response = await _send(method, path, accessToken: accessToken);
    if (response.body is! List) _malformed();
    try {
      return (response.body! as List)
          .map((value) => Map<String, Object?>.from(value as Map))
          .toList(growable: false);
    } catch (_) {
      _malformed();
    }
  }

  Future<void> _empty(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    await _send(method, path, accessToken: accessToken, body: body);
  }

  Future<AccountHttpResponse> _send(
    String method,
    String path, {
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    try {
      final response = await _transport.send(
        AccountHttpRequest(
          method: method,
          path: path,
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: body,
        ),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      final bodyMap = response.body;
      final code = bodyMap is Map ? bodyMap['code'] : null;
      throw AccountApiException(
        code is String ? code : 'SERVICE_UNAVAILABLE',
        statusCode: response.statusCode,
      );
    } on AccountApiException {
      rethrow;
    } catch (_) {
      throw const AccountApiException('NETWORK_ERROR');
    }
  }

  Never _malformed() => throw const AccountApiException('MALFORMED_RESPONSE');
}
