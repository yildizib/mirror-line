import 'dart:io';

import 'package:mirrorline/core/data/models/peer.dart';

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
    if (address.isLoopback) return false;
  } catch (_) {
    return false;
  }

  return !localIps.contains(ip);
}
