import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/known_network_dao.dart';
import 'package:mirrorline/core/data/daos/inbox_dao.dart';
import 'package:mirrorline/core/data/models/inbox_record.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/peer_discovery.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mirrorline/core/services/connectivity_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/queue_service.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/connection/force_connect_strategy.dart';
import 'package:mirrorline/features/connection/peer_discovery_coordinator.dart';
import 'package:mirrorline/features/connection/reconnect_scheduler.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/pairing/pairing_facade.dart';
import 'package:mirrorline/features/pairing/pairing_transport.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

/// Sends a single mirrored/peer message, queuing it locally if the socket
/// isn't currently writable. Implemented by ConnectionFacade (see
/// [ConnectionFacade.sendOrQueue]) so CallFacade/SmsFacade never need
/// their own view of the socket.
typedef SendOrQueue =
    Future<bool> Function(String type, Map<String, dynamic> payload);
typedef DomainMutation = Future<void> Function(Transaction database);

/// Shows (or replaces, by id) a local notification.
typedef ShowNotification =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      NotificationPayload? payload,
    });

class _SocketPairingTransport implements PairingTransport {
  _SocketPairingTransport(this._socket, this._generation);

  final SocketManager _socket;
  final int _generation;

  @override
  Object get connectionToken => (_socket, _generation);

  @override
  bool get isCurrent => _socket.isSessionCurrent(_generation);

  @override
  String? get remoteAddress => isCurrent ? _socket.remoteAddress : null;

  @override
  Future<bool> send(String type, Map<String, dynamic> payload) async {
    if (!isCurrent) return false;
    return _socket.sendMessage(type, payload);
  }
}

final connectionFacadeProvider = StateNotifierProvider<ConnectionFacade, bool>((
  ref,
) {
  return ConnectionFacade(ref);
});

final connectionConnectingProvider = Provider<bool>((ref) {
  return ref.watch(connectionFacadeProvider.notifier).isConnecting;
});

class ConnectionFacade extends StateNotifier<bool> with WidgetsBindingObserver {
  static const Duration _retryInterval = Duration(seconds: 30);
  // How long an outgoing SMS may sit on 'pending' before it's given up on
  // and shown as 'failed'. The queue's own 5-attempt retry only advances
  // when the connection actually comes back up (see _flushQueue), so if
  // the peer never reconnects a queued sms_status ack would otherwise
  // never get marked either way -- this is a connection-state-independent
  // backstop so "Gönderiliyor" doesn't linger forever.
  static const Duration _pendingSmsTimeout = Duration(minutes: 2);

  final Logger _logger = Logger();
  final Ref _ref;
  final ConnectivityService _connectivity = ConnectivityService();
  final PeerDao _peerDao = PeerDao();
  final KnownNetworkDao _knownNetworkDao = KnownNetworkDao();
  final QueueService _queue = QueueService();
  final InboxDao _inbox = InboxDao();
  final BeaconBroadcaster _broadcaster = BeaconBroadcaster();
  // Used only by _scanSubnetsWithProgress (force-reconnect's manual scan);
  // the periodic fallback scan's own scanner now lives inside
  // PeerDiscoveryCoordinator. These are two independent SubnetScanner
  // instances -- a force-reconnect scan and a periodic fallback scan could
  // now in principle run concurrently, whereas before they shared one
  // _scanning guard. Accepted as a narrow, low-risk divergence: force-
  // reconnect is rare/user-initiated and the periodic scan is itself rare
  // (25s grace + 60s backoff), so the overlap window is small and running
  // two network probes concurrently isn't harmful, just not deduped.
  final SubnetScanner _scanner = SubnetScanner();

  SocketManager? _socketManager;
  _SocketPairingTransport? _pairingTransport;
  Peer? _peer;
  SecretKey? _key;
  Timer? _healthTimer;
  bool _connecting = false;
  bool _refreshing = false;
  Completer<void>? _refreshDone;
  bool _scanning = false;
  bool _networkingStopped = false;
  bool _forceConnecting = false;
  ScanCancellationToken? _scanCancellation;
  bool _telephonyHandlerRegistered = false;
  void Function()? _clearTelephonyHandler;
  bool _online = true;
  String? _lastDiscoveredIp;
  // Resolved once (KeyStore reads are async) and cached for
  // PeerDiscoveryCoordinator's sync getPeerId/getDeviceName callbacks --
  // see _startAsMain.
  String? _selfDiscoveryId;
  String? _selfDiscoveryName;
  // Bumped whenever a forced reconnect abandons an in-flight _connectTo()
  // call, so that stale call's post-await continuation (recordConnectAttempt,
  // _maybeScheduleReconnect, resetting _connecting) is skipped instead of
  // stomping on the newer attempt it was superseded by. Deliberately kept
  // separate from ReconnectScheduler's own internal generation counter --
  // this one guards ConnectionFacade's own async continuations across
  // fallback-scan and network-changed paths, not just timer-driven
  // reconnects, so the two must not be conflated.
  int _connectGeneration = 0;
  final OutboxFlushGate _flushGate = OutboxFlushGate();
  bool _disposed = false;
  int _lifecycleGeneration = 0;

  // Owns the periodic/backoff reconnect timer against the stored peer
  // address. Callbacks are tear-offs of this instance (see the comment
  // above), so constructed in the constructor body alongside the handlers.
  late final ReconnectScheduler _reconnectScheduler;

  // Owns beacon listening and fallback subnet scanning (Main role only --
  // Source uses _broadcaster instead, which is unrelated). Same
  // constructor-body-construction reasoning as _reconnectScheduler.
  late final PeerDiscoveryCoordinator _peerDiscoveryCoordinator;

  ConnectionFacade(this._ref) : super(false) {
    _reconnectScheduler = ReconnectScheduler(
      logger: _logger,
      onReconnect: (ip, port) async {
        final ok = await _connectTo(ip, port);
        if (!ok) {
          // _connectTo already re-armed a guarded retry via
          // _maybeScheduleReconnect() below; throwing here additionally
          // lets the scheduler's own catch block increment its attempt
          // counter so backoff actually grows across scheduler-driven
          // retries (harmless redundant reschedule for this one path --
          // scheduleReconnect() always cancels+replaces the pending timer).
          throw StateError('Scheduled reconnect to $ip:$port failed');
        }
      },
      getPeerIp: () => _lastDiscoveredIp ?? _peer?.ip,
      getPeerPort: () => _peer?.port ?? 0,
    );
    _peerDiscoveryCoordinator = PeerDiscoveryCoordinator(
      logger: _logger,
      onDiscovered: _onDiscovered,
      getPeerId: () => _selfDiscoveryId ?? _peer?.id ?? '',
      getPeerPort: () => _peer?.port ?? 0,
      getDeviceName: () => _selfDiscoveryName ?? _peer?.deviceName ?? '',
      getAllLocalIps: () => _allLocalIps,
      getExpectedPeerId: () => _peer?.id,
    );
    _init();
  }

  bool get isSource => _peer?.role == 'source';
  bool get isConnecting => _connecting;

  PairingTransport? get pairingTransport {
    final socket = _socketManager;
    final generation = socket?.sessionGeneration;
    if (socket == null || generation == null) return null;
    final current = _pairingTransport;
    if (current?.connectionToken == (socket, generation)) return current;
    return _pairingTransport = _SocketPairingTransport(socket, generation);
  }

