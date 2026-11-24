import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_gateway.dart';
import 'package:mirrorline/features/pairing/domain/server_pairing_models.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_crypto.dart';

abstract interface class ServerPairingProofSigner {
  Future<String> sign(
    PairingProofTranscript transcript,
    ServerPairingRole localRole,
  );
}

/// Signs only the domain-separated v1 transcript. The private key stays in
/// the injected signer implementation and is never serialized into a request.
class Ed25519ServerPairingProofSigner implements ServerPairingProofSigner {
  Ed25519ServerPairingProofSigner(this._keyPair);

  final SimpleKeyPair _keyPair;
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<String> sign(
    PairingProofTranscript transcript,
    ServerPairingRole localRole,
  ) async {
    if (!transcript.isComplete) {
      throw const ServerPairingApiException('MALFORMED_RESPONSE');
    }
    final localIdentity = localRole == ServerPairingRole.main
        ? transcript.main
        : transcript.source;
    final publicKey = await _keyPair.extractPublicKey();
    final fingerprint = base64UrlEncode(
      (await Sha256().hash(publicKey.bytes)).bytes,
    ).replaceAll('=', '');
    if (localIdentity.keyFingerprint != fingerprint) {
      throw const ServerPairingApiException('MALFORMED_RESPONSE');
    }
    final signature = await _algorithm.sign(
      ProtocolCrypto.pairingTranscriptBytes(transcript.canonicalFields()),
      keyPair: _keyPair,
    );
    return base64UrlEncode(signature.bytes).replaceAll('=', '');
  }
}
