import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionStatus {
  final String? localIp;
  final String? peerIp;
  final String? lastBeaconIp;
  final DateTime? lastBeaconAt;
  final String? lastError;
  final int connectAttempts;
  final bool serverRunning;
  final int serverPort;

  const ConnectionStatus({
    this.localIp,
    this.peerIp,
    this.lastBeaconIp,
    this.lastBeaconAt,
    this.lastError,
    this.connectAttempts = 0,
    this.serverRunning = false,
    this.serverPort = 0,
  });

  ConnectionStatus copyWith({
    String? localIp,
    String? peerIp,
    String? lastBeaconIp,
    DateTime? lastBeaconAt,
    String? lastError,
    int? connectAttempts,
    bool? serverRunning,
    int? serverPort,
  }) =>
      ConnectionStatus(
        localIp: localIp ?? this.localIp,
        peerIp: peerIp ?? this.peerIp,
        lastBeaconIp: lastBeaconIp ?? this.lastBeaconIp,
        lastBeaconAt: lastBeaconAt ?? this.lastBeaconAt,
        lastError: lastError ?? this.lastError,
        connectAttempts: connectAttempts ?? this.connectAttempts,
        serverRunning: serverRunning ?? this.serverRunning,
        serverPort: serverPort ?? this.serverPort,
      );
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(const ConnectionStatus());

  void setLocalIp(String? ip) => state = state.copyWith(localIp: ip);

  void setPeerIp(String? ip) => state = state.copyWith(peerIp: ip);

  void setServer(int port, bool running) =>
      state = state.copyWith(serverPort: port, serverRunning: running);

  void recordBeacon(String ip) =>
      state = state.copyWith(lastBeaconIp: ip, lastBeaconAt: DateTime.now());

  void recordConnectAttempt(String? error) =>
      state = state.copyWith(
        connectAttempts: state.connectAttempts + 1,
        lastError: error,
      );

  void clearError() => state = state.copyWith(lastError: null);
}
