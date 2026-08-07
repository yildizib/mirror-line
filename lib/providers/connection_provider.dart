import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../data/daos/peer_dao.dart';
import '../data/models/peer.dart';
import '../network/message_protocol.dart';
import '../network/socket_manager.dart';
import '../security/crypto_manager.dart';
import '../security/key_store.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';

final connectionProvider = StateNotifierProvider<ConnectionNotifier, bool>((ref) {
  return ConnectionNotifier();
});

class ConnectionNotifier extends StateNotifier<bool> {
  final Logger _logger = Logger();
  final ConnectivityService _connectivity = ConnectivityService();
  final PeerDao _peerDao = PeerDao();

  SocketManager? _socketManager;
  Peer? _peer;
  SecretKey? _key;

  ConnectionNotifier() : super(false) {
    _init();
  }

  void _init() async {
    _connectivity.startListening();
    _connectivity.onChanged = (isOnline) {
      if (isOnline) {
        _tryConnect();
      } else {
        state = false;
        _socketManager?.disconnect();
      }
    };

    final isOnline = await _connectivity.isOnline();
    if (isOnline) {
      _tryConnect();
    }
  }

  Future<void> _tryConnect() async {
    if (_socketManager?.isConnected == true) return;

    _peer = await _peerDao.getPeer();
    _key = await KeyStore.getPeerKey();

    if (_peer == null || _key == null) {
      _logger.w('No peer info or key found. Cannot connect.');
      return;
    }

    _socketManager = SocketManager(
      onMessage: _handleIncomingMessage,
      onConnected: () {
        state = true;
        _logger.i('Socket connected!');
      },
      onDisconnected: () {
        state = false;
        _logger.w('Socket disconnected.');
      },
    );

    if (_peer!.role == 'source') {
      // Source cihaz server olarak dinler
      await _socketManager!.startServer(_peer!.port, _key!);
    } else {
      // Main cihaz client olarak Source'a bağlanır
      // Source cihazın IP'sini bilmesi lazım.
      // TODO: mDNS ile otomatik keşif eklenecek.
      // Şimdilik manuel IP gerekiyor.
      _logger.i('Main role: trying to connect to ${_peer!.ip}:${_peer!.port}');
      await _socketManager!.connect(_peer!.ip, _peer!.port, _key!);
    }
  }

  void _handleIncomingMessage(MirrorMessage message) async {
    if (_key == null) return;

    final decrypted = await CryptoManager.decrypt(_key!, message.payload);
    if (decrypted == null) {
      _logger.e('Decryption failed for message: ${message.id}');
      return;
    }

    final payload = jsonDecode(decrypted) as Map<String, dynamic>;

    switch (message.type) {
      case MessageTypes.callIncoming:
        final number = payload['number'] as String? ?? 'unknown';
        await NotificationService.show(
          id: 1,
          title: 'Gelen Arama',
          body: number,
          payload: message.id,
        );
        _logger.i('Call notification shown: $number');
        break;

      case MessageTypes.smsIncoming:
        final address = payload['address'] as String? ?? 'unknown';
        final body = payload['body'] as String? ?? '';
        await NotificationService.show(
          id: 2,
          title: 'SMS: $address',
          body: body,
          payload: message.id,
        );
        _logger.i('SMS notification shown: $address');
        break;

      case MessageTypes.smsStatus:
        _logger.i('SMS status: ${payload['status']}');
        break;

      case MessageTypes.ack:
        _logger.i('ACK received: ${message.id}');
        break;

      default:
        _logger.i('Unknown message type: ${message.type}');
    }
  }

  Future<void> sendCallNotification(String number) async {
    await _socketManager?.sendMessage(MessageTypes.callIncoming, {
      'number': number,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> sendSmsNotification(String address, String body) async {
    await _socketManager?.sendMessage(MessageTypes.smsIncoming, {
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> sendReplySms(String address, String body) async {
    await _socketManager?.sendMessage(MessageTypes.smsOutgoing, {
      'address': address,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> disconnect() async {
    await _socketManager?.disconnect();
    state = false;
  }

  @override
  void dispose() {
    _connectivity.stopListening();
    _socketManager?.disconnect();
    super.dispose();
  }
}