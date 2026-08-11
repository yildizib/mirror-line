import 'package:mirrorline/l10n/app_localizations.dart';

class CallEvent {
  final String id;
  final String direction; // 'incoming' | 'outgoing'
  final String number;
  final String contactName; // resolved from the address book; '' if unknown
  final DateTime timestamp;
  final String encrypted; // base64 ciphertext
  // 'ringing' (still active, can be rejected) | 'answered' | 'missed' |
  // 'rejected' | 'ended' (was answered, now finished) | 'failed'
  final String status;
  final DateTime createdAt;

  CallEvent({
    required this.id,
    required this.direction,
    required this.number,
    this.contactName = '',
    required this.timestamp,
    required this.encrypted,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction,
    'number': number,
    'contact_name': contactName,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'encrypted': encrypted,
    'status': status,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory CallEvent.fromJson(Map<String, dynamic> json) => CallEvent(
    id: json['id'] as String,
    direction: json['direction'] as String,
    number: json['number'] as String,
    contactName: json['contact_name'] as String? ?? '',
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    encrypted: json['encrypted'] as String,
    status: json['status'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
  );

  CallEvent copyWith({String? status, String? number, String? contactName}) =>
      CallEvent(
        id: id,
        direction: direction,
        number: (number != null && number.isNotEmpty) ? number : this.number,
        contactName: (contactName != null && contactName.isNotEmpty)
            ? contactName
            : this.contactName,
        timestamp: timestamp,
        encrypted: encrypted,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  /// Locale-independent grouping identity for the calls list (contact name
  /// if resolved, else the raw number, else '' so all "unknown number"
  /// calls still land in one group as before) -- deliberately not the
  /// (localized) [displayName] text, so grouping doesn't depend on the
  /// active language.
  String get groupKey => contactName.isNotEmpty ? contactName : number;

  /// Display name for UI/notifications: contact name if resolved, else the
  /// raw phone number, else a placeholder when neither is known (the
  /// carrier/OS never delivered a number for this call).
  String displayName(AppLocalizations l) {
    if (contactName.isNotEmpty) return contactName;
    if (number.isNotEmpty) return number;
    return l.callUnknownNumber;
  }

  /// Status label shared by the calls list UI and notifications.
  String statusLabel(AppLocalizations l) => switch (status) {
    'ringing' => l.callStatusRinging,
    'answered' => l.callStatusAnswered,
    'missed' => l.callStatusMissed,
    'rejected' => l.callStatusRejected,
    'ended' => l.callStatusEnded,
    'failed' => l.callStatusFailed,
    _ => status,
  };
}
