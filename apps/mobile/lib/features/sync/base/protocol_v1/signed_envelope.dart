import 'dart:convert';
import 'dart:typed_data';

import 'package:mirrorline/features/sync/base/protocol_v1/canonical_json.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_error.dart';

class SignedEnvelope {
  const SignedEnvelope({
    required this.protocolVersion,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.recipientUserId,
    required this.recipientDeviceId,
    required this.senderKeyVersion,
    required this.recipientKeyVersion,
    required this.messageId,
    required this.messageType,
    required this.createdAt,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  static const int version = 1;
  static const int maxEncodedSize = 16 * 1024;
  static const int maxCiphertextSize = 8 * 1024;
  static const int nonceLength = 12;
  static const int signatureLength = 64;

  final int protocolVersion;
  final String senderUserId;
  final String senderDeviceId;
  final String recipientUserId;
  final String recipientDeviceId;
  final int senderKeyVersion;
  final int recipientKeyVersion;
  final String messageId;
  final String messageType;
  final int createdAt;
  final String nonce;
  final String ciphertext;
  final String signature;

  SignedEnvelope withSignature(String value) => SignedEnvelope(
    protocolVersion: protocolVersion,
    senderUserId: senderUserId,
    senderDeviceId: senderDeviceId,
    recipientUserId: recipientUserId,
    recipientDeviceId: recipientDeviceId,
    senderKeyVersion: senderKeyVersion,
    recipientKeyVersion: recipientKeyVersion,
    messageId: messageId,
    messageType: messageType,
    createdAt: createdAt,
    nonce: nonce,
    ciphertext: ciphertext,
    signature: value,
  );

  Map<String, Object?> _values({required bool includeSignature}) => {
    'ciphertext': ciphertext,
    'createdAt': createdAt,
    'messageId': messageId,
    'messageType': messageType,
    'nonce': nonce,
    'protocolVersion': protocolVersion,
    'recipientDeviceId': recipientDeviceId,
    'recipientKeyVersion': recipientKeyVersion,
    'recipientUserId': recipientUserId,
    'senderDeviceId': senderDeviceId,
    'senderKeyVersion': senderKeyVersion,
    'senderUserId': senderUserId,
    if (includeSignature) 'signature': signature,
  };

  /// AAD binds routing and key identity to the AEAD ciphertext.
  List<int> authenticatedMetadataBytes() => CanonicalJson.utf8Bytes({
    'createdAt': createdAt,
    'messageId': messageId,
    'messageType': messageType,
    'nonce': nonce,
    'protocolVersion': protocolVersion,
    'recipientDeviceId': recipientDeviceId,
    'recipientKeyVersion': recipientKeyVersion,
    'recipientUserId': recipientUserId,
    'senderDeviceId': senderDeviceId,
    'senderKeyVersion': senderKeyVersion,
    'senderUserId': senderUserId,
  });

  /// The complete unsigned envelope is signed under an explicit domain label.
  List<int> signingBytes() => _domainSeparatedBytes(
    'mirrorline.envelope.v1',
    CanonicalJson.utf8Bytes(_values(includeSignature: false)),
  );

  String encode() => CanonicalJson.encode(_values(includeSignature: true));

  Uint8List nonceBytes() => _decodeBase64(nonce, nonceLength, 'nonce');

  Uint8List ciphertextBytes() =>
      _decodeBase64(ciphertext, maxCiphertextSize, 'ciphertext');

  Uint8List signatureBytes() =>
      _decodeBase64(signature, signatureLength, 'signature');

  void validate({bool requireSignature = true}) {
    if (protocolVersion != version) {
      throw const ProtocolException(
        ProtocolErrorCode.unsupportedVersion,
        'Unsupported protocol version.',
      );
    }
    for (final value in [
      senderUserId,
      senderDeviceId,
      recipientUserId,
      recipientDeviceId,
      messageId,
      messageType,
    ]) {
      if (value.isEmpty || value.length > 256) {
        throw const ProtocolException(
          ProtocolErrorCode.malformedInput,
          'Envelope identifier is invalid.',
        );
      }
    }
    if (senderKeyVersion < 1 || recipientKeyVersion < 1 || createdAt < 0) {
      throw const ProtocolException(
        ProtocolErrorCode.malformedInput,
        'Envelope version or creation time is invalid.',
      );
    }
    nonceBytes();
    final encrypted = ciphertextBytes();
    if (requireSignature && encrypted.length < 16) {
      throw const ProtocolException(
        ProtocolErrorCode.malformedInput,
        'Ciphertext is missing an authentication tag.',
      );
    }
    if (requireSignature) signatureBytes();
  }

  static SignedEnvelope decode(String encoded) {
    if (encoded.length > maxEncodedSize) {
      throw const ProtocolException(
        ProtocolErrorCode.oversizedInput,
        'Envelope exceeds the protocol size limit.',
      );
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic>) _malformed();
      const fields = {
        'protocolVersion',
        'senderUserId',
        'senderDeviceId',
        'recipientUserId',
        'recipientDeviceId',
        'senderKeyVersion',
        'recipientKeyVersion',
        'messageId',
        'messageType',
        'createdAt',
        'nonce',
        'ciphertext',
        'signature',
      };
      if (value.keys.toSet().length != fields.length ||
          !value.keys.toSet().containsAll(fields)) {
        _malformed();
      }
      final envelope = SignedEnvelope(
        protocolVersion: _int(value, 'protocolVersion'),
        senderUserId: _string(value, 'senderUserId'),
        senderDeviceId: _string(value, 'senderDeviceId'),
        recipientUserId: _string(value, 'recipientUserId'),
        recipientDeviceId: _string(value, 'recipientDeviceId'),
        senderKeyVersion: _int(value, 'senderKeyVersion'),
        recipientKeyVersion: _int(value, 'recipientKeyVersion'),
        messageId: _string(value, 'messageId'),
        messageType: _string(value, 'messageType'),
        createdAt: _int(value, 'createdAt'),
        nonce: _string(value, 'nonce'),
        ciphertext: _string(value, 'ciphertext'),
        signature: _string(value, 'signature'),
      );
      envelope.validate();
      return envelope;
    } on ProtocolException {
      rethrow;
    } catch (_) {
      _malformed();
    }
  }

  static String _string(Map<String, dynamic> value, String field) {
    final result = value[field];
    if (result is! String) _malformed();
    return result;
  }

  static int _int(Map<String, dynamic> value, String field) {
    final result = value[field];
    if (result is! int) _malformed();
    return result;
  }

  static Never _malformed() => throw const ProtocolException(
    ProtocolErrorCode.malformedInput,
    'Malformed protocol envelope.',
  );

  static Uint8List _decodeBase64(String value, int maxLength, String field) {
    if (value.length > ((maxLength + 2) ~/ 3) * 4) {
      throw ProtocolException(
        ProtocolErrorCode.oversizedInput,
        '$field exceeds the protocol size limit.',
      );
    }
    if (!RegExp(
      r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
    ).hasMatch(value)) {
      throw ProtocolException(
        ProtocolErrorCode.malformedInput,
        'Invalid $field encoding.',
      );
    }
    try {
      final decoded = Uint8List.fromList(base64Decode(value));
      if (decoded.length != maxLength && field != 'ciphertext') {
        throw ProtocolException(
          ProtocolErrorCode.malformedInput,
          'Invalid $field length.',
        );
      }
      if (decoded.length > maxLength) {
        throw ProtocolException(
          ProtocolErrorCode.oversizedInput,
          '$field exceeds the protocol size limit.',
        );
      }
      return decoded;
    } on ProtocolException {
      rethrow;
    } catch (_) {
      throw ProtocolException(
        ProtocolErrorCode.malformedInput,
        'Invalid $field encoding.',
      );
    }
  }

  static List<int> _domainSeparatedBytes(String domain, List<int> payload) => [
    ...utf8.encode(domain),
    0,
    ...payload,
  ];
}
