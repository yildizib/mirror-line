import 'dart:async';

import 'package:cryptography/cryptography.dart';

typedef PairingMessageHandler =
    FutureOr<void> Function(String type, Map<String, dynamic>? payload);

/// The only transport surface exposed to pairing orchestration and UI services.
abstract interface class PairingTransport {
  Object get connectionToken;
  bool get isCurrent;
  String? get remoteAddress;

  Future<bool> send(String type, Map<String, dynamic> payload);
}

/// A temporary client transport used by the QR-scanning side.
abstract interface class PairingClientTransport implements PairingTransport {
  Future<bool> connect(String ip, int port, SecretKey key);
  Future<void> disconnect();
}

typedef PairingClientTransportFactory =
    PairingClientTransport Function({
      required PairingMessageHandler onMessage,
      required void Function() onDisconnected,
    });
