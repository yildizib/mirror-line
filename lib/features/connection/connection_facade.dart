import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/known_network_dao.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/network/lan_beacon.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/peer_discovery.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:mirrorline/core/services/connectivity_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/queue_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/connection/force_connect_strategy.dart';
import 'package:mirrorline/features/connection/peer_discovery_coordinator.dart';
import 'package:mirrorline/features/connection/reconnect_scheduler.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/pairing/pairing_facade.dart';
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

/// Shows (or replaces, by id) a local notification.
typedef ShowNotification =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      NotificationPayload? payload,
    });

final connectionFacadeProvider = StateNotifierProvider<ConnectionFacade, bool>((
  ref,
) {
  return ConnectionFacade(ref);
});

final connectionConnectingProvider = Provider<bool>((ref) {
  return ref.watch(connectionFacadeProvider.notifier).isConnecting;
});

class ConnectionFacade extends StateNotifier<bool> with WidgetsBindingObserver {
  // How long an outgoing SMS may sit on 'pending' before it's given up on
  // and shown as 'failed'. The queue's own 5-attempt retry only advances
  // when the connection actually comes back up (see _flushQueue), so if
  // the peer never reconnects a queued sms_status ack would otherwise
  // never get marked either way -- this is a connection-state-independent
  // backstop so "Gönderiliyor" doesn't linger forever.
  final Logger _logger = Logger();
  final Ref _ref;
  final ConnectivityService _connectivity = ConnectivityService();
  final PeerDao _peerDao = PeerDao();
  final KnownNetworkDao _knownNetworkDao = KnownNetworkDao();
  final QueueService _queue = QueueService();
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
  Peer? _peer;
  SecretKey? _key;
  Timer? _healthTimer;
  bool _connecting = false;
  bool _refreshing = false;
  bool _scanning = false;
  bool _telephonyHandlerRegistered = false;
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
  // Guards against an active on-path attacker (e.g. ARP spoofing into an
  // already-authenticated TCP session) replaying a previously captured,
  // genuinely valid encrypted message to make the app act on it a second
  // time -- GCM's auth tag proves *who* encrypted a message but not that
  // it's fresh. Reset per connection (see onConnected below); a brand new
  // connection already requires a fresh signed challenge-response, so an
  // attacker without the identity key can't replay their way into a new
  // session -- this only needs to cover replay within one live session.
  int? _lastAcceptedMessageTimestamp;
  bool _disposed = false;

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

