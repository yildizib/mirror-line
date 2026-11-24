abstract interface class ServerPairingTransport {
  Future<ServerPairingHttpResponse> send(ServerPairingHttpRequest request);
}

class ServerPairingHttpRequest {
  const ServerPairingHttpRequest({
    required this.method,
    required this.path,
    required this.headers,
    this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

class ServerPairingHttpResponse {
  const ServerPairingHttpResponse({required this.statusCode, this.body});

  final int statusCode;
  final Object? body;
}
