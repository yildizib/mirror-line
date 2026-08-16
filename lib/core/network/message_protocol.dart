import 'dart:convert';

class MirrorMessage {
  static const int currentProtocolVersion = 1;

  final String type;
  final String id;
  final int timestamp;
  final String payload; // base64 encrypted json
  final int protocolVersion;
  final String? sourcePeerId;
  final String? destinationPeerId;
  final String? sessionId;
  final int? sequence;

  MirrorMessage({
    required this.type,
    required this.id,
    required this.timestamp,
    required this.payload,
    this.protocolVersion = currentProtocolVersion,
    this.sourcePeerId,
    this.destinationPeerId,
    this.sessionId,
    this.sequence,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'timestamp': timestamp,
    'payload': payload,
    'protocolVersion': protocolVersion,
    if (sourcePeerId != null) 'sourcePeerId': sourcePeerId,
    if (destinationPeerId != null) 'destinationPeerId': destinationPeerId,
    if (sessionId != null) 'sessionId': sessionId,
    if (sequence != null) 'sequence': sequence,
  };

  factory MirrorMessage.fromJson(Map<String, dynamic> json) => MirrorMessage(
    type: json['type'] as String,
    id: json['id'] as String,
    timestamp: json['timestamp'] as int,
    payload: json['payload'] as String,
    protocolVersion:
        (json['protocolVersion'] as int?) ?? currentProtocolVersion,
    sourcePeerId: json['sourcePeerId'] as String?,
    destinationPeerId: json['destinationPeerId'] as String?,
    sessionId: json['sessionId'] as String?,
    sequence: json['sequence'] as int?,
  );

  bool get hasAuthenticatedEnvelope =>
      sourcePeerId != null &&
      destinationPeerId != null &&
      sessionId != null &&
      sequence != null;

  String authenticatedData() => jsonEncode({
    'protocolVersion': protocolVersion,
    'sourcePeerId': sourcePeerId,
    'destinationPeerId': destinationPeerId,
    'sessionId': sessionId,
    'sequence': sequence,
    'type': type,
    'id': id,
    'timestamp': timestamp,
  });

  /// Stable context signed during authentication. It binds the fresh server
  /// challenge to both paired identities and this specific connection.
  static String authTranscript({
    required String sessionId,
    required String serverPeerId,
    required String clientPeerId,
    required String serverNonce,
    required String clientNonce,
  }) => jsonEncode({
    'protocolVersion': currentProtocolVersion,
    'sessionId': sessionId,
    'serverPeerId': serverPeerId,
    'clientPeerId': clientPeerId,
    'serverNonce': serverNonce,
    'clientNonce': clientNonce,
  });

  String encode() => jsonEncode(toJson());

  static MirrorMessage decode(String raw) =>
      MirrorMessage.fromJson(jsonDecode(raw));
}

abstract class MessageTypes {
  static const String callIncoming = 'call_incoming';
  static const String callRejected = 'call_rejected';
  // Source -> Main: the call's live state changed (answered/missed/ended)
  // so Main can stop offering to reject a call that's no longer ringing.
  static const String callStatus = 'call_status';
  // Source -> Main: enriches an already-announced call (e.g. the number
  // only resolved on a later RINGING broadcast) -- patches the existing
  // entry, never creates a new one.
  static const String callInfo = 'call_info';
  static const String smsIncoming = 'sms_incoming';
  static const String smsOutgoing = 'sms_outgoing';
  static const String smsStatus = 'sms_status';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String notificationMirrored = 'notification_mirrored';
  // Source -> Main: a previously-mirrored notification was dismissed on
  // the source device -- clear the mirrored copy. Payload: {packageName,
  // nativeId}.
  static const String notificationRemoved = 'notification_removed';

  // ---- Pairing handshake ----------------------------------------------
  // Scanner -> Scanned: starts a pairing request from {deviceName} ({myId}).
  static const String pairingRequest = 'pairing_request';
  // Scanned -> Scanner: accepts pairing as {deviceName} ({myId}).
  static const String pairingAccept = 'pairing_accept';
  // Scanned -> Scanner: rejects pairing.
  static const String pairingReject = 'pairing_reject';
  // Scanner -> Scanned: confirms pairingAccept was received and persisted.
  // Scanned does not call applyPairedPeer before this acknowledgement (see
  // the authOk/authAck pattern below). Without it, a lost pairingAccept
  // leaves Scanned paired while Scanner has no record: an asymmetric state
  // that cannot self-heal.
  static const String pairingAck = 'pairing_ack';
  // Scanned -> Scanner: local persistence completed successfully.
  static const String pairingComplete = 'pairing_complete';
  // Either side: the session failed after provisional persistence.
  static const String pairingAbort = 'pairing_abort';

  // ---- Connection authentication (challenge-response) -----------------
  // Client -> Server: starts a fresh authenticated connection attempt.
  static const String authHello = 'auth_hello';
  // Server -> Client: challenges the client to prove its identity (nonce).
  static const String authChallenge = 'auth_challenge';
  // Client -> Server: returns the signed nonce.
  static const String authResponse = 'auth_response';
  // Server -> Client: confirms authentication and accepts the connection.
  static const String authOk = 'auth_ok';
  // Client -> Server: confirms authOk. The server treats the connection as
  // established only after this acknowledgement; otherwise a lost authOk can
  // leave the server connected after the client has already given up.
  static const String authAck = 'auth_ack';
  // Server -> Client: rejects an unauthenticated connection.
  static const String authFail = 'auth_fail';
}
