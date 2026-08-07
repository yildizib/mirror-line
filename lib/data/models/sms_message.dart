class SmsMessage {
  final String id;
  final String threadId;
  final String address;
  final String body;
  final String encrypted; // base64 ciphertext
  final String direction; // 'incoming' | 'outgoing'
  final String status; // 'received' | 'sent' | 'delivered' | 'failed'
  final DateTime timestamp;
  final DateTime createdAt;

  SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.encrypted,
    required this.direction,
    required this.status,
    required this.timestamp,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'thread_id': threadId,
        'address': address,
        'body': body,
        'encrypted': encrypted,
        'direction': direction,
        'status': status,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SmsMessage.fromJson(Map<String, dynamic> json) => SmsMessage(
        id: json['id'] as String,
        threadId: json['thread_id'] as String,
        address: json['address'] as String,
        body: json['body'] as String,
        encrypted: json['encrypted'] as String,
        direction: json['direction'] as String,
        status: json['status'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      );

  SmsMessage copyWith({String? status, String? body, String? encrypted}) => SmsMessage(
        id: id,
        threadId: threadId,
        address: address,
        body: body ?? this.body,
        encrypted: encrypted ?? this.encrypted,
        direction: direction,
        status: status ?? this.status,
        timestamp: timestamp,
        createdAt: createdAt,
      );
}
