import 'package:mirrorline/features/sync/base/legacy_lan/socket_manager.dart';

/// Compatibility adapter for MirrorLine's existing direct LAN/VPN transport.
///
/// It deliberately inherits [SocketManager] so the pairing handshake keeps
/// its existing socket identity semantics while the sync facade gets an
/// explicitly named transport boundary.
final class LegacyLanTransportAdapter extends SocketManager {
  LegacyLanTransportAdapter({
    required super.onMessage,
    super.onConnected,
    super.onDisconnected,
    super.onAcceptConnection,
    super.socketStreamListener,
    super.logger,
  });
}
