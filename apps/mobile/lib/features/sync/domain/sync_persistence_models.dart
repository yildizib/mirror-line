import 'dart:typed_data';

enum DeviceKeyStatus { pending, active, retiring, retired, revoked }

enum ReplayDisposition { accepted, idempotent, conflict }

enum LocalHistoryRetention {
  days7(7),
  days30(30),
  days90(90),
  days180(180);

  const LocalHistoryRetention(this.days);
  final int days;
}

class RelayEnvelopeRecord {
  const RelayEnvelopeRecord({
    required this.direction,
    required this.messageId,
    required this.protocolVersion,
    required this.messageType,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.recipientUserId,
    required this.recipientDeviceId,
    required this.senderKeyVersion,
    required this.recipientKeyVersion,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
    required this.digest,
    required this.createdAt,
    this.acceptedAt,
    this.expiresAt,
  });
  final String direction,
      messageId,
      messageType,
      senderUserId,
      senderDeviceId,
      recipientUserId,
      recipientDeviceId;
  final int protocolVersion, senderKeyVersion, recipientKeyVersion;
  final Uint8List nonce, ciphertext, signature, digest;
  final DateTime createdAt;
  final DateTime? acceptedAt, expiresAt;
}
