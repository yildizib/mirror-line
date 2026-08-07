import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../data/daos/peer_dao.dart';
import '../data/models/call_event.dart';
import '../data/models/peer.dart';
import '../data/models/sms_message.dart';
import '../network/lan_beacon.dart';
import '../network/message_protocol.dart';
import '../network/peer_discovery.dart';
import '../network/socket_manager.dart';
import '../providers/call_list_provider.dart';
import '../providers/connection_status_provider.dart';
import '../providers/peer_provider.dart';
import '../providers/sms_list_provider.dart';
import '../security/crypto_manager.dart';
import '../security/key_store.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/queue_service.dart';
import '../telephony/telephony_channel.dart';

final connectionProvider = StateNotifierProvider<ConnectionNotifier, bool>((ref) {
  return ConnectionNotifier(ref);
});

class ConnectionNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  static const Duration _retryInterval = Duration(seconds: 10);

  final Logger _logger = Logger();
  final Ref _ref;
  final ConnectivityService _connectivity = ConnectivityService();
  final PeerDao _peerDao = PeerDao();
  final QueueService _queue = QueueService();
  final BeaconBroadcaster _broadcaster = BeaconBroadcaster();
  final BeaconListener _listener = BeaconListener();

  SocketManager? _socketManager;
  Peer? _peer;
  SecretKey? _key;
  Timer? _retryTimer;
  bool _connecting = false;
  bool _telephonyHandlerRegistered = false;
  String? _lastDiscoveredIp;

  ConnectionNotifier(this._ref) : super(false) {
    _init();
  }

  bool get isSource => _peer?.role == 'source';

  void _init() async {
    WidgetsBinding.instance.addObserver(this);

    _connectivity.onChanged = (isOnline) {
      if (isOnline) {
        refresh();
      } else {
        state = false;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  /// Reloads peer info and (re)starts role-specific networking machinery.
  /// Call after pairing, role changes or resets.
  Future<void> refresh() async {
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
  }

  Future<void> _startAsSource() async {
    final peer = _peer!;
    final key = _key!;

    _socketManager ??= _createSocketManager();
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

    await _broadcaster.start(
      peerId: peer.id,
      tcpPort: peer.port,
      deviceName: peer.deviceName,
    );

    _registerTelephonyHandler();
    try {
      await TelephonyChannel.startListening();
    } catch (e) {
      _logger.e('Telephony startListening failed: $e');
    }
    _logger.i('Source mode active: server on ${peer.port}, beacon broadcasting.');
  }

  Future<void> _startAsMain() async {
    if (!_listener.isListening) {
      await _listener.start(onBeacon: _onBeacon);
    }

    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      if (state || _connecting) return;
      _tryConnectToStoredPeer();
    });

    await _tryConnectToStoredPeer();
  }

  SocketManager _createSocketManager() {
    return SocketManager(
      onMessage: _handleIncomingMessage,
      onConnected: () {
        state = true;
        _ref.read(connectionStatusProvider.notifier).clearError();
        _logger.i('Socket connected!');
        _flushQueue();
      },
      onDisconnected: () {
        state = false;
        _logger.w('Socket disconnected.');
      },
    );
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
      final ok = await _socketManager!.connect(ip, port, key);
      _ref.read(connectionStatusProvider.notifier).recordConnectAttempt(
            ok ? null : 'Bağlantı başarısız: $ip:$port (sunucu kapalı veya ulaşılamıyor)',
          );
      return ok;
    } finally {
      _connecting = false;
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
        final number = (data['number'] as String?) ?? 'unknown';
        final event = CallEvent(
          id: id,
          direction: 'incoming',
          number: number,
          timestamp: now,
          encrypted: '',
          status: 'delivered',
          createdAt: now,
        );
        await _ref.read(callListProvider.notifier).add(event);
        await sendCallNotification(number, id: id);
      } else if (type == 'onSms') {
        final address = (data['address'] as String?) ?? 'unknown';
        final body = (data['body'] as String?) ?? '';
        final threadId = (data['threadId'] as String?) ?? '';
        final message = SmsMessage(
          id: id,
          threadId: threadId,
          address: address,
          body: body,
          encrypted: '',
          direction: 'incoming',
          status: 'received',
          timestamp: now,
          createdAt: now,
        );
        await _ref.read(smsListProvider.notifier).add(message);
        await _sendOrQueue(MessageTypes.smsIncoming, {
          'id': id,
          'address': address,
          'body': body,
          'thread_id': threadId,
          'timestamp': now.millisecondsSinceEpoch,
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
        final number = payload['number'] as String? ?? 'unknown';
        final id = payload['id'] as String? ?? message.id;
        await _ref.read(callListProvider.notifier).add(CallEvent(
              id: id,
              direction: 'incoming',
              number: number,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                  payload['timestamp'] as int? ?? now.millisecondsSinceEpoch),
              encrypted: message.payload,
              status: 'delivered',
              createdAt: now,
            ));
        await _notify(
          id: int.tryParse(id) ?? 1,
          title: 'Gelen Arama',
          body: number,
          payload: message.id,
        );
        break;

      case MessageTypes.callRejected:
        if (isSource) {
          await TelephonyChannel.rejectCall();
        }
        final id = payload['id'] as String?;
        if (id != null) {
          await _ref.read(callListProvider.notifier).updateStatus(id, 'rejected');
        }
        break;

      case MessageTypes.smsIncoming:
        final address = payload['address'] as String? ?? 'unknown';
        final body = payload['body'] as String? ?? '';
        final id = payload['id'] as String? ?? message.id;
        await _ref.read(smsListProvider.notifier).add(SmsMessage(
              id: id,
              threadId: payload['thread_id'] as String? ?? '',
              address: address,
              body: body,
              encrypted: message.payload,
              direction: 'incoming',
              status: 'received',
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                  payload['timestamp'] as int? ?? now.millisecondsSinceEpoch),
              createdAt: now,
            ));
        await _notify(
          id: int.tryParse(id) ?? 2,
          title: 'SMS: $address',
          body: body,
          payload: message.id,
        );
        break;

      case MessageTypes.smsOutgoing:
        if (isSource) {
          final address = payload['address'] as String? ?? '';
          final body = payload['body'] as String? ?? '';
          final id = payload['id'] as String? ?? message.id;
          var status = 'sent';
          try {
            await TelephonyChannel.sendSms(address, body);
          } catch (e) {
            _logger.e('SMS send failed: $e');
            status = 'failed';
          }
          await _ref.read(smsListProvider.notifier).add(SmsMessage(
                id: id,
                threadId: payload['thread_id'] as String? ?? '',
                address: address,
                body: body,
                encrypted: message.payload,
                direction: 'outgoing',
                status: status,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    payload['timestamp'] as int? ?? now.millisecondsSinceEpoch),
                createdAt: now,
              ));
          await _socketManager?.sendMessage(MessageTypes.smsStatus, {
            'id': id,
            'status': status,
          });
        }
        break;

      case MessageTypes.smsStatus:
        final id = payload['id'] as String?;
        final status = payload['status'] as String? ?? 'sent';
        if (id != null) {
          await _ref.read(smsListProvider.notifier).updateStatus(id, status);
        }
        break;

      case MessageTypes.ack:
        _logger.i('ACK received: ${message.id}');
        break;

      default:
        _logger.i('Unknown message type: ${message.type}');
    }
  }

  Future<void> _notify({
    required int id,
    required String title,
    required String body,
    String? payload,
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

  Future<bool> sendCallNotification(String number, {String? id}) {
    final callId = id ?? '${DateTime.now().millisecondsSinceEpoch}';
    return _sendOrQueue(MessageTypes.callIncoming, {
      'id': callId,
      'number': number,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendCallRejected(String callId) {
    return _sendOrQueue(MessageTypes.callRejected, {
      'id': callId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendSmsNotification(String address, String body, {String? id}) {
    final smsId = id ?? '${DateTime.now().millisecondsSinceEpoch}';
    return _sendOrQueue(MessageTypes.smsIncoming, {
      'id': smsId,
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> sendReplySms(String address, String body, {String? id}) {
    final smsId = id ?? '${DateTime.now().millisecondsSinceEpoch}';
    return _sendOrQueue(MessageTypes.smsOutgoing, {
      'id': smsId,
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

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
          if (item.id != null) await _queue.markFailed(item.id!, item.retryCount);
          break;
        }
      } catch (e) {
        _logger.e('Failed to flush queue item ${item.id}: $e');
        if (item.id != null) await _queue.markFailed(item.id!, item.retryCount);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------

  Future<void> _stopMachinery() async {
    _retryTimer?.cancel();
    _retryTimer = null;
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
    _retryTimer?.cancel();
    _broadcaster.stop();
    _listener.stop();
    _socketManager?.disconnect();
    super.dispose();
  }
}
