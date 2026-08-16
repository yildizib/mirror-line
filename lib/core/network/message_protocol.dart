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
    required String nonce,
  }) => jsonEncode({
    'protocolVersion': currentProtocolVersion,
    'sessionId': sessionId,
    'serverPeerId': serverPeerId,
    'clientPeerId': clientPeerId,
    'nonce': nonce,
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
  // Scanner -> Scanned:  "Ben {deviceName} ({myId}) seninle eşleşmek istiyorum"
  static const String pairingRequest = 'pairing_request';
  // Scanned -> Scanner:  "Eşleşmeyi onayladım, ben {deviceName} ({myId})"
  static const String pairingAccept = 'pairing_accept';
  // Scanned -> Scanner:  "Eşleşme reddedildi"
  static const String pairingReject = 'pairing_reject';
  // Scanner -> Scanned:  "pairingAccept'i aldım ve kendi tarafımı da
  // kalıcı olarak kaydettim" -- Scanned, bu ack'i almadan applyPairedPeer
  // çağırmaz (bkz. authOk/authAck deseni aşağıda). Bunsuz, pairingAccept
  // ağ üzerinde kaybolursa Scanned kendini eşleşmiş sanır ama Scanner hiç
  // kaydetmemiş olur -- asimetrik, kendi kendine düzelmeyen bir durum.
  static const String pairingAck = 'pairing_ack';
  // Scanned -> Scanner: local persistence completed successfully.
  static const String pairingComplete = 'pairing_complete';
  // Either side: the session failed after provisional persistence.
  static const String pairingAbort = 'pairing_abort';

  // ---- Connection authentication (challenge-response) -----------------
  // Server -> Client:  "Bana kim olduğunu kanıtla" (nonce içerir)
  static const String authChallenge = 'auth_challenge';
  // Client -> Server:  "İşte imzalı nonce'um"
  static const String authResponse = 'auth_response';
  // Server -> Client:  "Doğrulandı, bağlantı kabul"
  static const String authOk = 'auth_ok';
  // Client -> Server:  "authOk'u aldım" -- server ancak bunu alınca
  // bağlantıyı kurulmuş sayar; aksi halde authOk kaybolursa server yanlışça
  // "bağlı" görünüp client çoktan vazgeçmiş olabilirdi.
  static const String authAck = 'auth_ack';
  // Server -> Client:  "Doğrulanamadı, bağlantı reddedildi"
  static const String authFail = 'auth_fail';
}
