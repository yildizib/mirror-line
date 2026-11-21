import 'package:cryptography/cryptography.dart';
import 'package:mirrorline/features/sync/base/legacy_lan/message_protocol.dart';
import 'package:mirrorline/features/sync/base/legacy_lan/socket_manager.dart';

/// Keeps the existing QR bootstrap socket behavior behind the pairing boundary.
///
/// Pairing still speaks the legacy LAN wire format. The facade owns the
/// workflow while this adapter owns creation and connection of its temporary
/// socket, making a future server-backed pairing transport replaceable.
class LegacyPairingHandshakeAdapter {
  const LegacyPairingHandshakeAdapter();

  SocketManager createSocket({
    required void Function(MirrorMessage) onMessage,
    required void Function() onConnected,
    required void Function() onDisconnected,
  }) => SocketManager(
    onMessage: onMessage,
    onConnected: onConnected,
    onDisconnected: onDisconnected,
  );

  Future<bool> connect(
    SocketManager socket,
    String ip,
    int port,
    SecretKey key,
  ) => socket.connect(ip, port, key);
}
