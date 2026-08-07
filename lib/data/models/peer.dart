class Peer {
  final String id;
  final String deviceName;
  final String role; // 'main' | 'source'
  final String ip;
  final int port;
  final String key; // base64 AES-256 key
  final DateTime createdAt;

  Peer({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.ip,
    required this.port,
    required this.key,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_name': deviceName,
        'role': role,
        'ip': ip,
        'port': port,
        'key': key,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        deviceName: json['device_name'] as String? ?? 'Bilinmeyen Cihaz',
        role: json['role'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
        key: json['key'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      );

  Peer copyWith({
    String? id,
    String? deviceName,
    String? role,
    String? ip,
    int? port,
    String? key,
    DateTime? createdAt,
  }) =>
      Peer(
        id: id ?? this.id,
        deviceName: deviceName ?? this.deviceName,
        role: role ?? this.role,
        ip: ip ?? this.ip,
        port: port ?? this.port,
        key: key ?? this.key,
        createdAt: createdAt ?? this.createdAt,
      );
}