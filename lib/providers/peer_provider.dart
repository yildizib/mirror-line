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
      final model = androidInfo.model;
      return model.isEmpty ? 'Android Cihaz' : model;
    } catch (_) {
      return 'Bilinmeyen Cihaz';
    }
  }

  static String generateVerificationCode(String keyBase64, String peerId) {
    final combined = '$keyBase64|$peerId';
    final hash = combined.hashCode.abs();
    return (hash % 1000000).toString().padLeft(6, '0');
  }

  Future<void> createPeer(String role) async {
    final existing = await _dao.getPeer();
    if (existing != null) {
      final updated = existing.copyWith(role: role);
      await _dao.update(updated);
      state = updated;
      return;
    }

    final key = CryptoManager.generateKey();
    final keyBytes = await key.extractBytes();
    final keyBase64 = base64Encode(keyBytes);
    final ip = await PeerDiscovery().getLocalIp() ?? 'unknown';
    final deviceName = await _getDeviceName();

    // Ensure this device has an Ed25519 identity keypair.
    final myPublicKey = await KeyStore.ensureDeviceKeyPair();

    final peer = Peer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceName: deviceName,
      role: role,
      ip: ip,
      port: 45678,
      key: keyBase64,
      publicKey: myPublicKey,
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
    required String publicKey,
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
      publicKey: publicKey,
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

  /// Returns this device's Ed25519 public key (generating if needed).
  Future<String> getMyPublicKey() async {
    return KeyStore.ensureDeviceKeyPair();
  }

  /// Applies an updated peer record (e.g. newly discovered IP address).
  void applyUpdate(Peer peer) {
    state = peer;
  }

  /// Re-detects the local IP (used before displaying the QR code so the
  /// QR always carries the current address).
  Future<void> refreshLocalIp() async {
    final current = state;
    if (current == null) return;
    final ip = await PeerDiscovery().getLocalIp();
    if (ip != null && ip != current.ip) {
      final updated = current.copyWith(ip: ip);
      await _dao.update(updated);
      state = updated;
    }
  }

  Future<void> updateConnectionInfo(String ip, int port) async {
    final current = state;
    if (current == null) return;
    final updated = current.copyWith(ip: ip, port: port);
    await _dao.update(updated);
    state = updated;
  }

  /// Deletes a specific peer record.
  /// If it was the active peer, the next available peer becomes active
  /// (and its key is restored); otherwise the device becomes unpaired.
  Future<void> deletePeer(Peer peer) async {
    await _dao.delete(peer.id);
    final current = state;
    if (current?.id != peer.id) return;

    final remaining = await _dao.getPeer();
    if (remaining != null) {
      final keyBytes = base64Decode(remaining.key);
      final key = SecretKey(keyBytes);
      await KeyStore.setPeerId(remaining.id);
      await KeyStore.setPeerKey(key);
      state = remaining;
    } else {
      await KeyStore.clearPeerId();
      await KeyStore.clearPeerKey();
      state = null;
    }
  }

  Future<void> reset() async {
    final current = state;
    if (current != null) {
      await _dao.delete(current.id);
    }
    await KeyStore.clearPeerId();
    await KeyStore.clearPeerKey();
    state = null;
  }
}