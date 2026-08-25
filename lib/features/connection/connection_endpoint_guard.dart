import 'dart:io';

import 'package:mirrorline/core/data/models/peer.dart';

enum EndpointRejectionReason {
  empty,
  invalidPort,
  malformed,
  unspecified,
  loopback,
  locallyOwned,
}

class EndpointValidationResult {
  final String? normalizedIp;
  final EndpointRejectionReason? rejectionReason;

  const EndpointValidationResult.usable(this.normalizedIp)
    : assert(normalizedIp != null),
      rejectionReason = null;

  const EndpointValidationResult.rejected(this.rejectionReason)
    : normalizedIp = null;

  bool get isUsable => normalizedIp != null;
}

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
  return validateEndpoint(ip: ip, port: port, localIps: localIps).isUsable;
}

EndpointValidationResult validateEndpoint({
  required String ip,
  required int port,
  required Iterable<String> localIps,
}) {
  if (ip.isEmpty || ip == 'unknown') {
    return const EndpointValidationResult.rejected(
      EndpointRejectionReason.empty,
    );
  }
  if (port <= 0 || port > 65535) {
    return const EndpointValidationResult.rejected(
      EndpointRejectionReason.invalidPort,
    );
  }

  try {
    final address = InternetAddress(ip);
    final addressBytes = _normalizedAddressBytes(address.rawAddress);
    if (_isUnspecified(addressBytes)) {
      return const EndpointValidationResult.rejected(
        EndpointRejectionReason.unspecified,
      );
    }
    if (_isLoopback(addressBytes)) {
      return const EndpointValidationResult.rejected(
        EndpointRejectionReason.loopback,
      );
    }
    for (final localIp in localIps) {
      if (_isSameAddress(address, localIp)) {
        return const EndpointValidationResult.rejected(
          EndpointRejectionReason.locallyOwned,
        );
      }
    }
    return EndpointValidationResult.usable(address.address);
  } catch (_) {
    return const EndpointValidationResult.rejected(
      EndpointRejectionReason.malformed,
    );
  }
}

bool areSameIpAddresses(String left, String right) {
  try {
    return _isSameAddress(InternetAddress(left), right);
  } catch (_) {
    return false;
  }
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
