import 'dart:convert';

import 'package:mirrorline/features/sync/base/protocol_v1/protocol_error.dart';

/// RFC 8785-compatible serialization for the protocol's deliberately small
/// value domain: null, bool, integer, string, lists, and string-keyed maps.
///
/// Protocol values intentionally do not permit floating point numbers. This
/// avoids cross-runtime number rendering ambiguities in signed data.
class CanonicalJson {
  static String encode(Object? value) {
    final output = StringBuffer();
    _write(value, output);
    return output.toString();
  }

  static List<int> utf8Bytes(Object? value) => utf8.encode(encode(value));

  static void _write(Object? value, StringBuffer output) {
    switch (value) {
      case null:
        output.write('null');
      case bool value:
        output.write(value ? 'true' : 'false');
      case int value:
        output.write(value);
      case String value:
        output.write(jsonEncode(value));
      case List<Object?> value:
        output.write('[');
        for (var index = 0; index < value.length; index++) {
          if (index > 0) output.write(',');
          _write(value[index], output);
        }
        output.write(']');
      case Map<String, Object?> value:
        output.write('{');
        final keys = value.keys.toList()..sort();
        for (var index = 0; index < keys.length; index++) {
          if (index > 0) output.write(',');
          final key = keys[index];
          output.write(jsonEncode(key));
          output.write(':');
          _write(value[key], output);
        }
        output.write('}');
      case double _:
        throw const ProtocolException(
          ProtocolErrorCode.malformedInput,
          'Protocol JSON does not support floating point values.',
        );
      default:
        throw ProtocolException(
          ProtocolErrorCode.malformedInput,
          'Unsupported protocol JSON value: ${value.runtimeType}.',
        );
    }
  }
}
