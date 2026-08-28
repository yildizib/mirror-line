import 'package:mirrorline/core/security/crypto_manager.dart';

abstract interface class VerificationCodeService {
  String fromKey(
    String keyBase64,
    String peerId, {
    Iterable<String> expectedPublicKeys,
  });
}

class CryptoVerificationCodeService implements VerificationCodeService {
  const CryptoVerificationCodeService();

  @override
  String fromKey(
    String keyBase64,
    String peerId, {
    Iterable<String> expectedPublicKeys = const [],
  }) => CryptoManager.verificationCodeFromKey(
    keyBase64,
    peerId,
    expectedPublicKeys: expectedPublicKeys,
  );
}
