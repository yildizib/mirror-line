import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/network/peer_discovery.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:uuid/uuid.dart';

final peerFacadeProvider = StateNotifierProvider<PeerFacade, Peer?>((ref) {
  return PeerFacade();
});

// List of all paired peers (for settings display). Watches peerFacadeProvider so
// it automatically refreshes whenever the active peer record changes
// (pairing completes, peer deleted, reset, etc.) -- without this the list
// would show stale data after pairing since FutureProvider doesn't
// auto-refresh on DB writes.
final pairedPeersProvider = FutureProvider<List<Peer>>((ref) async {
  // Depend on peerFacadeProvider so any state change (applyPairedPeer,
  // deletePeer, reset, ...) invalidates this provider.
  ref.watch(peerFacadeProvider);
  return PeerDao().getAllPeers();
});

class PeerFacade extends StateNotifier<Peer?> {
  final PeerDao _dao = PeerDao();

  PeerFacade() : super(null) {
    _load();
  }

  Future<void> _load() async {
    state = await _dao.getPeer();
  }

  /// Not routed through AppLocalizations: this becomes the persisted/
  /// transmitted device identity shown on the *other* paired device (whose
  /// app language may differ from this one's), so it needs a locale-neutral
  /// fallback rather than this device's own language.
  Future<String> _getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final model = androidInfo.model;
      return model.isEmpty ? 'Android Device' : model;
    } catch (_) {
      return 'Unknown Device';
    }
  }

  static String generateVerificationCode(String keyBase64, String peerId) {
    return CryptoManager.verificationCodeFromKey(keyBase64, peerId);
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

    // Ensure this device has an Ed25519 identity keypair (stored in KeyStore).
    // The peer's publicKey field holds the *other* device's public key and
    // is left empty until pairing completes.
    await KeyStore.ensureDeviceKeyPair();

    final peer = Peer(
      id: const Uuid().v4(),
      deviceName: deviceName,
      role: role,
      ip: ip,
      port: 45678,
      key: keyBase64,
      publicKey: '',
      createdAt: DateTime.now(),
    );

    await _dao.insert(peer);
    await KeyStore.setPeerId(peer.id);
    await KeyStore.setPeerKey(key);
    await KeyStore.setSelfIdentity(id: peer.id, deviceName: deviceName);
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

    // Replace (not just insert): before pairing this device had its own
    // self-only row under a different id. Plain insert() would leave that
    // old row behind as an orphaned duplicate (visible as a phantom entry
    // in the paired-devices list) since the new row has a different id.
    final oldId = state?.id;
    if (oldId != null) {
      await _dao.replaceId(oldId, peer);
    } else {
      await _dao.insert(peer);
    }
    await KeyStore.setPeerId(peer.id);
    await KeyStore.setPeerKey(key);
    state = peer;
  }

  /// Returns this device's Ed25519 public key (generating if needed).
  Future<String> getMyPublicKey() async {
    return KeyStore.ensureDeviceKeyPair();
  }

  /// Called on the *scanned* side once pairing completes. Persists the
  /// scanner's (the other device's) full identity -- not just its public
  /// key -- so that afterwards `peer` consistently represents the paired
  /// other device on both sides, regardless of who scanned whom. Preserves
  /// this device's own role/key/port.
  ///
  /// The [ip] is the scanner's real IP, claimed by the scanner itself in
  /// its pairingRequest (preferred over the TCP remote address, which can
  /// be wrong on NAT/VLAN setups). Beacon discovery will further refine it
  /// if the scanner later roams to a new address -- see
  /// ConnectionFacade._recordDiscoveredAddress.
  Future<void> applyPairedPeer({
    required String id,
    required String deviceName,
    required String publicKey,
    String? ip,
  }) async {
    final current = state;
    if (current == null) return;
    final updated = current.copyWith(
      id: id,
      deviceName: deviceName,
      publicKey: publicKey,
      ip: (ip != null && ip.isNotEmpty) ? ip : current.ip,
    );
    await _dao.replaceId(current.id, updated);
    await KeyStore.setPeerId(updated.id);
    state = updated;
  }

  /// Applies an updated peer record (e.g. newly discovered IP address).
  void applyUpdate(Peer peer) {
    state = peer;
  }

  /// Re-detects the local IP (used before displaying the QR code so the
  /// QR always carries the current address). Only meaningful while the peer
  /// row still represents *this* device (pre-pairing): once paired, the row
  /// holds the other device's identity, and overwriting its ip with our own
  /// local address is what made Settings' diagnostics show the same IP for
  /// both "This Device" and "Peer Device".
  Future<void> refreshLocalIp() async {
    final current = state;
    if (current == null) return;
    if (current.publicKey.isNotEmpty) return;
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
