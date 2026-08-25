class QueueItem {
  final int? id;
  final String type; // 'call' | 'sms'
  final String payload; // encrypted JSON
  final String? dedupeKey;
  final int retryCount;
  final DateTime createdAt;

  QueueItem({
    this.id,
    required this.type,
    required this.payload,
    this.dedupeKey,
    this.retryCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'dedupe_key': dedupeKey,
    'retry_count': retryCount,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] as int?,
    type: json['type'] as String,
    payload: json['payload'] as String,
    dedupeKey: json['dedupe_key'] as String?,
    retryCount: json['retry_count'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
  );

  QueueItem copyWith({int? retryCount}) => QueueItem(
    id: id,
    type: type,
    payload: payload,
    dedupeKey: dedupeKey,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt,
  );
}
