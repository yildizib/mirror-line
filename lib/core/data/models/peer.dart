import 'package:mirrorline/core/security/crypto_manager.dart';

class Peer {
  final String id;
  final String deviceName;
  final String role; // 'main' | 'source'
  final String ip;
  final int port;
  final String key; // base64 AES-256 key
  final String publicKey; // base64 Ed25519 public key of the other device
  final DateTime createdAt;

  Peer({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.ip,
    required this.port,
    required this.key,
    required this.publicKey,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_name': deviceName,
    'role': role,
    'ip': ip,
    'port': port,
    'key': key,
    'public_key': publicKey,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    id: json['id'] as String,
    // Not routed through AppLocalizations: this is identity data that
    // gets persisted and shown on *both* devices (which may run
    // different app languages), so it needs a locale-neutral fallback
    // rather than whichever language the writer's device happened to
    // be in -- same reasoning as peer_provider.dart's _getDeviceName().
    deviceName: json['device_name'] as String? ?? 'Unknown Device',
    role: json['role'] as String,
    ip: json['ip'] as String,
    port: json['port'] as int,
    key: json['key'] as String,
    publicKey: json['public_key'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
  );

  Peer copyWith({
    String? id,
    String? deviceName,
    String? role,
    String? ip,
    int? port,
    String? key,
    String? publicKey,
    DateTime? createdAt,
  }) => Peer(
    id: id ?? this.id,
    deviceName: deviceName ?? this.deviceName,
    role: role ?? this.role,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    key: key ?? this.key,
    publicKey: publicKey ?? this.publicKey,
    createdAt: createdAt ?? this.createdAt,
  );

  String get verificationCode {
    // Deprecated: use CryptoManager.verificationCodeFromKey instead.
    // This getter is kept for compatibility but delegates to the
    // cryptographically sound SHA-256-based method.
    // ignore: deprecated_member_use_from_same_package
    return CryptoManager.verificationCodeFromKey(key, id);
  }
}
