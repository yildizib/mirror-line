import 'dart:math';

/// Supplies an opaque, unique value for every mutating pairing request.
///
/// The provider is injectable so tests can use deterministic values without
/// making production identifiers predictable.
abstract interface class ServerPairingIdempotencyKeyProvider {
  String next();
}

class SecureServerPairingIdempotencyKeyProvider
    implements ServerPairingIdempotencyKeyProvider {
  SecureServerPairingIdempotencyKeyProvider({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    return hex.join();
  }
}