  void _init() async {
    WidgetsBinding.instance.addObserver(this);

    // Registered here (role-agnostic, before any peer/role is even loaded)
    // rather than only from _startAsSource(): the native onNetworkChanged
    // event (see _handleNetworkChangedEvent) needs to reach Main too, since
    // Main is the device that dials out and most needs to react quickly to
    // having roamed (see _maybeRunFallbackScan's "only Main ever dials
    // out"). Idempotent via _telephonyHandlerRegistered.
    _registerTelephonyHandler();

    _connectivity.onChanged = (isOnline) {
      _online = isOnline;
      _lifecycleGeneration++;
      if (isOnline) {
        _logger.i('Network back online. Reconnecting...');
        if (!_networkingStopped) {
          _reconnectScheduler.start();
          _refresh();
          _maybeScheduleReconnect();
        }
      } else {
        _logger.i(
          'Network offline. Dropping stale connection, pausing attempts.',
        );
        state = false;
        _reconnectScheduler.pause();
        _cancelActiveScan();
        _peerDiscoveryCoordinator.cancelActiveScan();
        _peerDiscoveryCoordinator.markDisconnected();
        // Actually tear down the client-side connection, not just the UI
        // flag. Some network transitions (e.g. Wi-Fi AP roam) never deliver
        // a socket error, so SocketManager's internal _isConnected can stay
        // stuck true; its connect() then short-circuits to a no-op "success"
        // on the next attempt without ever firing onConnected, leaving
        // `state` permanently stuck at false until the app is restarted.
        _socketManager?.disconnectClient();
        // Forget the peer address we discovered on the old network: once
        // we're back online it may be stale, and reconnect must re-discover
        // instead of hammering a dead IP for minutes.
        _lastDiscoveredIp = null;
      }
    };
    _connectivity.startListening();

    try {
      final lifecycleGeneration = _lifecycleGeneration;
      final isOnline = await _connectivity.isOnline();
      if (lifecycleGeneration == _lifecycleGeneration) {
        _online = isOnline;
      }
      if (isOnline && lifecycleGeneration == _lifecycleGeneration) {
        await _refresh();
      }
    } catch (e) {
      _logger.e('Connection init failed: $e');
    }

    // Self-healing safety net for BOTH roles (not just 'main'): if the
    // connection ever goes quietly stale -- silently dropped Wi-Fi, a dead
    // beacon broadcaster/listener, anything that isn't caught by the
    // socket's own error/heartbeat handling -- this periodically redoes
    // the same full (re)initialization that happens on a fresh app start,
    // so devices recover on their own instead of requiring the app to be
    // killed and reopened.
    if (_disposed) return;
    _healthTimer ??= Timer.periodic(_retryInterval, (_) {
      if (_disposed || _networkingStopped || !_online) return;
      _ref
          .read(smsFacadeProvider.notifier)
          .failStalePending(_pendingSmsTimeout);
      if (_networkingStopped || _connecting || state) return;
      _refresh();
      _maybeRunFallbackScan();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _socketManager?.setBackgroundMode(false);
      _refresh();
      _maybeScheduleReconnect();
    } else if (state == AppLifecycleState.paused) {
      _socketManager?.setBackgroundMode(true);
    }
  }

  /// Reloads peer info and (re)starts role-specific networking machinery.
  /// Call after pairing, role changes or resets, and also called
  /// periodically by _healthTimer as a self-healing check.
  Future<void> refresh() async {
    _networkingStopped = false;
    _lifecycleGeneration++;
    _reconnectScheduler.start();
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_networkingStopped || _disposed) return;
    if (_refreshing) {
      await _refreshDone?.future;
      if (_networkingStopped || _disposed) return;
      return _refresh();
    }
    final lifecycleGeneration = _lifecycleGeneration;
    _refreshing = true;
    _refreshDone = Completer<void>();
    try {
      try {
        _peer = await _peerDao.getPeer();
        _key = await KeyStore.getPeerKey();
        if (!_isLifecycleCurrent(lifecycleGeneration)) return;
      } catch (e) {
        _logger.e('Failed to load peer info: $e');
        return;
      }

      final peer = _peer;
      final pairingValid =
          peer != null && peer.publicKey.isNotEmpty && _key != null;
      final nativeRole = _mirroringRole(peer?.role);
      try {
        await TelephonyChannel.syncMirroringEligibility(
          enabled: pairingValid,
          role: nativeRole,
          paired: pairingValid,
        );
        if (!_isLifecycleCurrent(lifecycleGeneration)) {
          await TelephonyChannel.nativeEventsNotReady();
          return;
        }
        if (pairingValid && nativeRole != MirroringRole.unknown) {
          await Future.wait([
            _ref.read(callFacadeProvider.notifier).initialized,
            _ref.read(smsFacadeProvider.notifier).initialized,
            _ref.read(notificationFacadeProvider.notifier).initialized,
            _ref.read(watchedAppsProvider.notifier).initialized,
          ]);
          if (!_isLifecycleCurrent(lifecycleGeneration)) {
            await TelephonyChannel.nativeEventsNotReady();
            return;
          }
          await TelephonyChannel.nativeEventsReady();
          if (!_isLifecycleCurrent(lifecycleGeneration)) {
            await TelephonyChannel.nativeEventsNotReady();
            return;
          }
        }
      } catch (e) {
        _logger.e('Failed to synchronize native mirroring lifecycle: $e');
        return;
      }

      final statusNotifier = _ref.read(connectionStatusProvider.notifier);
      // Use getAllLocalIps for VPN support: collects WiFi + VPN TUN + etc.
      final allIps = await PeerDiscovery().getAllLocalIps();
      if (!_isLifecycleCurrent(lifecycleGeneration)) return;
      _allLocalIps = allIps.map((e) => e.ip).toList();
      statusNotifier.setLocalIp(allIps.isNotEmpty ? allIps.first.ip : null);
      statusNotifier.setPeerIp(_peer?.ip);

      if (!pairingValid) {
        _logger.w('No valid paired peer or key found. Waiting for pairing.');
        await _stopMachinery();
        return;
      }

      try {
        if (isSource) {
          await _startAsSource(lifecycleGeneration);
        } else {
          await _startAsMain(lifecycleGeneration);
        }
      } catch (e) {
        _logger.e('Failed to start networking: $e');
      }
    } finally {
      _refreshing = false;
      _refreshDone?.complete();
      _refreshDone = null;
    }
  }

  bool _isLifecycleCurrent(int generation) =>
      generation == _lifecycleGeneration &&
      _online &&
      !_networkingStopped &&
      !_disposed;

  MirroringRole _mirroringRole(String? role) => switch (role) {
    'source' => MirroringRole.source,
    'main' => MirroringRole.main,
    _ => MirroringRole.unknown,
  };

  /// Refreshes the reported local IP without touching the peer record.
  /// Used when showing the pairing QR, where the address must be current but
  /// must never be written back into the (possibly already-paired) peer row
  /// -- unlike PeerFacade.refreshLocalIp, which used to overwrite the
  /// paired peer's stored IP with this device's own address.
  ///
  /// Uses [getAllLocalIps] for VPN support: when the device has both WiFi
  /// and VPN interfaces, the first private IP (typically WiFi) is set as
  /// the "primary" localIp for backwards compatibility, but the full list
  /// is available for subnet scanning.
  Future<void> updateLocalIp() async {
    final allIps = await PeerDiscovery().getAllLocalIps();
    if (allIps.isNotEmpty) {
      _ref.read(connectionStatusProvider.notifier).setLocalIp(allIps.first.ip);
      _allLocalIps = allIps.map((e) => e.ip).toList();
    }
  }

  /// All local IPs across all interfaces (WiFi + VPN + ethernet). Used by
  /// the subnet scanner to scan all /24 subnets in parallel for VPN support.
  /// Updated by [updateLocalIp] and [refresh].
  List<String> _allLocalIps = [];

