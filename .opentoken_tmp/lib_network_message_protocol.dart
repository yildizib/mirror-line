import 'dart:convert';

class MirrorMessage {
  final String type;
  final String id;
  final int timestamp;
  final String payload; // base64 encrypted json

  MirrorMessage({
    required this.type,
    required this.id,
    required this.timestamp,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'timestamp': timestamp,
        'payload': payload,
      };

  factory MirrorMessage.fromJson(Map<String, dynamic> json) => MirrorMessage(
        type: json['type'] as String,
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        payload: json['payload'] as String,
      );

  String encode() => jsonEncode(toJson());

  static MirrorMessage decode(String raw) => MirrorMessage.fromJson(jsonDecode(raw));
}

abstract class MessageTypes {
  static const String callIncoming = 'call_incoming';
  static const String callRejected = 'call_rejected';
  static const String smsIncoming = 'sms_incoming';
  static const String smsOutgoing = 'sms_outgoing';
  static const String smsStatus = 'sms_status';
  static const String ack = 'ack';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String notificationMirrored = 'notification_mirrored';
}
