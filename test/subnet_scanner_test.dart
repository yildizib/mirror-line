import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';

void main() {
  group('subnetPrefixOf', () {
    test('extracts the first three octets of a valid IPv4 address', () {
      expect(subnetPrefixOf('192.168.1.42'), '192.168.1');
      expect(subnetPrefixOf('10.0.0.1'), '10.0.0');
    });

    test('returns null for malformed input', () {
      expect(subnetPrefixOf(''), isNull);
      expect(subnetPrefixOf('not-an-ip'), isNull);
      expect(subnetPrefixOf('192.168.1'), isNull);
      expect(subnetPrefixOf('192.168.1.1.1'), isNull);
    });
  });
}
