import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Produces the same positive OS notification id in every process/device for
/// the same logical notification namespace and key.
int stableNotificationId(String namespace, String key) {
  final digest = sha256.convert(utf8.encode('$namespace\u0000$key')).bytes;
  final data = ByteData.sublistView(Uint8List.fromList(digest));
  return data.getUint32(0) & 0x7fffffff;
}
