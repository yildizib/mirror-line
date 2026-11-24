abstract interface class AccountHttpTransport {
  Future<AccountHttpResponse> send(AccountHttpRequest request);
}

class AccountHttpRequest {
  const AccountHttpRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

class AccountHttpResponse {
  const AccountHttpResponse({required this.statusCode, this.body});

  final int statusCode;
  final Object? body;
}
