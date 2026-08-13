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
String connectionErrorText(
  AppLocalizations l,
  ConnectionErrorCode code,
  String? detail,
) {
  return switch (code) {
    ConnectionErrorCode.serverStartFailed =>
      detail == null
          ? l.connErrorServerStartFailed
          : '${l.connErrorServerStartFailed}: $detail',
    ConnectionErrorCode.peerIpUnknown => l.connErrorPeerIpUnknown,
    ConnectionErrorCode.connectFailed =>
      detail == null
          ? l.connErrorConnectFailed
          : '${l.connErrorConnectFailed}: $detail',
  };
}

/// What the connection machinery is doing right now. Surfaced through
/// [ConnectionStatus.discoveryState] so the UI (Settings force-connect
/// panel) can show live progress to the user instead of a silent spinner.
enum DiscoveryState {
  idle, // nothing active
  tryingStoredIp, // attempting the last known peer.ip
  tryingKnownNetwork, // attempting a cached known-network IP
  scanningSubnet, // subnet scanning 1..254 on the local /24
  connecting, // TCP+auth handshake to a discovered IP in progress
  connected, // fully connected
  failed, // last attempt failed (see lastErrorCode)
}

/// A single line in the force-connect / discovery log, shown to the user
/// in real time as the connection machinery tries different paths.
class DiscoveryLogEntry {
  final DateTime timestamp;
  final String message;
  final bool isSuccess;
  final bool isError;

  const DiscoveryLogEntry({
    required this.timestamp,
    required this.message,
    this.isSuccess = false,
    this.isError = false,
  });
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

  /// What the connection machinery is doing right now (idle/trying/
  /// scanning/connected/failed). Updated live so the Settings UI can show
  /// progress instead of a silent spinner.
  final DiscoveryState discoveryState;

  /// Human-readable detail for [discoveryState], e.g.
  /// "Trying 192.168.1.42:45678..." or "Scanning 192.168.1.0/24 (batch 3/11)".
  final String? discoveryDetail;

  /// Whether a force-connect session is active (the user pressed the
  /// button). The UI uses this to keep the progress panel open.
  final bool forceConnectActive;

  /// Real-time log of what the force-connect / discovery machinery has
  /// tried, newest last. Each entry is one line the UI can render.
  final List<DiscoveryLogEntry> discoveryLog;

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
    this.discoveryState = DiscoveryState.idle,
    this.discoveryDetail,
    this.forceConnectActive = false,
    this.discoveryLog = const [],
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
    DiscoveryState? discoveryState,
    String? discoveryDetail,
    bool? forceConnectActive,
    List<DiscoveryLogEntry>? discoveryLog,
  }) => ConnectionStatus(
    localIp: localIp ?? this.localIp,
    peerIp: peerIp ?? this.peerIp,
    lastBeaconIp: lastBeaconIp ?? this.lastBeaconIp,
    lastBeaconAt: lastBeaconAt ?? this.lastBeaconAt,
    lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    lastErrorDetail: lastErrorDetail ?? this.lastErrorDetail,
    connectAttempts: connectAttempts ?? this.connectAttempts,
    serverRunning: serverRunning ?? this.serverRunning,
    serverPort: serverPort ?? this.serverPort,
    discoveryState: discoveryState ?? this.discoveryState,
    discoveryDetail: discoveryDetail ?? this.discoveryDetail,
    forceConnectActive: forceConnectActive ?? this.forceConnectActive,
    discoveryLog: discoveryLog ?? this.discoveryLog,
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

  void recordConnectAttempt(
    ConnectionErrorCode? errorCode, {
    String? errorDetail,
  }) {
    // Clearing vs setting: when errorCode is null (success) we must
    // *replace* lastErrorCode, not preserve it. copyWith's `??` fallback
    // would keep the old error, so we rebuild the status explicitly.
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
      discoveryState: state.discoveryState,
      discoveryDetail: state.discoveryDetail,
      forceConnectActive: state.forceConnectActive,
      discoveryLog: state.discoveryLog,
    );
  }

  void clearError() {
    final next = state.copyWith(lastErrorCode: null, lastErrorDetail: null);
    // copyWith uses ?? which preserves old values on null; manually clear
    // error fields by reconstructing with nulls.
    state = ConnectionStatus(
      localIp: next.localIp,
      peerIp: next.peerIp,
      lastBeaconIp: next.lastBeaconIp,
      lastBeaconAt: next.lastBeaconAt,
      lastErrorCode: null,
      lastErrorDetail: null,
      connectAttempts: next.connectAttempts,
      serverRunning: next.serverRunning,
      serverPort: next.serverPort,
      discoveryState: next.discoveryState,
      discoveryDetail: next.discoveryDetail,
      forceConnectActive: next.forceConnectActive,
      discoveryLog: next.discoveryLog,
    );
  }

  // ------------------------------------------------------------------
  // Discovery / force-connect live progress
  // ------------------------------------------------------------------

  /// Marks the start of a force-connect session. Clears the log so the UI
  /// panel shows only this session's entries.
  void beginForceConnect() => state = ConnectionStatus(
    localIp: state.localIp,
    peerIp: state.peerIp,
    lastBeaconIp: state.lastBeaconIp,
    lastBeaconAt: state.lastBeaconAt,
    lastErrorCode: state.lastErrorCode,
    lastErrorDetail: state.lastErrorDetail,
    connectAttempts: state.connectAttempts,
    serverRunning: state.serverRunning,
    serverPort: state.serverPort,
    discoveryState: DiscoveryState.idle,
    discoveryDetail: null,
    forceConnectActive: true,
    discoveryLog: const [],
  );

  /// Marks the end of a force-connect session (success or give-up).
  void endForceConnect() => state = ConnectionStatus(
    localIp: state.localIp,
    peerIp: state.peerIp,
    lastBeaconIp: state.lastBeaconIp,
    lastBeaconAt: state.lastBeaconAt,
    lastErrorCode: state.lastErrorCode,
    lastErrorDetail: state.lastErrorDetail,
    connectAttempts: state.connectAttempts,
    serverRunning: state.serverRunning,
    serverPort: state.serverPort,
    // If we were in the middle of connecting when force ended, the
    // connection succeeded -- flip to connected. Otherwise keep
    // whatever state we were in (failed, idle, etc.).
    discoveryState: state.discoveryState == DiscoveryState.connecting
        ? DiscoveryState.connected
        : state.discoveryState,
    discoveryDetail: null, // cleared on session end
    forceConnectActive: false,
    discoveryLog: state.discoveryLog,
  );

  /// Updates the live discovery state + detail string.
  void setDiscoveryState(DiscoveryState state, {String? detail}) => this.state =
      this.state.copyWith(discoveryState: state, discoveryDetail: detail);

  /// Appends a line to the discovery log (shown in the UI force-connect
  /// panel). Trims to the last 50 entries to bound memory.
  void logDiscovery(
    String message, {
    bool isSuccess = false,
    bool isError = false,
  }) {
    final entry = DiscoveryLogEntry(
      timestamp: DateTime.now(),
      message: message,
      isSuccess: isSuccess,
      isError: isError,
    );
    final next = [...state.discoveryLog, entry];
    if (next.length > 50) next.removeRange(0, next.length - 50);
    state = state.copyWith(discoveryLog: next);
  }
}
