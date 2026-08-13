class NotificationEvent {
  final String id;
  // Native's own stable per-notification key (sbn.key) -- used to match a
  // dismissal (onNotificationRemoved) back to the right stored event.
  final String nativeId;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final String encrypted; // base64 ciphertext
  final DateTime timestamp;
  final DateTime createdAt;

  NotificationEvent({
    required this.id,
    required this.nativeId,
    required this.packageName,
    this.appName = '',
    this.title = '',
    this.text = '',
    required this.encrypted,
    required this.timestamp,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'native_id': nativeId,
    'package_name': packageName,
    'app_name': appName,
    'title': title,
    'text': text,
    'encrypted': encrypted,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory NotificationEvent.fromJson(Map<String, dynamic> json) =>
      NotificationEvent(
        id: json['id'] as String,
        nativeId: json['native_id'] as String,
        packageName: json['package_name'] as String,
        appName: json['app_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        encrypted: json['encrypted'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] as int,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['created_at'] as int,
        ),
      );

  /// Grouping identity for the notifications list -- one group per app.
  String get groupKey => packageName;

  /// Display name for UI: the app's name, else the raw package name if the
  /// app name never resolved.
  String get displayName => appName.isNotEmpty ? appName : packageName;
}
