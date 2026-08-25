import 'package:mirrorline/core/security/crypto_manager.dart';

class LocalPairingIdentity {
  final String id;
  final String deviceName;
  final String role;
  final String publicKey;
  final String ip;
  final int port;
  final String keyBase64;

  const LocalPairingIdentity({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.publicKey,
    required this.ip,
    required this.port,
    required this.keyBase64,
  });

  String get qrData => '$id|$ip|$port|$keyBase64|$deviceName|$role|$publicKey';

  String get verificationCode =>
      CryptoManager.verificationCodeFromKey(keyBase64, id);
}