  /// Exposed so PairingFacade can reply on the live connection.
  SocketManager? get socketManager => _socketManager;

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
      if (isOnline) {
        _logger.i('Network back online. Reconnecting...');
        refresh();
        _maybeScheduleReconnect();
      } else {
        _logger.i(
          'Network offline. Dropping stale connection, pausing attempts.',
        );
        state = false;
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
      final isOnline = await _connectivity.isOnline();
      if (isOnline) {
        await refresh();
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
    _healthTimer ??= Timer.periodic(SecurityConstants.reconnectInterval, (_) {
      _ref
          .read(smsFacadeProvider.notifier)
          .failStalePending(SecurityConstants.pendingSmsTimeout);
      if (_connecting || state) return;
      refresh();
      _maybeRunFallbackScan();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _socketManager?.setBackgroundMode(false);
      refresh();
      _maybeScheduleReconnect();
    } else if (state == AppLifecycleState.paused) {
      _socketManager?.setBackgroundMode(true);
    }
  }

  /// Reloads peer info and (re)starts role-specific networking machinery.
  /// Call after pairing, role changes or resets, and also called
  /// periodically by _healthTimer as a self-healing check.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      try {
        _peer = await _peerDao.getPeer();
        _key = await KeyStore.getPeerKey();
      } catch (e) {
        _logger.e('Failed to load peer info: $e');
        return;
      }

      final statusNotifier = _ref.read(connectionStatusProvider.notifier);
      // Use getAllLocalIps for VPN support: collects WiFi + VPN TUN + etc.
      final allIps = await PeerDiscovery().getAllLocalIps();
      _allLocalIps = allIps.map((e) => e.ip).toList();
      statusNotifier.setLocalIp(allIps.isNotEmpty ? allIps.first.ip : null);
      statusNotifier.setPeerIp(_peer?.ip);

      if (_peer == null || _key == null) {
        _logger.w('No peer info or key found. Waiting for pairing.');
        await _stopMachinery();
        return;
      }

      try {
        if (isSource) {
          await _startAsSource();
        } else {
          await _startAsMain();
        }
      } catch (e) {
        _logger.e('Failed to start networking: $e');
      }
    } finally {
      _refreshing = false;
    }
  }

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

  Future<void> _startAsSource() async {
    final peer = _peer!;
    final key = _key!;

    _socketManager ??= _createSocketManager();
    await _configureAuth(_socketManager!);
    if (_socketManager!.isConnected == false) {
      try {
        await _socketManager!.startServer(peer.port, key);
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
      // Include all local IPs (WiFi + VPN) in the beacon so the receiver
      // can try them all if the UDP source IP is unreachable.
      final allIps = _allLocalIps.isNotEmpty ? _allLocalIps : null;
      await _broadcaster.start(
        peerId: selfId,
        tcpPort: peer.port,
        deviceName: selfName,
        ips: allIps,
      );
    }

    try {
      await TelephonyChannel.startListening();
    } catch (e) {
      _logger.e('Telephony startListening failed: $e');
    }
    _logger.i(
      'Source mode active: server on ${peer.port}, beacon broadcasting.',
    );
  }

  Future<void> _startAsMain() async {
    final peer = _peer!;
    final key = _key!;
    final isPaired = peer.publicKey.isNotEmpty;

    if (!isPaired) {
      // Not yet paired to a specific device: also listen on our own port,
      // exactly like 'source' always does, so a QR scan works regardless
      // of who scans whom. There's no real peer to dial out to yet, so
      // skip the client/beacon machinery entirely until pairing completes
      // (only 'source' keeps a permanent server afterwards -- see
      // _startAsSource).
      _socketManager ??= _createSocketManager();
      await _configureAuth(_socketManager!);
      if (_socketManager!.isConnected == false) {
        try {
          await _socketManager!.startServer(peer.port, key);
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
    _ref.read(connectionStatusProvider.notifier).setServer(0, false);

    // Resolved once and cached (KeyStore reads are async, but
    // PeerDiscoveryCoordinator's getPeerId/getDeviceName callbacks must be
    // sync) -- matches the old code's "only resolve once" intent, which
    // relied on _listener.isListening as an implicit guard.
    if (_selfDiscoveryId == null || _selfDiscoveryName == null) {
      _selfDiscoveryId = await KeyStore.getSelfId() ?? peer.id;
      _selfDiscoveryName =
          await KeyStore.getSelfDeviceName() ?? peer.deviceName;
    }
    await _peerDiscoveryCoordinator.startListening();

    // Periodic retries now come from the role-agnostic _healthTimer (see
    // _init()), which calls refresh() -- this immediate attempt just
    // avoids waiting a full interval before the first try. Inlined from
    // the old _tryConnectToStoredPeer() (now deleted) since it has only
    // this one remaining call site, and routing it through
    // ReconnectScheduler would add a mandatory 2s+ delay this immediate
    // first-try attempt never had.
    if (!isSource && !state && !_connecting) {
      final ip = _lastDiscoveredIp ?? peer.ip;
      if (ip.isEmpty || ip == 'unknown') {
        _ref
            .read(connectionStatusProvider.notifier)
            .recordConnectAttempt(ConnectionErrorCode.peerIpUnknown);
      } else {
        await _connectTo(ip, peer.port);
      }
    }
  }

  SocketManager _createSocketManager() {
    final sm = SocketManager(
      onMessage: _handleIncomingMessage,
      onConnected: () {
        state = true;
        _reconnectScheduler.markConnected();
        _peerDiscoveryCoordinator.markConnected();
        _lastAcceptedMessageTimestamp = null;
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
        state = false;
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
    sm.requireAuthIdentity();
    final localKeyPair = await KeyStore.getDeviceKeyPair();
    if (localKeyPair == null) return;
    final localDeviceId = await KeyStore.getSelfId();
    sm.setAuthIdentity(
      peerPublicKeyBase64: peer.publicKey,
      localKeyPair: localKeyPair,
      localDeviceId: localDeviceId ?? '',
      peerDeviceId: peer.id,
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
    if (key == null || _connecting || state) return false;

    final generation = ++_connectGeneration;
    _connecting = true;
    _ref
        .read(connectionStatusProvider.notifier)
        .setDiscoveryState(
          DiscoveryState.connecting,
          detail: 'Connecting to $ip:$port...',
        );
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
        return ok;
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
      } else {
        _ref
            .read(connectionStatusProvider.notifier)
            .setDiscoveryState(
              DiscoveryState.failed,
              detail: 'Failed to connect to $ip:$port',
            );
        _maybeScheduleReconnect();
      }
      return ok;
    } finally {
      if (generation == _connectGeneration) _connecting = false;
    }
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
    if (isSource) return; // only Main ever dials out
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
    if (fromScan) {
      if (state) return;
      _lastDiscoveredIp = ip;
      _recordDiscoveredAddress(ip, port);
      if (_connecting) {
        _connectGeneration++;
        _connecting = false;
        await _socketManager?.disconnectClient();
      }
      await _connectTo(ip, port);
    } else {
      _lastDiscoveredIp = ip;
      _ref.read(connectionStatusProvider.notifier).recordBeacon(ip);
      _recordDiscoveredAddress(ip, port);
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
    _ref.read(peerFacadeProvider.notifier).applyUpdate(updated);
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

    if (newIp != null) {
      if (!_isValidIpAddress(newIp)) {
        _logger.w('Ignoring invalid IP from network change: $newIp');
      } else {
        _ref.read(connectionStatusProvider.notifier).setLocalIp(newIp);
      }
    }

    // Abandon any connect attempt that's in flight on the old network so
    // the guards (_connecting) don't silently swallow the fast reconnect
    // below -- same pattern forceReconnect()/_maybeRunFallbackScan use.
    _connectGeneration++;
    _connecting = false;

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
    if (state) return;
    final statusNotifier = _ref.read(connectionStatusProvider.notifier);
    statusNotifier.beginForceConnect();

    if (isSource) {
      statusNotifier.logDiscovery(
        'Re-initializing source device (server + beacon)...',
      );
      _lastDiscoveredIp = null;
      await _socketManager?.disconnectClient();
      await _broadcaster.stop();
      await _peerDiscoveryCoordinator.stopListening();
      await refresh();
      statusNotifier.logDiscovery('Source device ready.', isSuccess: true);
      statusNotifier.endForceConnect();
      return;
    }

    // Abandon any in-flight attempt so the parallel race below owns the
    // generation and the busy guards.
    if (_connecting) {
      _connectGeneration++;
      _connecting = false;
      await _socketManager?.disconnectClient();
      statusNotifier.logDiscovery('Cancelled previous attempt.');
    }
    _lastDiscoveredIp = null;

    await _parallelForceConnect(statusNotifier);
    statusNotifier.endForceConnect();
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
        onProgress: (batch, total, subnet) {
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
      if (found != null) {
        statusNotifier.logDiscovery('Scan found host: $found', isSuccess: true);
      }
      return found;
    } finally {
      _scanning = false;
    }
  }

  // ---------------------------------------------------------------------
  // Telephony events (source device only)
  // ---------------------------------------------------------------------

  void _registerTelephonyHandler() {
    if (_telephonyHandlerRegistered) return;
    _telephonyHandlerRegistered = true;

    TelephonyChannel.setEventHandler((type, data) async {
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

  void _handleIncomingMessage(MirrorMessage message) async {
    final key = _key;
    if (key == null) return;

    final metadata = CryptoManager.canonicalMessageMetadata(
      version: message.protocolVersion,
      type: message.type,
      id: message.id,
      timestamp: message.timestamp,
    );
    final decrypted = await CryptoManager.decryptWithAad(
      key,
      message.payload,
      aad: utf8.encode(metadata),
    );
    if (decrypted == null) {
      _logger.e('Decryption failed for message: ${message.id}');
      return;
    }

    // Reject a message with a timestamp at or before the last one we
    // accepted on this connection -- a genuinely valid (correctly
    // decrypted) message can still be a replayed copy of a real one an
    // on-path attacker captured earlier. Strictly-less-than (not <=) so a
    // legitimate burst of messages constructed within the same
    // millisecond -- e.g. _flushQueue draining several queued items --
    // is never mistaken for a replay.
    final lastAccepted = _lastAcceptedMessageTimestamp;
    if (lastAccepted != null && message.timestamp < lastAccepted) {
      _logger.w(
        'Rejected likely-replayed message: ${message.id} (type=${message.type})',
      );
      return;
    }
    _lastAcceptedMessageTimestamp = message.timestamp;

    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final now = DateTime.now();

    switch (message.type) {
      case MessageTypes.callIncoming:
      case MessageTypes.callRejected:
      case MessageTypes.callStatus:
      case MessageTypes.callInfo:
        await _ref
            .read(callFacadeProvider.notifier)
            .handleIncomingMessage(message.type, payload, message, now);
        break;

      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
      case MessageTypes.smsStatus:
        await _ref
            .read(smsFacadeProvider.notifier)
            .handleIncomingMessage(message.type, payload, message, now);
        break;

      case MessageTypes.ack:
        _logger.i('ACK received: ${message.id}');
        break;

      case MessageTypes.notificationMirrored:
      case MessageTypes.notificationRemoved:
        await _ref
            .read(notificationFacadeProvider.notifier)
            .handleIncomingMessage(message.type, payload, message, now);
        break;

      case MessageTypes.pairingRequest:
        _logger.i('pairingRequest received from scanner.');
        _ref
            .read(pairingFacadeProvider.notifier)
            .handleIncomingRequest(payload);
        break;

      case MessageTypes.pairingAck:
        _logger.i('pairingAck received — scanner persisted its end.');
        // Scanned side: the scanner confirmed it persisted its own end --
        // arrives on this device's regular socket (unlike pairingAccept/
        // pairingReject below, which the *scanner* receives on its own
        // separate handshake socket, never here).
        _ref.read(pairingFacadeProvider.notifier).handlePairingAck();
        break;

      case MessageTypes.pairingAccept:
      case MessageTypes.pairingReject:
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
    final sent = await _socketManager?.sendMessage(type, payload) ?? false;
    if (!sent) {
      await _queue.enqueue(type, jsonEncode(payload));
      _logger.w('$type queued for later delivery.');
    }
    return sent;
  }

  /// Public entry points to [_sendOrQueue]/[_notify] -- CallFacade/SmsFacade
  /// are constructed from their own top-level providers (not from within
  /// this constructor), so unlike the pre-#39 CallEventHandler/
  /// SmsEventHandler they can't tear off the private methods directly
  /// (Dart privacy is per-file). Same underlying implementation either way.
  Future<bool> sendOrQueue(String type, Map<String, dynamic> payload) =>
      _sendOrQueue(type, payload);

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

  Future<bool> sendReplySms(
    String address,
    String body, {
    String? id,
    String? contactName,
    String? threadId,
  }) => _ref
      .read(smsFacadeProvider.notifier)
      .sendReplySms(
        address,
        body,
        id: id,
        contactName: contactName,
        threadId: threadId,
      );

  Future<void> _flushQueue() async {
    final items = await _queue.pendingItems();
    if (items.isEmpty) return;
    _logger.i('Flushing ${items.length} queued message(s).');
    for (final item in items) {
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        final sent =
            await _socketManager?.sendMessage(item.type, payload) ?? false;
        if (sent) {
          if (item.id != null) await _queue.markSent(item.id!);
        } else {
          if (item.id != null) await _onQueueItemFailed(item, payload);
          break;
        }
      } catch (e) {
        _logger.e('Failed to flush queue item ${item.id}: $e');
        if (item.id != null) await _onQueueItemFailed(item, null);
      }
    }
  }

  /// Records a failed send attempt; if that was the last retry (item
  /// permanently dropped), reflects it back onto the originating SMS/call
  /// entry as 'failed' instead of the item just silently vanishing --
  /// otherwise the sender has no way to know their message never arrived.
  Future<void> _onQueueItemFailed(
    QueueItem item,
    Map<String, dynamic>? payload,
  ) async {
    final dropped = await _queue.markFailed(item.id!, item.retryCount);
    if (!dropped) return;

    final decodedPayload = payload ?? _tryDecode(item.payload);
    final entryId = decodedPayload?['id'] as String?;
    if (entryId == null) return;

    switch (item.type) {
      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
      case MessageTypes.smsStatus:
        await _ref
            .read(smsFacadeProvider.notifier)
            .updateStatus(entryId, 'failed');
        break;
      case MessageTypes.callIncoming:
        await _ref
            .read(callFacadeProvider.notifier)
            .updateStatus(entryId, 'failed');
        break;
    }
  }

  Map<String, dynamic>? _tryDecode(String payload) {
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
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
    await _broadcaster.stop();
    await _peerDiscoveryCoordinator.stopListening();
    await _socketManager?.disconnect();
    _socketManager = null;
    _lastDiscoveredIp = null;
    state = false;
    _ref.read(connectionStatusProvider.notifier).setServer(0, false);
    try {
      await TelephonyChannel.stopListening();
    } catch (_) {}
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
    await _socketManager?.disconnectClient();
    state = false;
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connectivity.stopListening();
    _healthTimer?.cancel();
    _broadcaster.stop();
    _peerDiscoveryCoordinator.dispose();
    _socketManager?.disconnect();
    super.dispose();
  }
}
