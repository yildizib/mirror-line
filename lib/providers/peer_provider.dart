import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/daos/peer_dao.dart';
import '../data/models/peer.dart';
import '../network/peer_discovery.dart';
import '../security/crypto_manager.dart';
import '../security/key_store.dart';

final peerProvider = StateNotifierProvider<PeerNotifier, Peer?>((ref) {
  return PeerNotifier();
});

// List of all paired peers (for settings display)
final pairedPeersProvider = FutureProvider<List<Peer>>((ref) async {
  return PeerDao().getAllPeers();
});

class PeerNotifier extends StateNotifier<Peer?> {
  final PeerDao _dao = PeerDao();

  PeerNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    state = await _dao.getPeer();
  }

  Future<String> _getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model ?? 'Android Cihaz';
    } catch (_) {
      return 'Bilinmeyen Cihaz';
    }
  }

  Future<void> createPeer(String role) async {
    final key = CryptoManager.generateKey();
    final keyBytes = await key.extractBytes();
    final keyBase64 = base64Encode(keyBytes);
    final ip = await PeerDiscovery().getLocalIp() ?? 'unknown';
    final deviceName = await _getDeviceName();

    final peer = Peer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceName: deviceName,
      role: role,
      ip: ip,
      port: 45678,
      key: keyBase64,
      createdAt: DateTime.now(),
    );

    await _dao.insert(peer);
    await KeyStore.setPeerId(peer.id);
    await KeyStore.setPeerKey(key);
    state = peer;
  }

  /// Save peer info obtained from scanning the other device's QR code.
  /// The key comes as base64 string from the QR payload.
  /// The ip comes from the scanned QR (the other device's IP).
  Future<void> createPeerFromQr({
    required String id,
    required String ip,
    required int port,
    required String keyBase64,
    required String role,
    required String deviceName,
  }) async {
    final keyBytes = base64Decode(keyBase64);
    final key = SecretKey(keyBytes);

    final peer = Peer(
      id: id,
      deviceName: deviceName,
      role: role,
      ip: ip,
      port: port,
      key: keyBase64,
      createdAt: DateTime.now(),
    );

    await _dao.insert(peer);
    await KeyStore.setPeerId(peer.id);
    await KeyStore.setPeerKey(key);
    state = peer;
  }

  Future<void> savePeer(Peer peer, SecretKey key) async {
    await _dao.insert(peer);
    await KeyStore.setPeerId(peer.id);
    await KeyStore.setPeerKey(key);
    state = peer;
  }

  Future<void> reset() async {
    final current = state;
    if (current != null) {
      await _dao.delete(current.id);
    }
    await KeyStore.clearAll();
    state = null;
  }
}