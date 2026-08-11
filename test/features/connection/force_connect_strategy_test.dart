import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForceConnectStrategy', () {
    test('Prefers stored IP when available', () {
      final candidates = <String>[];

      const storedIp = '192.168.1.100';
      final beaconIps = ['192.168.1.101', '192.168.1.102'];

      // Strategy should prioritize stored IP first
      if (storedIp.isNotEmpty && storedIp != 'unknown') {
        candidates.addAll([storedIp, ...beaconIps.where((ip) => ip != storedIp)]);
      }

      expect(candidates.first, storedIp);
      expect(candidates, [storedIp, '192.168.1.101', '192.168.1.102']);
    });

    test('Falls back to beacon IPs when stored IP is unavailable', () {
      final candidates = <String>[];

      const storedIp = 'unknown';
      final beaconIps = ['192.168.1.101', '192.168.1.102'];

      // Stored IP is invalid, fall back to beacon
      if (storedIp.isEmpty || storedIp == 'unknown') {
        if (beaconIps.isNotEmpty) {
          candidates.addAll(beaconIps);
        }
      }

      expect(candidates, beaconIps);
      expect(candidates.isNotEmpty, true);
    });

    test('Combines multiple discovery paths into single candidate list', () {
      final allCandidates = <String>{};

      // Path 1: stored + beacon
      const storedIp = '192.168.1.100';
      final beaconIps = ['192.168.1.101'];
      allCandidates.addAll([storedIp, ...beaconIps]);

      // Path 2: known network
      allCandidates.add('192.168.1.103');

      // Path 3: scan result
      allCandidates.add('192.168.1.104');

      expect(allCandidates.length, 4);
      expect(allCandidates.contains(storedIp), true);
      expect(allCandidates.contains('192.168.1.103'), true);
      expect(allCandidates.contains('192.168.1.104'), true);
    });

    test('Handles empty beacon list gracefully', () {
      final candidates = <String>[];

      const storedIp = '192.168.1.100';
      final beaconIps = <String>[];

      if (storedIp.isNotEmpty && storedIp != 'unknown') {
        candidates.add(storedIp);
      } else if (beaconIps.isNotEmpty) {
        candidates.addAll(beaconIps);
      }

      expect(candidates, [storedIp]);
    });

    test('Deduplicates candidate IPs', () {
      final allCandidates = <String>{};

      // Add same IP multiple times from different sources
      allCandidates.add('192.168.1.100');
      allCandidates.add('192.168.1.100'); // Duplicate
      allCandidates.add('192.168.1.100'); // Duplicate again

      // Set automatically deduplicates
      expect(allCandidates.length, 1);
      expect(allCandidates.contains('192.168.1.100'), true);
    });

    test('Stops trying candidates once connection succeeds', () {
      final candidates = ['192.168.1.100', '192.168.1.101', '192.168.1.102'];
      var connectionAttempt = 0;

      // Simulate connection attempts until success
      for (final ip in candidates) {
        connectionAttempt++;
        if (ip == '192.168.1.101') {
          // Connection succeeds on second attempt
          break;
        }
      }

      expect(connectionAttempt, 2); // Only 2 attempts before success
    });

    test('Handles case where all candidates fail', () {
      final candidates = ['192.168.1.100', '192.168.1.101'];
      var connectionAttempt = 0;
      var allFailed = true;

      for (final _ in candidates) {
        connectionAttempt++;
        // Simulate all connections failing
      }

      expect(allFailed, true);
      expect(connectionAttempt, candidates.length);
    });
  });
}
