class InboxRecord {
  final String sourcePeerId;
  final String messageId;
  final String type;
  final String processingState;
  final DateTime receivedAt;
  final DateTime updatedAt;

  const InboxRecord({
    required this.sourcePeerId,
    required this.messageId,
    required this.type,
    this.processingState = 'received',
    required this.receivedAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'source_peer_id': sourcePeerId,
    'message_id': messageId,
    'type': type,
    'processing_state': processingState,
    'received_at': receivedAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory InboxRecord.fromJson(Map<String, dynamic> json) => InboxRecord(
    sourcePeerId: json['source_peer_id'] as String,
    messageId: json['message_id'] as String,
    type: json['type'] as String,
    processingState: json['processing_state'] as String,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(json['received_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
  );
}
