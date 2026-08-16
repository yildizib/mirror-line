class QueueItem {
  final int? id;
  final String messageId;
  final String destinationPeerId;
  final String type; // 'call' | 'sms'
  final String payload; // encrypted JSON
  final int retryCount;
  final String status;
  final DateTime? nextAttemptAt;
  final DateTime createdAt;

  QueueItem({
    this.id,
    required this.messageId,
    required this.destinationPeerId,
    required this.type,
    required this.payload,
    this.retryCount = 0,
    this.status = 'pending',
    this.nextAttemptAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'message_id': messageId,
    'destination_peer_id': destinationPeerId,
    'type': type,
    'payload': payload,
    'status': status,
    'attempt_count': retryCount,
    'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] as int?,
    messageId: json['message_id'] as String,
    destinationPeerId: json['destination_peer_id'] as String,
    type: json['type'] as String,
    payload: json['payload'] as String,
    retryCount: json['attempt_count'] as int,
    status: json['status'] as String,
    nextAttemptAt: (json['next_attempt_at'] as int?) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(json['next_attempt_at'] as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
  );

  QueueItem copyWith({int? retryCount}) => QueueItem(
    id: id,
    messageId: messageId,
    destinationPeerId: destinationPeerId,
    type: type,
    payload: payload,
    retryCount: retryCount ?? this.retryCount,
    status: status,
    nextAttemptAt: nextAttemptAt,
    createdAt: createdAt,
  );
}
