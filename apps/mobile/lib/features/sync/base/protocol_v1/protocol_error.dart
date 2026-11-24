/// Typed failures returned by the protocol-v1 boundary.
enum ProtocolErrorCode {
  unsupportedVersion,
  malformedInput,
  oversizedInput,
  authenticationFailed,
}

class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message);

  final ProtocolErrorCode code;
  final String message;

  @override
  String toString() => 'ProtocolException($code, $message)';
}