  Future<void> _startAsSource(int lifecycleGeneration) async {
    final peer = _peer!;
    final key = _key!;
    _reconnectScheduler.stop();

    _socketManager ??= _createSocketManager();
    await _configureAuth(_socketManager!);
    if (!_isLifecycleCurrent(lifecycleGeneration)) return;
    if (_socketManager!.isConnected == false) {
      try {
        await _socketManager!.startServer(peer.port, key);
        if (!_isLifecycleCurrent(lifecycleGeneration)) {
          await _socketManager!.stopServer();
          return;
        }
        _ref.read(connectionStatusProvider.notifier).setServer(peer.port, true);
      } catch (e) {
        _logger.e('Server start failed: $e');
        _ref
            .read(connectionStatusProvider.notifier)
            .recordConnectAttempt(
              ConnectionErrorCode.serverStartFailed,
              errorDetail: '$e',
            );
      }
    }

    // Broadcast this device's OWN identity, not `peer` (which represents
    // the *other* device once paired -- see applyPairedPeer). Fall back to
    // the peer record for pre-fix installs that never persisted a self id.
    // Guarded so the periodic self-healing refresh() (see _healthTimer)
    // doesn't tear down and rebind a perfectly healthy UDP broadcaster
    // every 10 seconds.
    if (!_broadcaster.isBroadcasting) {
      final selfId = await KeyStore.getSelfId() ?? peer.id;
      final selfName = await KeyStore.getSelfDeviceName() ?? peer.deviceName;
      if (!_isLifecycleCurrent(lifecycleGeneration)) return;
      // Include all local IPs (WiFi + VPN) in the beacon so the receiver
      // can try them all if the UDP source IP is unreachable.
      final allIps = _allLocalIps.isNotEmpty ? _allLocalIps : null;
      await _broadcaster.start(
        peerId: selfId,
        tcpPort: peer.port,
        deviceName: selfName,
        ips: allIps,
      );
      if (!_isLifecycleCurrent(lifecycleGeneration)) {
        await _broadcaster.stop();
        return;
      }
    }

    try {
      final result = await TelephonyChannel.startListening();
      if (!_isLifecycleCurrent(lifecycleGeneration)) {
        await TelephonyChannel.stopListening(
          enabled: false,
          role: MirroringRole.source,
          paired: false,
        );
        return;
      }
      switch (result.outcome) {
        case MirroringServiceOutcome.startRequested:
          _logger.i('Native mirroring service start requested.');
        case MirroringServiceOutcome.permissionsRequired:
          _logger.w('Native mirroring permissions are required.');
        case MirroringServiceOutcome.ineligible:
          _logger.w('Native mirroring service is ineligible to start.');
        case MirroringServiceOutcome.failed:
          _logger.e('Native mirroring service failed: ${result.error}');
        case MirroringServiceOutcome.unavailable:
          _logger.d('Native mirroring service unavailable on this platform.');
        case MirroringServiceOutcome.stopped:
          _logger.w('Native mirroring start unexpectedly returned stopped.');
      }
    } catch (e) {
      _logger.e('Telephony startListening failed: $e');
    }
    // Recovery is independent of Inbox redelivery. Only `executing` work is
    // returned to `received`; `submitted` work remains indeterminate.
    await _ref.read(smsFacadeProvider.notifier).recoverOutgoingSms();
    await _ref.read(callFacadeProvider.notifier).recoverCallRejects();
    _logger.i(
      'Source mode active: server on ${peer.port}, beacon broadcasting.',
    );
  }

  Future<void> _startAsMain(int lifecycleGeneration) async {
    final peer = _peer!;
    final key = _key!;
    final isPaired = peer.publicKey.isNotEmpty;
    _reconnectScheduler.start();

    if (!isPaired) {
      // Not yet paired to a specific device: also listen on our own port,
      // exactly like 'source' always does, so a QR scan works regardless
      // of who scans whom. There's no real peer to dial out to yet, so
      // skip the client/beacon machinery entirely until pairing completes
      // (only 'source' keeps a permanent server afterwards -- see
      // _startAsSource).
      _socketManager ??= _createSocketManager();
      await _configureAuth(_socketManager!);
      if (!_isLifecycleCurrent(lifecycleGeneration)) return;
      if (_socketManager!.isConnected == false) {
        try {
          await _socketManager!.startServer(peer.port, key);
          if (!_isLifecycleCurrent(lifecycleGeneration)) {
            await _socketManager!.stopServer();
            return;
          }
          _ref
              .read(connectionStatusProvider.notifier)
              .setServer(peer.port, true);
        } catch (e) {
          _logger.e('Pairing-time server start failed: $e');
        }
      }
      return;
    }

    // Paired: pure client role. Tear down any leftover pairing-time server.
    await _socketManager?.stopServer();
    if (!_isLifecycleCurrent(lifecycleGeneration)) return;
    _ref.read(connectionStatusProvider.notifier).setServer(0, false);

    // Resolved once and cached (KeyStore reads are async, but
    // PeerDiscoveryCoordinator's getPeerId/getDeviceName callbacks must be
    // sync) -- matches the old code's "only resolve once" intent, which
    // relied on _listener.isListening as an implicit guard.
    if (_selfDiscoveryId == null || _selfDiscoveryName == null) {
      _selfDiscoveryId = await KeyStore.getSelfId() ?? peer.id;
      _selfDiscoveryName =
          await KeyStore.getSelfDeviceName() ?? peer.deviceName;
      if (!_isLifecycleCurrent(lifecycleGeneration)) return;
    }
    await _peerDiscoveryCoordinator.startListening();
    if (!_isLifecycleCurrent(lifecycleGeneration)) {
      await _peerDiscoveryCoordinator.stopListening();
      return;
    }

    // Periodic retries now come from the role-agnostic _healthTimer (see
    // _init()), which calls refresh() -- this immediate attempt just
    // avoids waiting a full interval before the first try. Inlined from
    // the old _tryConnectToStoredPeer() (now deleted) since it has only
    // this one remaining call site, and routing it through
    // ReconnectScheduler would add a mandatory 2s+ delay this immediate
    // first-try attempt never had.
    if (!isSource && !state && !_connecting) {
      _reconnectScheduler.markDisconnected(schedule: false);
      _peerDiscoveryCoordinator.markDisconnected();
      final ip = _lastDiscoveredIp ?? peer.ip;
      if (ip.isEmpty || ip == 'unknown') {
        _ref
            .read(connectionStatusProvider.notifier)
            .recordConnectAttempt(ConnectionErrorCode.peerIpUnknown);
        _maybeScheduleReconnect();
        unawaited(_maybeRunFallbackScan(immediate: true));
      } else {
        await _connectTo(ip, peer.port);
      }
    }
  }

