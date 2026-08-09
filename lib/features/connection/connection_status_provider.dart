import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

/// What went wrong on the last connect attempt, kept as a code (not a
/// rendered string) so it can be localized at the widget layer -- see
/// [connectionErrorText]. Mirrors PairingErrorCode's reasoning.
enum ConnectionErrorCode {
  serverStartFailed, // detail: the exception
  peerIpUnknown,
  connectFailed, // detail: "$ip:$port"
}

/// Renders a [ConnectionErrorCode] into user-facing text for the Settings
/// diagnostics card.
String connectionErrorText(AppLocalizations l, ConnectionErrorCode code, String? detail) {
  return switch (code) {
    ConnectionErrorCode.serverStartFailed =>
      detail == null ? l.connErrorServerStartFailed : '${l.connErrorServerStartFailed}: $detail',
    ConnectionErrorCode.peerIpUnknown => l.connErrorPeerIpUnknown,
    ConnectionErrorCode.connectFailed =>
      detail == null ? l.connErrorConnectFailed : '${l.connErrorConnectFailed}: $detail',
  };
}

class ConnectionStatus {
  final String? localIp;
  final String? peerIp;
  final String? lastBeaconIp;
  final DateTime? lastBeaconAt;
  final ConnectionErrorCode? lastErrorCode;
  final String? lastErrorDetail;
  final int connectAttempts;
  final bool serverRunning;
  final int serverPort;

  const ConnectionStatus({
    this.localIp,
    this.peerIp,
    this.lastBeaconIp,
    this.lastBeaconAt,
    this.lastErrorCode,
    this.lastErrorDetail,
    this.connectAttempts = 0,
    this.serverRunning = false,
    this.serverPort = 0,
  });

  ConnectionStatus copyWith({
    String? localIp,
    String? peerIp,
    String? lastBeaconIp,
    DateTime? lastBeaconAt,
    ConnectionErrorCode? lastErrorCode,
    String? lastErrorDetail,
    int? connectAttempts,
    bool? serverRunning,
    int? serverPort,
  }) =>
      ConnectionStatus(
        localIp: localIp ?? this.localIp,
        peerIp: peerIp ?? this.peerIp,
        lastBeaconIp: lastBeaconIp ?? this.lastBeaconIp,
        lastBeaconAt: lastBeaconAt ?? this.lastBeaconAt,
        lastErrorCode: lastErrorCode ?? this.lastErrorCode,
        lastErrorDetail: lastErrorDetail ?? this.lastErrorDetail,
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

  void recordConnectAttempt(ConnectionErrorCode? errorCode, {String? errorDetail}) =>
      state = ConnectionStatus(
        localIp: state.localIp,
        peerIp: state.peerIp,
        lastBeaconIp: state.lastBeaconIp,
        lastBeaconAt: state.lastBeaconAt,
        lastErrorCode: errorCode,
        lastErrorDetail: errorDetail,
        connectAttempts: state.connectAttempts + 1,
        serverRunning: state.serverRunning,
        serverPort: state.serverPort,
      );

  void clearError() => state = ConnectionStatus(
        localIp: state.localIp,
        peerIp: state.peerIp,
        lastBeaconIp: state.lastBeaconIp,
        lastBeaconAt: state.lastBeaconAt,
        connectAttempts: state.connectAttempts,
        serverRunning: state.serverRunning,
        serverPort: state.serverPort,
      );
}
