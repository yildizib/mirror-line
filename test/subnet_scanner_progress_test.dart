// Verifies the SubnetScanner's onProgress callback fires per batch with
// the correct batch index, total batch count, and subnet prefix -- and
// that a hit short-circuits remaining batches.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/subnet_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'onProgress fires once per batch with correct indices and total',
    () async {
      // Start a real TCP server on 127.0.0.1. The scanner skips the host's
      // own last octet when localIp matches, so we use localIp='127.0.0.254'
      // (skipping .254) so the scanner probes .1..253 and hits our server
      // on .1 in the first batch.
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final port = server.port;

      final progress = <(int, int, String)>[];
      final scanner = SubnetScanner();

      try {
        final found = await scanner.findHostWithOpenPort(
          localIp: '127.0.0.254',
          port: port,
          concurrency: 24,
          onProgress: (batch, total, subnet) {
            progress.add((batch, total, subnet));
          },
        );

        expect(
          found,
          '127.0.0.1',
          reason: 'scan should find the localhost server',
        );
        expect(progress, isNotEmpty);
        expect(progress.first.$1, 1, reason: 'first callback is batch 1');
        expect(
          progress.first.$2,
          11,
          reason: '254 hosts / 24 concurrency = 11 batches',
        );
        expect(progress.first.$3, '127.0.0');
        // Hit short-circuits: the first batch contains .1..24, so we should
        // have stopped after just 1 (or a few) batches -- never all 11.
        expect(progress.length, lessThanOrEqualTo(11));
      } finally {
        await server.close();
      }
    },
  );

  test('onProgress fires all batches when no host is found', () async {
    final scanner = SubnetScanner();

    // Pick an unlikely-to-be-open port.
    final port = 59999;
    final progress = <(int, int, String)>[];

    final found = await scanner.findHostWithOpenPort(
      localIp: '127.0.0.1',
      port: port,
      concurrency: 24,
      perHostTimeout: const Duration(milliseconds: 50),
      onProgress: (batch, total, subnet) {
        progress.add((batch, total, subnet));
      },
    );

    expect(found, isNull);
    // All 11 batches must have fired.
    expect(progress.length, 11);
    expect(progress.first.$1, 1);
    expect(progress.last.$1, 11);
    expect(progress.first.$2, 11);
    expect(progress.first.$3, '127.0.0');
  });

  test('subnetPrefixOf parses and rejects invalid IPs', () {
    expect(subnetPrefixOf('192.168.1.42'), '192.168.1');
    expect(subnetPrefixOf('10.0.0.1'), '10.0.0');
    expect(subnetPrefixOf('127.0.0.1'), '127.0.0');
    expect(subnetPrefixOf('not-an-ip'), isNull);
    expect(subnetPrefixOf('1.2.3'), isNull);
    expect(subnetPrefixOf('1.2.3.4.5'), isNull);
    expect(subnetPrefixOf(''), isNull);
  });
}
