import 'package:cryptography/cryptography.dart';

/// Transport-independent contract owned by the sync feature.
///
/// Product facades depend on this boundary instead of knowing whether the
/// active transport is the legacy LAN socket or a future server relay.
abstract interface class TransportAdapter {
  bool get isConnected;
  bool get isServerMode;
  bool get isPairingMode;
  int? get boundPort;
  String? get remoteAddress;

  void setBackgroundMode(bool background);
  void requireAuthIdentity();
  void setAuthIdentity({
    required String peerPublicKeyBase64,
    required SimpleKeyPair localKeyPair,
    String? localDeviceId,
    String? peerDeviceId,
  });

  Future<void> startServer(int port, SecretKey key);
  Future<void> stopServer();
  Future<bool> connect(
    String host,
    int port,
    SecretKey key, {
    Duration? connectTimeout,
  });
  Future<bool> sendMessage(String type, Map<String, dynamic> payload);
  Future<void> disconnectClient();
  Future<void> disconnect();
}
