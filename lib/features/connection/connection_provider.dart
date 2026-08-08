import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
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
import 'package:mirrorline/core/services/connectivity_service.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/queue_service.dart';
import 'package:mirrorline/core/telephony/telephony_channel.dart';
import 'package:mirrorline/features/calls/call_list_provider.dart';
import 'package:mirrorline/features/connection/call_event_handler.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';
import 'package:mirrorline/features/connection/sms_event_handler.dart';
import 'package:mirrorline/features/pairing/pairing_provider.dart';
import 'package:mirrorline/features/pairing/peer_provider.dart';
import 'package:mirrorline/features/sms/sms_list_provider.dart';

final connectionProvider = StateNotifierProvider<ConnectionNotifier, bool>((ref) {
  return ConnectionNotifier(ref);
});

final connectionConnectingProvider = Provider<bool>((ref) {
  return ref.watch(connectionProvider.notifier).isConnecting;
});

class ConnectionNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  static const Duration _retryInterval = Duration(seconds: 30);
  static const Duration _reconnectInitialDelay = Duration(seconds: 2);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);
  // Fallback active network scan (see SubnetScanner): only kicks in after
  // being disconnected this long (beacon/direct-IP get a fair chance
  // first), and won't run again more often than this -- scanning ~254
  // hosts has a real battery/radio cost, so it must stay a rare fallback,
  // not a routine poll.
  static const Duration _scanGraceDuration = Duration(seconds: 25);
  static const Duration _scanBackoff = Duration(seconds: 60);

  final Logger _logger = Logger();
  final Ref _ref;
  final ConnectivityService _connectivity = ConnectivityService();
  final PeerDao _peerDao = PeerDao();
  final QueueService _queue = QueueService();
  final BeaconBroadcaster _broadcaster = BeaconBroadcaster();
  final BeaconListener _listener = BeaconListener();
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
  DateTime? _disconnectedSince;
  DateTime? _lastScanAt;
  int _reconnectAttempts = 0;

  // Call/SMS native-event and peer-message handling live in their own
  // classes (see call_event_handler.dart / sms_event_handler.dart) so this
  // notifier's own job -- owning the socket and the connection lifecycle
  // -- stays readable on its own. Constructed here (not as field
  // initializers) because their callbacks are tear-offs of this instance's
  // own methods, which need `this` to be fully alive first.
  late final CallEventHandler _callHandler;
  late final SmsEventHandler _smsHandler;

  ConnectionNotifier(this._ref) : super(false) {
    _callHandler = CallEventHandler(
      ref: _ref,
      logger: _logger,
      isSource: () => isSource,
      sendOrQueue: _sendOrQueue,
      notify: _notify,
    );
    _smsHandler = SmsEventHandler(
      ref: _ref,
      logger: _logger,
      isSource: () => isSource,
      sendOrQueue: _sendOrQueue,
      notify: _notify,
      socketManager: () => _socketManager,
    );
    _init();
  }

  bool get isSource => _peer?.role == 'source';
  bool get isConnecting => _connecting;

  /// Exposed so PairingNotifier can reply on the live connection.
  SocketManager? get socketManager => _socketManager;

  void _init() async {
    WidgetsBinding.instance.addObserver(this);

    _connectivity.onChanged = (isOnline) {
      if (isOnline) {
        _logger.i('Network back online. Reconnecting...');
        refresh();
        _scheduleReconnect();
      } else {
        _logger.i('Network offline. Dropping stale connection, pausing attempts.');
        state = false;
        _disconnectedSince ??= DateTime.now();
        // Actually tear down the client-side connection, not just the UI
        // flag. Some network transitions (e.g. Wi-Fi AP roam) never deliver
        // a socket error, so SocketManager's internal _isConnected can stay
        // stuck true; its connect() then short-circuits to a no-op "success"
        // on the next attempt without ever firing onConnected, leaving
        // `state` permanently stuck at false until the app is restarted.
        _socketManager?.disconnectClient();
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
    _healthTimer ??= Timer.periodic(_retryInterval, (_) {
      if (_connecting || state) return;
      refresh();
      _maybeRunFallbackScan();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socketManager?.setBackgroundMode(false);
      refresh();
      _scheduleReconnect();
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
      final localIp = await PeerDiscovery().getLocalIp();
      statusNotifier.setLocalIp(localIp);
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
        _ref.read(connectionStatusProvider.notifier)
            .recordConnectAttempt('Server başlatılamadı: $e');
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
      await _broadcaster.start(
        peerId: selfId,
        tcpPort: peer.port,
        deviceName: selfName,
      );
    }

    _registerTelephonyHandler();
    try {
      await TelephonyChannel.startListening();
    } catch (e) {
      _logger.e('Telephony startListening failed: $e');
    }
    _logger.i('Source mode active: server on ${peer.port}, beacon broadcasting.');
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
          _ref.read(connectionStatusProvider.notifier).setServer(peer.port, true);
        } catch (e) {
          _logger.e('Pairing-time server start failed: $e');
        }
      }
      return;
    }

    // Paired: pure client role. Tear down any leftover pairing-time server.
    await _socketManager?.stopServer();
    _ref.read(connectionStatusProvider.notifier).setServer(0, false);

    if (!_listener.isListening) {
      await _listener.start(onBeacon: _onBeacon);
    }

    // Periodic retries now come from the role-agnostic _healthTimer (see
    // _init()), which calls refresh() -- this immediate attempt just
    // avoids waiting a full interval before the first try.
    await _tryConnectToStoredPeer();
  }

  SocketManager _createSocketManager() {
    final sm = SocketManager(
      onMessage: _handleIncomingMessage,
      onConnected: () {
        state = true;
        _disconnectedSince = null;
        _reconnectAttempts = 0;
        _ref.read(connectionStatusProvider.notifier).clearError();
        _logger.i('Socket connected and authenticated!');
        _flushQueue();
        _broadcaster.setThrottle(true);
        _listener.setThrottle(true);
      },
      onDisconnected: () {
        state = false;
        _disconnectedSince ??= DateTime.now();
        _logger.w('Socket disconnected. Will auto-reconnect when peer is reachable.');
        _broadcaster.setThrottle(false);
        _listener.setThrottle(false);
        _scheduleReconnect();
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

  /// Schedules a reconnect attempt with exponential backoff: 2s, 4s, 8s,
  /// 16s, 30s (capped). The delay doubles after each failed attempt and
  /// resets to 2s once a connection succeeds (see _createSocketManager's
  /// onConnected). This replaces the old single-shot 2s retry, which gave
  /// up after one try and then waited up to 10s for the health timer --
  /// making the app feel unresponsive when the screen was turned back on
  /// after a disconnect.
  void _scheduleReconnect() {
    if (_peer == null || _key == null) return;
    if (state || _connecting) return;
    final delay = _reconnectInitialDelay * (1 << _reconnectAttempts);
    final clampedDelay = delay > _reconnectMaxDelay ? _reconnectMaxDelay : delay;
    _logger.i('Scheduling reconnect in ${clampedDelay.inSeconds}s (attempt ${_reconnectAttempts + 1}).');
    Future.delayed(clampedDelay, () {
      if (!state && !_connecting) {
        _tryConnectToStoredPeer();
      }
    });
  }

  Future<void> _tryConnectToStoredPeer() async {
    final peer = _peer;
    final key = _key;
    if (peer == null || key == null) return;
    if (state || _connecting) return;

    final ip = _lastDiscoveredIp ?? peer.ip;
    if (ip.isEmpty || ip == 'unknown') {
      _ref.read(connectionStatusProvider.notifier)
          .recordConnectAttempt('Eş cihaz IP bilinmiyor (beacon bekleniyor)');
      return;
    }

    await _connectTo(ip, peer.port);
  }

  Future<bool> _connectTo(String ip, int port) async {
    final key = _key;
    if (key == null || _connecting || state) return false;

    _connecting = true;
    try {
      _socketManager ??= _createSocketManager();
      await _configureAuth(_socketManager!);
      final ok = await _socketManager!.connect(ip, port, key);
      _ref.read(connectionStatusProvider.notifier).recordConnectAttempt(
            ok ? null : 'Bağlantı başarısız: $ip:$port (sunucu kapalı veya ulaşılamıyor)',
          );
      if (!ok) {
        _reconnectAttempts++;
        _scheduleReconnect();
      }
      return ok;
    } finally {
      _connecting = false;
    }
  }

  /// Fallback discovery: if the beacon and last-known-IP haven't gotten us
  /// connected for a while, actively scan the local subnet for the peer's
  /// TCP port. Covers routers that restrict broadcast/multicast between
  /// devices even without classic AP isolation. Deliberately rare (grace
  /// period + backoff, see the constants above) since scanning ~254 hosts
  /// has a real, if brief, battery/radio cost -- this is a fallback, not a
  /// routine poll.
  Future<void> _maybeRunFallbackScan() async {
    if (isSource) return; // only Main ever dials out
    if (state || _connecting || _scanning) return;

    final disconnectedSince = _disconnectedSince;
    if (disconnectedSince == null) return;
    if (DateTime.now().difference(disconnectedSince) < _scanGraceDuration) return;

    final lastScan = _lastScanAt;
    if (lastScan != null && DateTime.now().difference(lastScan) < _scanBackoff) return;

    final peer = _peer;
    final localIp = _ref.read(connectionStatusProvider).localIp;
    if (peer == null || localIp == null) return;

    _scanning = true;
    _lastScanAt = DateTime.now();
    try {
      final found = await _scanner.findHostWithOpenPort(localIp: localIp, port: peer.port);
      if (found != null && !state && !_connecting) {
        _logger.i('Fallback scan located peer at $found; attempting connection.');
        _lastDiscoveredIp = found;
        await _connectTo(found, peer.port);
      }
    } finally {
      _scanning = false;
    }
  }

  void _onBeacon(BeaconInfo info) {
    final peer = _peer;
    if (peer == null) return;
    if (info.peerId != peer.id) {
      _logger.w('Ignoring beacon from unknown peer: ${info.peerId}');
      return;
    }

    _lastDiscoveredIp = info.ip;
    _ref.read(connectionStatusProvider.notifier).recordBeacon(info.ip);

    if (info.ip != peer.ip || info.tcpPort != peer.port) {
      _logger.i('Peer discovered at new address ${info.ip}:${info.tcpPort}');
      final updated = peer.copyWith(ip: info.ip, port: info.tcpPort);
      _peer = updated;
      _peerDao.update(updated);
      _ref.read(peerProvider.notifier).applyUpdate(updated);
      _ref.read(connectionStatusProvider.notifier).setPeerIp(info.ip);
    }

    if (!state && !_connecting) {
      _connectTo(info.ip, info.tcpPort);
    }
  }

  /// Manual connection fallback from the settings screen.
  Future<bool> connectManually(String ip, int port) async {
    final peer = _peer;
    final key = _key;
    if (peer == null || key == null) return false;

    final updated = peer.copyWith(ip: ip, port: port);
    _peer = updated;
    await _peerDao.update(updated);
    _ref.read(peerProvider.notifier).applyUpdate(updated);

    return _connectTo(ip, port);
  }

  Future<void> retryNow() => _tryConnectToStoredPeer();

  // ---------------------------------------------------------------------
  // Telephony events (source device only)
  // ---------------------------------------------------------------------

  void _registerTelephonyHandler() {
    if (_telephonyHandlerRegistered) return;
    _telephonyHandlerRegistered = true;

    TelephonyChannel.setEventHandler((type, data) async {
      if (!isSource) return;
      final now = DateTime.now();
      final id = '${now.millisecondsSinceEpoch}';

      if (type == 'onCall') {
        await _callHandler.handleNativeEvent(data, id: id, now: now);
      } else if (type == 'onSms') {
        await _smsHandler.handleNativeEvent(data, id: id, now: now);
      } else if (type == 'onNotification') {
        final packageName = (data['packageName'] as String?) ?? 'unknown';
        final appName = (data['appName'] as String?) ?? packageName;
        final title = (data['title'] as String?) ?? '';
        final text = (data['text'] as String?) ?? '';
        final timestamp = (data['timestamp'] as int?) ?? now.millisecondsSinceEpoch;
        // Native's own stable per-notification key (see
        // MirrorLineNotificationListener), not the generated message id --
        // this is what lets Main replace a reposted notification instead
        // of duplicating it.
        final nativeId = (data['id'] as String?) ?? id;
        if (packageName == 'com.thinksolve.mirrorline') return;
        await _sendOrQueue(MessageTypes.notificationMirrored, {
          'nativeId': nativeId,
          'packageName': packageName,
          'appName': appName,
          'title': title,
          'text': text,
          'timestamp': timestamp,
        });
      }
    });
  }

  // ---------------------------------------------------------------------
  // Incoming peer messages
  // ---------------------------------------------------------------------

  void _handleIncomingMessage(MirrorMessage message) async {
    final key = _key;
    if (key == null) return;

    final decrypted = await CryptoManager.decrypt(key, message.payload);
    if (decrypted == null) {
      _logger.e('Decryption failed for message: ${message.id}');
      return;
    }

    final payload = jsonDecode(decrypted) as Map<String, dynamic>;
    final now = DateTime.now();

    switch (message.type) {
      case MessageTypes.callIncoming:
      case MessageTypes.callRejected:
      case MessageTypes.callStatus:
      case MessageTypes.callInfo:
        await _callHandler.handleIncomingMessage(message.type, payload, message, now);
        break;

      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
      case MessageTypes.smsStatus:
        await _smsHandler.handleIncomingMessage(message.type, payload, message, now);
        break;

      case MessageTypes.ack:
        _logger.i('ACK received: ${message.id}');
        break;

      case MessageTypes.notificationMirrored:
        final packageName = payload['packageName'] as String? ?? 'unknown';
        final appName = payload['appName'] as String? ?? packageName;
        final title = payload['title'] as String? ?? '';
        final text = payload['text'] as String? ?? '';
        // Native's stable per-notification key (see
        // MirrorLineNotificationListener), not a timestamp -- so a
        // reposted/updated notification replaces the previous one here
        // instead of stacking up as a duplicate.
        final nativeId = payload['nativeId'] as String? ?? message.id;
        await NotificationService.showMirrored(
          id: nativeId.hashCode & 0x7fffffff,
          title: appName,
          // The original notification's own title is usually "who it's
          // from" (e.g. a WhatsApp sender name); keep it as context ahead
          // of the message body when it says more than the app name does.
          body: (title.isNotEmpty && title != appName) ? '$title: $text' : text,
          packageName: packageName,
        );
        break;

      case MessageTypes.pairingRequest:
        _ref.read(pairingProvider.notifier).handleIncomingRequest(payload);
        break;

      case MessageTypes.pairingAccept:
      case MessageTypes.pairingReject:
        // Handled by PairingNotifier's own socket on the scanner side.
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

  Future<bool> sendCallNotification(String number, {String? id, String? contactName}) =>
      _callHandler.sendCallNotification(number, id: id, contactName: contactName);

  Future<bool> sendCallRejected(String callId) => _callHandler.sendCallRejected(callId);

  Future<bool> sendSmsNotification(String address, String body, {String? id}) =>
      _smsHandler.sendSmsNotification(address, body, id: id);

  Future<bool> sendReplySms(String address, String body, {String? id, String? contactName, String? threadId}) =>
      _smsHandler.sendReplySms(address, body, id: id, contactName: contactName, threadId: threadId);

  Future<void> _flushQueue() async {
    final items = await _queue.pendingItems();
    if (items.isEmpty) return;
    _logger.i('Flushing ${items.length} queued message(s).');
    for (final item in items) {
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        final sent = await _socketManager?.sendMessage(item.type, payload) ?? false;
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
  Future<void> _onQueueItemFailed(QueueItem item, Map<String, dynamic>? payload) async {
    final dropped = await _queue.markFailed(item.id!, item.retryCount);
    if (!dropped) return;

    final decodedPayload = payload ?? _tryDecode(item.payload);
    final entryId = decodedPayload?['id'] as String?;
    if (entryId == null) return;

    switch (item.type) {
      case MessageTypes.smsIncoming:
      case MessageTypes.smsOutgoing:
        await _ref.read(smsListProvider.notifier).updateStatus(entryId, 'failed');
        break;
      case MessageTypes.callIncoming:
        await _ref.read(callListProvider.notifier).updateStatus(entryId, 'failed');
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
    await _listener.stop();
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

  Future<void> disconnect() async {
    await _socketManager?.disconnectClient();
    state = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity.stopListening();
    _healthTimer?.cancel();
    _broadcaster.stop();
    _listener.stop();
    _socketManager?.disconnect();
    super.dispose();
  }
}