  SocketManager _createSocketManager() {
    late final SocketManager sm;
    sm = SocketManager(
      onMessage: (message) => _handleIncomingMessage(sm, message),
      onConnected: () {
        state = true;
        _reconnectScheduler.markConnected();
        _peerDiscoveryCoordinator.markConnected();
        _cancelActiveScan();
        _peerDiscoveryCoordinator.cancelActiveScan();
        _ref.read(connectionStatusProvider.notifier).clearError();
        _logger.i('Socket connected and authenticated!');
        // Source: the peer (Main) connected to us. Record its remote
        // address so Settings shows the correct peer IP and future
        // reconnects know where to find it. On Main this is a no-op
        // (it already knows the IP it connected to).
        final remote = _socketManager?.remoteAddress;
        if (remote != null && remote.isNotEmpty) {
          final peer = _peer;
          if (peer != null && peer.ip != remote) {
            _recordDiscoveredAddress(remote, peer.port);
          }
        }
        _flushQueue();
        _broadcaster.setThrottle(true);
        _peerDiscoveryCoordinator.setThrottle(true);
      },
      onDisconnected: () {
        final pairingTransport = _pairingTransport;
        if (pairingTransport != null) {
          _ref
              .read(pairingFacadeProvider.notifier)
              .handleTransportDisconnected(pairingTransport);
          _pairingTransport = null;
        }
        state = false;
        _reconnectScheduler.markDisconnected(schedule: false);
        _peerDiscoveryCoordinator.markDisconnected();
        _logger.w(
          'Socket disconnected. Will auto-reconnect when peer is reachable.',
        );
        _broadcaster.setThrottle(false);
        _peerDiscoveryCoordinator.setThrottle(false);
        _maybeScheduleReconnect();
      },
    );
    _configureAuth(sm);
    return sm;
  }

  /// Sets the auth identity (peer's public key + our Ed25519 keypair) on
  /// the socket so challenge-response authentication can run.
  Future<void> _configureAuth(SocketManager sm) async {
    final peer = _peer;
    if (peer == null) return;
    final localKeyPair = await KeyStore.getDeviceKeyPair();
    if (localKeyPair == null) return;
    sm.setAuthIdentity(
      peerPublicKeyBase64: peer.publicKey,
      localKeyPair: localKeyPair,
    );
  }

  /// Arms [_reconnectScheduler] for a backoff-timed retry, preserving the
  /// exact guard conditions the old inline scheduling logic enforced --
  /// the scheduler itself is role/state-agnostic (it just runs a timer
  /// against whatever `getPeerIp`/`getPeerPort` currently return), so
  /// every call site must gate it the same way here rather than relying on
  /// the scheduler to know when it shouldn't run.
  ///
  /// **Source guard:** Source never dials out -- it only listens. Without
  /// this guard, an onDisconnected callback on Source would schedule a
  /// reconnect -> _connectTo call on Source's own socket manager, which
  /// would flip `_isServer = false` (see SocketManager.connect) and
  /// destroy the server socket's ability to accept incoming connections.
  /// This was a root cause of the "auth timeout on 1st-2nd attempt,
  /// succeeds on 3rd" pattern: each failed reconnect attempt silently
  /// broke Source's server, and only the next incoming connection from
  /// Main eventually revived it.
  void _maybeScheduleReconnect() {
    if (!_online || _networkingStopped || _disposed) return;
    if (_peer == null || _key == null) return;
    if (isSource) return; // Source never dials out
    if (state || _connecting) return;
    _reconnectScheduler.scheduleReconnect();
  }

  Future<bool> _connectTo(
    String ip,
    int port, {
    Duration? connectTimeout,
  }) async {
    final key = _key;
    if (!_online ||
        _networkingStopped ||
        _disposed ||
        key == null ||
        _connecting ||
        state) {
      return false;
    }

    final generation = ++_connectGeneration;
    _connecting = true;
    _ref
        .read(connectionStatusProvider.notifier)
        .setDiscoveryState(
          DiscoveryState.connecting,
          detail: 'Connecting to $ip:$port...',
        );
    var shouldScheduleReconnect = false;
    var result = false;
    try {
      _socketManager ??= _createSocketManager();
      await _configureAuth(_socketManager!);
      final ok = await _socketManager!.connect(
        ip,
        port,
        key,
        connectTimeout: connectTimeout,
      );
      if (generation != _connectGeneration) {
        // A forced reconnect abandoned this attempt while it was in flight;
        // the newer attempt it triggered now owns _connecting/scheduling.
        return false;
      }
      _ref
          .read(connectionStatusProvider.notifier)
          .recordConnectAttempt(
            ok ? null : ConnectionErrorCode.connectFailed,
            errorDetail: ok ? null : '$ip:$port',
          );
      if (ok) {
        _ref
            .read(connectionStatusProvider.notifier)
            .setDiscoveryState(
              DiscoveryState.connected,
              detail: 'Connected to $ip:$port',
            );
        _rememberKnownNetwork(ip, port);
        _lastDiscoveredIp = ip;
        _recordDiscoveredAddress(ip, port);
      } else {
        _ref
            .read(connectionStatusProvider.notifier)
            .setDiscoveryState(
              DiscoveryState.failed,
              detail: 'Failed to connect to $ip:$port',
            );
        shouldScheduleReconnect = true;
      }
      result = ok;
    } catch (e) {
      if (generation == _connectGeneration) {
        _logger.e('Connection attempt failed: $e');
        _ref
            .read(connectionStatusProvider.notifier)
            .recordConnectAttempt(
              ConnectionErrorCode.connectFailed,
              errorDetail: '$ip:$port ($e)',
            );
        shouldScheduleReconnect = true;
      }
    } finally {
      if (generation == _connectGeneration) _connecting = false;
    }
    if (generation == _connectGeneration && shouldScheduleReconnect) {
      _reconnectScheduler.markDisconnected(schedule: false);
      _peerDiscoveryCoordinator.markDisconnected();
      _maybeScheduleReconnect();
    }
    return result;
  }

  /// Records "this IP worked on this subnet" for the known-network fast
  /// path (see _tryKnownNetworkFastPath). Only meaningful for Main, which
  /// is the only role that ever dials out -- Source never calls _connectTo
  /// at all, so there is nothing useful to remember on that side.
  void _rememberKnownNetwork(String ip, int port) {
    if (isSource) return;
    final peer = _peer;
    final localIp = _ref.read(connectionStatusProvider).localIp;
    final prefix = subnetPrefixOf(localIp ?? '');
    if (peer == null || prefix == null) return;
    unawaited(
      _knownNetworkDao.recordSuccess(
        peerId: peer.id,
        subnetPrefix: prefix,
        ip: ip,
        port: port,
      ),
    );
  }

  /// Fallback discovery: if the beacon and last-known-IP haven't gotten us
  /// connected for a while, actively scan the local subnet for the peer's
  /// TCP port (delegated to [_peerDiscoveryCoordinator]). Covers routers
  /// that restrict broadcast/multicast between devices even without
  /// classic AP isolation.
  ///
  /// Role/connection-state guards live here, not in the coordinator (which
  /// is role/state-agnostic, same reasoning as [_maybeScheduleReconnect]).
  /// [immediate]/[force] are forwarded as-is -- see
  /// [PeerDiscoveryCoordinator.maybeRunFallbackScan] for their meaning.
  Future<void> _maybeRunFallbackScan({
    bool immediate = false,
    bool force = false,
  }) async {
    if (!_online || _networkingStopped || _disposed || isSource) return;
    if (state || _connecting) return;

    if (await _tryKnownNetworkFastPath()) return;
    if (state || _connecting) return;

    await _peerDiscoveryCoordinator.maybeRunFallbackScan(
      immediate: immediate,
      force: force,
    );
  }

