import 'dart:io';

import 'package:mirrorline/core/data/models/peer.dart';

bool hasCompletedRemotePeer(Peer? peer) {
  return peer != null && peer.publicKey.isNotEmpty;
}

bool isUsablePeerEndpoint({
  required Peer? peer,
  required Iterable<String> localIps,
}) {
  if (peer == null || peer.publicKey.isEmpty) return false;
  return isUsableEndpoint(ip: peer.ip, port: peer.port, localIps: localIps);
}

bool isUsableEndpoint({
  required String ip,
  required int port,
  required Iterable<String> localIps,
}) {
  if (ip.isEmpty || ip == 'unknown' || port <= 0 || port > 65535) {
    return false;
  }

  try {
    final address = InternetAddress(ip);
    final addressBytes = _normalizedAddressBytes(address.rawAddress);
    if (_isUnspecified(addressBytes) || _isLoopback(addressBytes)) return false;
    for (final localIp in localIps) {
      if (_isSameAddress(address, localIp)) return false;
    }
  } catch (_) {
    return false;
  }

  return true;
}

bool _isSameAddress(InternetAddress address, String candidate) {
  try {
    final scopeIndex = candidate.indexOf('%');
    final normalized = scopeIndex < 0
        ? candidate
        : candidate.substring(0, scopeIndex);
    final other = InternetAddress(normalized);
    final left = _normalizedAddressBytes(address.rawAddress);
    final right = _normalizedAddressBytes(other.rawAddress);
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

List<int> _normalizedAddressBytes(List<int> bytes) {
  if (bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff) {
    return bytes.sublist(12);
  }
  return bytes;
}

bool _isUnspecified(List<int> bytes) => bytes.every((byte) => byte == 0);

bool _isLoopback(List<int> bytes) {
  if (bytes.length == 4) return bytes.first == 127;
  return bytes.length == 16 &&
      bytes.take(15).every((byte) => byte == 0) &&
      bytes.last == 1;
}
