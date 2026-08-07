class CallEvent {
  final String id;
  final String direction; // 'incoming' | 'outgoing'
  final String number;
  final DateTime timestamp;
  final String encrypted; // base64 ciphertext
  final String status; // 'delivered' | 'rejected' | 'failed'
  final DateTime createdAt;

  CallEvent({
    required this.id,
    required this.direction,
    required this.number,
    required this.timestamp,
    required this.encrypted,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction,
        'number': number,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'encrypted': encrypted,
        'status': status,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory CallEvent.fromJson(Map<String, dynamic> json) => CallEvent(
        id: json['id'] as String,
        direction: json['direction'] as String,
        number: json['number'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        encrypted: json['encrypted'] as String,
        status: json['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      );

  CallEvent copyWith({String? status}) => CallEvent(
        id: id,
        direction: direction,
        number: number,
        timestamp: timestamp,
        encrypted: encrypted,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