  /// Shared landing point for both beacon and fallback-scan discovery (see
  /// [PeerDiscoveryCoordinator]'s `onDiscovered` callback). [fromScan]
  /// preserves the two policies the pre-extraction code applied: a scan
  /// result is rare/expensive enough to abandon an in-flight connect
  /// attempt for; a beacon is frequent/cheap enough that it should just be
  /// skipped while an attempt is already in flight.
  Future<void> _onDiscovered(
    String ip,
    int port, {
    required bool fromScan,
  }) async {
    if (!_online || _networkingStopped || _disposed) return;
    if (!_isValidIpAddress(ip) || port < 1 || port > 65535) {
      _logger.w('Ignoring invalid discovered address $ip:$port.');
      return;
    }
    if (fromScan) {
      if (state) return;
      _lastDiscoveredIp = ip;
      if (_connecting) {
        _connectGeneration++;
        _connecting = false;
        await _socketManager?.disconnectClient();
      }
      await _connectTo(ip, port);
    } else {
      _lastDiscoveredIp = ip;
      _ref.read(connectionStatusProvider.notifier).recordBeacon(ip);
      if (!state && !_connecting) {
        await _connectTo(ip, port);
      }
    }
  }

  /// Persists a peer address discovered via beacon or subnet scan so the
  /// stored peer record, diagnostics and future reconnect attempts all agree
  /// on where the peer actually is. No-op when the address is unchanged.
  void _recordDiscoveredAddress(String ip, int port) {
    final peer = _peer;
    if (peer == null) return;
    if (ip == peer.ip && port == peer.port) return;
    _logger.i('Peer discovered at new address $ip:$port');
    final updated = peer.copyWith(ip: ip, port: port);
    _peer = updated;
    unawaited(_peerDao.update(updated));
    unawaited(_ref.read(peerFacadeProvider.notifier).applyUpdate(updated));
    _ref.read(connectionStatusProvider.notifier).setPeerIp(ip);
  }

  /// Reacts to the native onNetworkChanged event (see
  /// MirrorLineChannel.kt's NetworkCallback / onLinkPropertiesChanged),
  /// which fires on IP/subnet changes that ConnectivityService's
  /// connectivity-*type* monitoring can't see -- e.g. roaming from one WiFi
  /// network to another. Without this, the app only notices via the 90s
  /// heartbeat timeout followed by _maybeRunFallbackScan's 25s grace
  /// period -- 2+ minutes of silence. Here we already know *why* the
  /// connection may be stale, so we react immediately instead of waiting.
  ///
  /// **Fast reconnect:** runs the fallback scan with `force: true` so the
  /// 60s scan backoff doesn't block discovery after a roam, and resets
  /// ReconnectScheduler's backoff to the fast cadence via
  /// `_reconnectScheduler.forceReconnect()`. The beacon
  /// listener is un-throttled to fast cadence (3s) so a beacon from the
  /// peer lands as quickly as possible.
  /// Validates that a string is a valid IP address (IPv4 or IPv6).
  bool _isValidIpAddress(String? ip) {
    if (ip == null || ip.isEmpty) return false;
    try {
      InternetAddress(ip);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleNetworkChangedEvent(Map data) async {
    final newIp = data['localIp'] as String?;
    _logger.i('Native reported a network change (new local IP: $newIp).');
    final lifecycleGeneration = ++_lifecycleGeneration;

    if (newIp != null) {
      if (!_isValidIpAddress(newIp)) {
        _logger.w('Ignoring invalid IP from network change: $newIp');
      } else {
        _ref.read(connectionStatusProvider.notifier).setLocalIp(newIp);
      }
    }
    if (!_isLifecycleCurrent(lifecycleGeneration)) return;

    // Abandon any connect attempt that's in flight on the old network so
    // the guards (_connecting) don't silently swallow the fast reconnect
    // below -- same pattern forceReconnect()/_maybeRunFallbackScan use.
    _connectGeneration++;
    _connecting = false;
    _reconnectScheduler.pause();
    _cancelActiveScan();
    _peerDiscoveryCoordinator.cancelActiveScan();

    // Don't wait for the heartbeat timeout to notice the old socket is
    // dead -- same teardown _connectivity.onChanged's offline branch
    // already uses for the analogous "we know this connection is stale"
    // situation.
    _socketManager?.disconnectClient();
    state = false;
    _peerDiscoveryCoordinator.markDisconnected();
    // The address we last discovered belongs to the old network -- reconnect
    // must re-discover instead of hammering a dead IP for minutes.
    _lastDiscoveredIp = null;
    _broadcaster.setThrottle(false);
    _peerDiscoveryCoordinator.setThrottle(false);

    // Re-enumerate all local IPs (WiFi + VPN) BEFORE scanning so the scan
    // covers the new network's subnets (previously this was fire-and-forget
    // and the immediate scan could race it and probe the old subnet).
    final allIps = await PeerDiscovery().getAllLocalIps();
    if (!_isLifecycleCurrent(lifecycleGeneration)) return;
    _allLocalIps = allIps.map((e) => e.ip).toList();

    if (isSource) {
      // Source's beacon advertises this device's own IPs to Main -- refresh
      // them so a freshly-roamed Main learns the new address right away.
      _broadcaster.updateBroadcastInfo(ips: _allLocalIps);
      return; // server role: fast beacon is all there is to do
    }
    // Force the fallback scan immediately: bypass both the 25s grace and
    // the 60s scan backoff, since we have a concrete reason to believe the
    // network changed. The scan runs in parallel with the scheduled
    // reconnect below (which tries the stored peer IP directly).
    _maybeRunFallbackScan(immediate: true, force: true);
    // Reconnect backoff was accumulated against the old network's
    // failures; a roam is a fresh state, so reset attempts to 0 and
    // schedule immediately -- ReconnectScheduler.forceReconnect() does
    // both in one call (it also bumps the scheduler's own generation,
    // abandoning any stale scheduler-driven attempt against the old
    // network -- independent of _connectGeneration above, which guards
    // this method's own continuations, not the scheduler's).
    _reconnectScheduler.forceReconnect();
  }

  /// Fast path for reconnecting to a previously-seen network: before
  /// falling back to beacon/subnet-scan, try the IP that worked last time
  /// on this subnet (see KnownNetworkDao). Most home routers hand out the
  /// same DHCP lease repeatedly, so "returning to a known network" usually
  /// reconnects in one attempt instead of waiting on discovery.
  Future<bool> _tryKnownNetworkFastPath() async {
    if (isSource || state || _connecting) return false;
    final peer = _peer;
    if (peer == null) return false;
    final localIp = await PeerDiscovery().getLocalIp();
    final prefix = subnetPrefixOf(localIp ?? '');
    if (prefix == null) return false;
    final cachedIp = await _knownNetworkDao.lookupIp(
      peerId: peer.id,
      subnetPrefix: prefix,
    );
    if (cachedIp == null || state || _connecting) return false;
    _logger.i(
      'Known-network cache hit for $prefix.0/24 -> $cachedIp; trying fast reconnect.',
    );
    return _connectTo(cachedIp, peer.port);
  }

  /// Manually triggered reconnect: tries the last-known peer address, then
  /// falls through to the known-network cache and an active subnet scan if
  /// that didn't work. Backs the Settings "force reconnect" button so the
  /// user isn't stuck waiting on the beacon/health-timer cadence. No-op only
  /// while already connected -- the button is disabled in that state, so
  /// this is just a defensive guard, not the primary gate.
  ///
  /// Unlike the internal reconnect paths, this doesn't just bail when an
  /// attempt is already in flight -- "force" means it abandons the stuck
  /// attempt and dials again immediately, rather than silently doing
  /// nothing until it resolves on its own. It also forgets the stale
  /// discovered address and bypasses the fallback-scan backoff, because a
  /// user pressing this is explicitly telling us the normal cadence failed.
  ///
  /// **Paralel force:** Stored IP, known-network cache, and subnet scan
  /// all start at once (raced); the first to connect wins and the others
  /// are cancelled via `_connectGeneration`. This is dramatically faster
  /// than the old sequential path (5s timeout × 3 stages ≈ 15s).
  ///
  /// **Progress:** Live status is pushed into `ConnectionStatus` so the
  /// Settings UI's force-connect dialog can show what's happening:
  /// "Trying stored IP 192.168.1.42...", "Scanning subnet batch 3/11",
  /// "Connected to 192.168.1.99!".
  ///
  /// On Source (the SIM-holding device that never dials out) it isn't a
  /// no-op: it re-initializes this device's own machinery (server socket,
  /// beacon broadcaster) so a silently-dead socket or broadcaster can't keep
  /// blocking Main's incoming reconnect attempts.
  Future<void> forceReconnect() async {
    if (!_online || state || _forceConnecting) return;
    _forceConnecting = true;
    final statusNotifier = _ref.read(connectionStatusProvider.notifier);
    statusNotifier.beginForceConnect();
    var mainRecoveryPaused = false;
    try {
      _networkingStopped = false;
      final lifecycleGeneration = ++_lifecycleGeneration;
      _reconnectScheduler.start();
      if (isSource) {
        statusNotifier.logDiscovery(
          'Re-initializing source device (server + beacon)...',
        );
        _lastDiscoveredIp = null;
        await _socketManager?.disconnectClient();
        if (!_isLifecycleCurrent(lifecycleGeneration)) return;
        await _broadcaster.stop();
        if (!_isLifecycleCurrent(lifecycleGeneration)) return;
        await _peerDiscoveryCoordinator.stopListening();
        if (!_isLifecycleCurrent(lifecycleGeneration)) return;
        await _refresh();
        if (!_isLifecycleCurrent(lifecycleGeneration)) return;
        statusNotifier.logDiscovery('Source device ready.', isSuccess: true);
        return;
      }

      _reconnectScheduler.pause();
      mainRecoveryPaused = true;
      _cancelActiveScan();
      _peerDiscoveryCoordinator.cancelActiveScan();
      if (_connecting) {
        _connectGeneration++;
        _connecting = false;
        await _socketManager?.disconnectClient();
        statusNotifier.logDiscovery('Cancelled previous attempt.');
      }
      _lastDiscoveredIp = null;
      await _parallelForceConnect(statusNotifier);
    } finally {
      if (mainRecoveryPaused &&
          _online &&
          !state &&
          !_networkingStopped &&
          !_disposed) {
        _reconnectScheduler.forceReconnect();
      }
      statusNotifier.endForceConnect();
      _forceConnecting = false;
    }
  }

  /// Races the three discovery paths in parallel to find candidate IPs,
  /// then tries connecting to them sequentially (fastest candidate first)
  /// until one succeeds. Updates [statusNotifier] with live progress.
  ///
  /// **Why discovery is parallel but connect is sequential:** `_connectTo`
  /// uses a single shared SocketManager with a `_connecting` guard, so
  /// two concurrent `_connectTo` calls would collide. Instead, we race
  /// only the *discovery* (finding which IPs to try), then connect to the
  /// discovered candidates one at a time. This is still much faster than
  /// the old sequential path because the slow subnet scan runs in
  /// parallel with the stored-IP and known-network lookups instead of
  /// only starting after they fail.
  Future<void> _parallelForceConnect(
    ConnectionStatusNotifier statusNotifier,
  ) async {
    final peer = _peer;
    final key = _key;
    if (peer == null || key == null) {
      statusNotifier.logDiscovery('No peer configured.', isError: true);
      return;
    }

    final localIp = _ref.read(connectionStatusProvider).localIp;

    final strategy = ForceConnectStrategy(
      storedIp: peer.ip,
      beaconIps: _peerDiscoveryCoordinator.beaconIps,
      allLocalIps: _allLocalIps,
      localIp: localIp,
      peerId: peer.id,
      peerPort: peer.port,
      connectWithProgress: _connectWithProgress,
      lookupKnownNetworkIp: _lookupKnownNetworkIp,
      scanSubnetsWithProgress: _scanSubnetsWithProgress,
      recordDiscoveredAddress: _recordDiscoveredAddress,
    );

    await strategy.execute(statusNotifier, () => state, () => _connecting);
  }

  /// Looks up the known-network cached IP for this subnet.
  Future<List<String>> _lookupKnownNetworkIp(
    ConnectionStatusNotifier statusNotifier,
    String peerId,
  ) async {
    final localIp = await PeerDiscovery().getLocalIp();
    final prefix = subnetPrefixOf(localIp ?? '');
    if (prefix == null) return [];
    final cachedIp = await _knownNetworkDao.lookupIp(
      peerId: peerId,
      subnetPrefix: prefix,
    );
    if (cachedIp == null) {
      statusNotifier.logDiscovery(
        'Known-network: no cached IP for $prefix.0/24.',
      );
      return [];
    }
    statusNotifier.logDiscovery('Known-network cache hit: $cachedIp');
    return [cachedIp];
  }

  /// Wraps `_connectTo` with progress logging. Returns true on success.
  /// [connectTimeout] shortens the TCP connect timeout -- used in
  /// force-connect to avoid waiting 5s on a stale stored IP before trying
  /// the next candidate from the scan.
  Future<bool> _connectWithProgress(
    String ip,
    int port,
    ConnectionStatusNotifier statusNotifier, {
    required String label,
    Duration? connectTimeout,
  }) async {
    statusNotifier.setDiscoveryState(
      DiscoveryState.connecting,
      detail: 'Trying $label...',
    );
    statusNotifier.logDiscovery('Trying $label...');
    final ok = await _connectTo(ip, port, connectTimeout: connectTimeout);
    if (ok) {
      statusNotifier.setDiscoveryState(
        DiscoveryState.connected,
        detail: 'Connected to $ip',
      );
    }
    return ok;
  }

  /// Multi-subnet scan (VPN support): scans all local subnets in parallel.
  /// Returns the first responsive host across all subnets.
  Future<String?> _scanSubnetsWithProgress(
    List<String> localIps,
    int port,
    ConnectionStatusNotifier statusNotifier,
  ) async {
    if (isSource || state || _connecting || _scanning) return null;
    if (localIps.isEmpty) return null;
    _scanning = true;
    final cancellation = ScanCancellationToken();
    _scanCancellation = cancellation;
    statusNotifier.setDiscoveryState(
      DiscoveryState.scanningSubnet,
      detail: 'Scanning ${localIps.length} subnets...',
    );
    statusNotifier.logDiscovery(
      'Scanning ${localIps.length} subnets: ${localIps.join(', ')}',
    );
    try {
      final found = await _scanner.findHostWithOpenPortMulti(
        localIps: localIps,
        port: port,
        cancellationToken: cancellation,
        onProgress: (batch, total, subnet) {
          if (cancellation.isCancelled) return;
          statusNotifier.setDiscoveryState(
            DiscoveryState.scanningSubnet,
            detail: 'Scanning $subnet.0/24 (batch $batch/$total)',
          );
          if (batch == 1 || batch % 3 == 0) {
            statusNotifier.logDiscovery(
              'Scanning $subnet.0/24 ($batch/$total)...',
            );
          }
        },
      );
      if (found != null && !cancellation.isCancelled) {
        statusNotifier.logDiscovery('Scan found host: $found', isSuccess: true);
      }
      return found;
    } finally {
      if (identical(_scanCancellation, cancellation)) {
        _scanCancellation = null;
        _scanning = false;
      }
    }
  }

  void _cancelActiveScan() {
    _scanCancellation?.cancel();
    _scanCancellation = null;
    _scanning = false;
  }

  // ---------------------------------------------------------------------
  // Telephony events (source device only)
  // ---------------------------------------------------------------------

  void _registerTelephonyHandler() {
    if (_telephonyHandlerRegistered) return;
    _telephonyHandlerRegistered = true;

    _clearTelephonyHandler = TelephonyChannel.setEventHandler((
      type,
      data,
    ) async {
      if (type == 'onNetworkChanged') {
        _handleNetworkChangedEvent(data);
        return;
      }
      if (!isSource) return;
      final now = DateTime.now();
      final id = const Uuid().v4();

      if (type == 'onCall') {
        await _ref
            .read(callFacadeProvider.notifier)
            .handleNativeEvent(data, id: id, now: now);
      } else if (type == 'onSms') {
        await _ref
            .read(smsFacadeProvider.notifier)
            .handleNativeEvent(data, id: id, now: now);
      } else if (type == 'onSmsSent' || type == 'onSmsDelivered') {
        final operationId = data['operationId'] as String?;
        if (operationId != null) {
          await _ref
              .read(smsFacadeProvider.notifier)
              .handleSmsResult(
                operationId,
                sent: type == 'onSmsSent',
                success: data['success'] == true,
              );
        }
      } else if (type == 'onNotification') {
        await _ref
            .read(notificationFacadeProvider.notifier)
            .handleNativeEvent(data, id: id, now: now);
      } else if (type == 'onNotificationRemoved') {
        await _ref
            .read(notificationFacadeProvider.notifier)
            .handleNativeRemoval(data);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Incoming peer messages
  // ---------------------------------------------------------------------

  Future<void> _handleIncomingMessage(
    SocketManager socketManager,
    MirrorMessage message,
  ) async {
    final sessionGeneration = socketManager.sessionGeneration;
    if (sessionGeneration == null) return;

    final decrypted = await socketManager.decryptMessage(message);
    if (!socketManager.isSessionCurrent(sessionGeneration)) return;
    if (decrypted == null) {
      _logger.e('Decryption failed for message: ${message.id}');
      return;
    }

    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final now = DateTime.now();
    final sourcePeerId = message.sourcePeerId;
    if (sourcePeerId == null) return;
    final receivedAt = DateTime.now();
    final record = InboxRecord(
      sourcePeerId: sourcePeerId,
      messageId: message.id,
      type: message.type,
      receivedAt: receivedAt,
      updatedAt: receivedAt,
    );
    final isDomainMessage = {
      MessageTypes.callIncoming,
      MessageTypes.callRejected,
      MessageTypes.callStatus,
      MessageTypes.callInfo,
      MessageTypes.smsIncoming,
      MessageTypes.smsOutgoing,
      MessageTypes.smsStatus,
      MessageTypes.notificationMirrored,
      MessageTypes.notificationRemoved,
    }.contains(message.type);

    if (isDomainMessage) {
      var isNewMessage = false;
      final database = await AppDatabase.instance.database;
      await database.transaction((transaction) async {
        isNewMessage = await _inbox.insertIfAbsentOn(transaction, record);
        if (isNewMessage) {
          await _dispatchIncomingMessage(
            message,
            payload,
            now,
            transaction: transaction,
          );
        }
      });
      if (!isNewMessage) {
        _logger.i('Skipping duplicate Inbox message: ${message.id}');
        return;
      }
      // Facade handlers perform UI and platform work only after the durable
      // Inbox/domain transaction has successfully committed.
      await _dispatchIncomingMessage(
        message,
        payload,
        now,
        alreadyPersisted: true,
      );
      if (message.type == MessageTypes.smsOutgoing) {
        await _ref
            .read(smsFacadeProvider.notifier)
            .executeOutgoingSms(message.id);
      }
      if (message.type == MessageTypes.callRejected) {
        await _ref
            .read(callFacadeProvider.notifier)
            .executeCallReject(message.id);
      }
      await _sendDeliveryAck(socketManager, message.id);
      return;
    }

    final isNewMessage = await _inbox.insertIfAbsent(record);
    if (!isNewMessage) {
      _logger.i('Skipping duplicate Inbox message: ${message.id}');
      return;
    }
    await _dispatchIncomingMessage(message, payload, now);
  }

  Future<void> _sendDeliveryAck(
    SocketManager socketManager,
    String messageId,
  ) async {
    final sent = await socketManager.sendMessage(MessageTypes.ack, {
      'message_id': messageId,
      'result': 'committed',
    });
    if (!sent) {
      _logger.w('Could not send delivery ACK for message $messageId.');
    }
  }

  Future<void> _dispatchIncomingMessage(
    MirrorMessage message,
    Map<String, dynamic> payload,
    DateTime now, {
    Transaction? transaction,
    bool alreadyPersisted = false,
  }) async {
    switch (message.type) {
      case MessageTypes.callIncoming:
      case MessageTypes.callRejected:
      case MessageTypes.callStatus:
      case MessageTypes.callInfo:
        await _ref
            .read(callFacadeProvider.notifier)
            .handleIncomingMessage(
              message.type,
              payload,
              message,
              now,
              transaction: transaction,
              alreadyPersisted: alreadyPersisted,
            );
        break;

      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
      case MessageTypes.smsStatus:
        await _ref
            .read(smsFacadeProvider.notifier)
            .handleIncomingMessage(
              message.type,
              payload,
              message,
              now,
              transaction: transaction,
              alreadyPersisted: alreadyPersisted,
            );
        break;

      case MessageTypes.ack:
        final acknowledgedId = payload['message_id'] as String?;
        final result = payload['result'] as String?;
        if (acknowledgedId != null && result == 'committed') {
          await _queue.markAcknowledged(
            acknowledgedId,
            destinationPeerId: _peer?.id,
          );
          _logger.i('Committed ACK received: $acknowledgedId');
        }
        break;

      case MessageTypes.notificationMirrored:
      case MessageTypes.notificationRemoved:
        await _ref
            .read(notificationFacadeProvider.notifier)
            .handleIncomingMessage(
              message.type,
              payload,
              message,
              now,
              transaction: transaction,
              alreadyPersisted: alreadyPersisted,
            );
        break;

      case MessageTypes.pairingRequest:
        _logger.i('pairingRequest received from scanner.');
        final transport = pairingTransport;
        if (transport != null) {
          await _ref
              .read(pairingFacadeProvider.notifier)
              .handleIncomingRequest(transport, payload);
        }
        break;

      case MessageTypes.pairingAck:
        _logger.i('pairingAck received — scanner persisted its end.');
        // Scanned side: the scanner confirmed it persisted its own end --
        // arrives on this device's regular socket (unlike pairingAccept/
        // pairingReject below, which the *scanner* receives on its own
        // separate handshake socket, never here).
        final transport = pairingTransport;
        if (transport != null) {
          _ref
              .read(pairingFacadeProvider.notifier)
              .handlePairingAck(transport, payload);
        }
        break;

      case MessageTypes.pairingAccept:
      case MessageTypes.pairingReject:
      case MessageTypes.pairingComplete:
      case MessageTypes.pairingAbort:
        // Handled by PairingFacade's own socket on the scanner side.
        // On the scanned side we never receive these (we send them).
        break;

      default:
        _logger.i('Unknown message type: ${message.type}');
    }
  }

  Future<void> _notify({
    required int id,
    required String title,
    required String body,
    NotificationPayload? payload,
  }) async {
    try {
      // Android notification ids must fit in a 32-bit int.
      final safeId = id & 0x7fffffff;
      await NotificationService.show(
        id: safeId,
        title: title,
        body: body,
        payload: payload,
      );
    } catch (e) {
      _logger.e('Notification failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Outgoing messages (with offline queue)
  // ---------------------------------------------------------------------

  Future<bool> _sendOrQueue(String type, Map<String, dynamic> payload) async {
    final destinationPeerId = _peer?.id;
    if (destinationPeerId == null) {
      _logger.w('$type could not be queued without a destination peer.');
      return false;
    }

    // Persist before transport so a process or socket failure cannot lose the
    // operation between the send decision and the socket write.
    final item = await _queue.enqueue(
      type,
      jsonEncode(payload),
      destinationPeerId: destinationPeerId,
    );
    final sent =
        await _socketManager?.sendMessage(
          type,
          payload,
          messageId: item.messageId,
        ) ??
        false;
    if (sent && item.id != null) await _queue.markSent(item.id!);
    if (!sent) _logger.w('$type queued for later delivery.');
    return sent;
  }

  /// Public entry points to [_sendOrQueue]/[_notify] -- CallFacade/SmsFacade
  /// are constructed from their own top-level providers (not from within
  /// this constructor), so unlike the pre-#39 CallEventHandler/
  /// SmsEventHandler they can't tear off the private methods directly
  /// (Dart privacy is per-file). Same underlying implementation either way.
  Future<bool> sendOrQueue(String type, Map<String, dynamic> payload) =>
      _sendOrQueue(type, payload);

  Future<bool> sendOrQueueWithMutation(
    String type,
    Map<String, dynamic> payload,
    DomainMutation mutation,
  ) async {
    final destinationPeerId = _peer?.id;
    if (destinationPeerId == null) return false;
    final database = await AppDatabase.instance.database;
    late QueueItem item;
    await database.transaction((transaction) async {
      await mutation(transaction);
      item = await _queue.enqueueOnDatabase(
        transaction,
        type,
        jsonEncode(payload),
        destinationPeerId: destinationPeerId,
      );
    });
    final sent =
        await _socketManager?.sendMessage(
          type,
          payload,
          messageId: item.messageId,
        ) ??
        false;
    if (sent && item.id != null) await _queue.markSent(item.id!);
    return sent;
  }

  Future<void> notify({
    required int id,
    required String title,
    required String body,
    NotificationPayload? payload,
  }) => _notify(id: id, title: title, body: body, payload: payload);

  Future<bool> sendCallNotification(
    String number, {
    String? id,
    String? contactName,
  }) => _ref
      .read(callFacadeProvider.notifier)
      .sendCallNotification(number, id: id, contactName: contactName);

  Future<bool> sendCallRejected(String callId) =>
      _ref.read(callFacadeProvider.notifier).sendCallRejected(callId);

  Future<bool> sendSmsNotification(String address, String body, {String? id}) =>
      _ref
          .read(smsFacadeProvider.notifier)
          .sendSmsNotification(address, body, id: id);

  Future<void> _flushQueue() async {
    await _flushGate.run(_flushQueueWorker);
  }

  Future<void> _flushQueueWorker() async {
    final socketManager = _socketManager;
    final sessionGeneration = socketManager?.sessionGeneration;
    final destinationPeerId = _peer?.id;
    if (socketManager == null ||
        sessionGeneration == null ||
        destinationPeerId == null) {
      return;
    }
    final items = await _queue.pendingItems(destinationPeerId);
    if (items.isEmpty) return;
    _logger.i('Flushing ${items.length} queued message(s).');
    for (final item in items) {
      if (_socketManager != socketManager ||
          socketManager.sessionGeneration != sessionGeneration) {
        _logger.i('Stopping stale Outbox worker after session change.');
        return;
      }
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        final sent = await socketManager.sendMessage(
          item.type,
          payload,
          messageId: item.messageId,
        );
        if (sent) {
          if (item.id != null) await _queue.markSent(item.id!);
        } else {
          if (item.id != null) await _onQueueItemFailed(item);
          break;
        }
      } catch (e) {
        _logger.e('Failed to flush queue item ${item.id}: $e');
        if (item.id != null) await _onQueueItemFailed(item);
      }
    }
  }

  /// Records a failed transport attempt without changing domain state.
  Future<void> _onQueueItemFailed(QueueItem item) async {
    final dropped = await _queue.markFailed(item.id!, item.retryCount);
    if (dropped) {
      _logger.w('Outbox item ${item.messageId} moved to dead letter.');
    }
  }

  // ---------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------

  Future<void> _stopMachinery() async {
    // _healthTimer deliberately keeps running (not cancelled here) -- it's
    // a session-long self-healing loop, not tied to pairing state. If a
    // user pairs again later, its next tick picks the new peer straight
    // back up; cancelling it here would permanently disable self-healing
    // for the rest of the app session (it's only ever created once, in
    // _init()).
    _networkingStopped = true;
    _lifecycleGeneration++;
    _reconnectScheduler.stop();
    _cancelActiveScan();
    _peerDiscoveryCoordinator.cancelActiveScan();
    _connectGeneration++;
    _connecting = false;
    await _disableNativeMirroring();
    await _broadcaster.stop();
    await _peerDiscoveryCoordinator.stopListening();
    await _socketManager?.disconnect();
    _socketManager = null;
    _lastDiscoveredIp = null;
    state = false;
    _ref.read(connectionStatusProvider.notifier).setServer(0, false);
  }

  Future<void> _disableNativeMirroring() async {
    final role = _mirroringRole(_peer?.role);
    await _markNativeEventsNotReady();
    try {
      await TelephonyChannel.syncMirroringEligibility(
        enabled: false,
        role: role,
        paired: false,
      );
    } catch (e) {
      _logger.e('Failed to disable native mirroring eligibility: $e');
    }
    try {
      final result = await TelephonyChannel.stopListening(
        enabled: false,
        role: role,
        paired: false,
      );
      if (result.outcome == MirroringServiceOutcome.failed) {
        _logger.e('Native mirroring service stop failed: ${result.error}');
      }
    } catch (e) {
      _logger.e('Failed to stop native mirroring service: $e');
    }
  }

  Future<void> _markNativeEventsNotReady() async {
    try {
      await TelephonyChannel.nativeEventsNotReady();
    } catch (e) {
      _logger.e('Failed to mark native events not ready: $e');
    }
  }

  /// Stops networking (e.g. after device reset).
  Future<void> stopAll() => _stopMachinery();

  /// Clears the offline queue of pending peer messages. Used by the reset
  /// flow so stale `call_status` / `sms_status` messages from before the
  /// reset aren't delivered to the peer after a fresh pairing. Routed
  /// through the facade (not the QueueService directly) so the UI service
  /// layer stays decoupled from the queue's implementation.
  Future<void> clearQueue() async {
    await _queue.clear();
    _logger.i('Offline queue cleared.');
  }

  Future<void> disconnect() async {
    _networkingStopped = true;
    _lifecycleGeneration++;
    _reconnectScheduler.stop();
    _cancelActiveScan();
    _peerDiscoveryCoordinator.cancelActiveScan();
    _connectGeneration++;
    _connecting = false;
    await _socketManager?.disconnectClient();
    state = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycleGeneration++;
    _clearTelephonyHandler?.call();
    _clearTelephonyHandler = null;
    _telephonyHandlerRegistered = false;
    unawaited(_markNativeEventsNotReady());
    WidgetsBinding.instance.removeObserver(this);
    _connectivity.stopListening();
    _healthTimer?.cancel();
    _reconnectScheduler.dispose();
    _cancelActiveScan();
    _broadcaster.stop();
    _peerDiscoveryCoordinator.dispose();
    _socketManager?.disconnect();
    super.dispose();
  }
}
