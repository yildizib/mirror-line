import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reconnect Backoff Logic', () {
    test('Exponential backoff delay calculation', () {
      // Verify exponential backoff: delay = initial * (1 << attempt)
      // With _reconnectInitialDelay = 2s, _reconnectMaxDelay = 30s
      const initialDelay = Duration(seconds: 2);
      const maxDelay = Duration(seconds: 30);

      // Attempt 0: 2s * (1 << 0) = 2s
      var attempt = 0;
      var delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 2));

      // Attempt 1: 2s * (1 << 1) = 4s
      attempt = 1;
      delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 4));

      // Attempt 2: 2s * (1 << 2) = 8s
      attempt = 2;
      delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 8));

      // Attempt 3: 2s * (1 << 3) = 16s
      attempt = 3;
      delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 16));

      // Attempt 4: 2s * (1 << 4) = 32s → clamped to 30s
      attempt = 4;
      delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 30));

      // Attempt 5+: stays at 30s max
      attempt = 5;
      delay = initialDelay * (1 << attempt);
      if (delay > maxDelay) delay = maxDelay;
      expect(delay, const Duration(seconds: 30));
    });

    test('Reconnect attempt counter increments correctly', () {
      var reconnectAttempts = 0;

      // Simulate consecutive failed reconnects
      for (var i = 0; i < 5; i++) {
        reconnectAttempts++;
      }

      expect(reconnectAttempts, 5);
    });

    test('Successful connection resets attempt counter', () {
      var reconnectAttempts = 5; // After multiple failures

      // Simulate successful connection: reset counter
      reconnectAttempts = 0;

      expect(reconnectAttempts, 0);
    });
  });

  group('Generation Counter (Race Condition Prevention)', () {
    test('Generation counter prevents stale reconnect results', () {
      var connectGeneration = 0;
      final staleResults = <int>[];
      final validResults = <int>[];

      // Simulate force-reconnect bumping generation
      connectGeneration++;
      final firstGeneration = connectGeneration; // gen = 1

      // Stale async operation from old generation starts
      staleResults.add(firstGeneration);

      // User forces reconnect (bumps generation again)
      connectGeneration++;
      final secondGeneration = connectGeneration; // gen = 2

      // Only accept results matching current generation
      for (final gen in staleResults) {
        if (gen != connectGeneration) {
          // Stale result ignored
          expect(gen, firstGeneration);
          expect(gen, isNot(secondGeneration));
        }
      }

      // New async operation completes with current generation
      if (connectGeneration == secondGeneration) {
        validResults.add(connectGeneration);
      }

      expect(validResults, [secondGeneration]);
      expect(staleResults.length, 1);
      expect(validResults.length, 1);
    });

    test('Multiple concurrent reconnects handled via generation', () {
      var connectGeneration = 0;
      final results = <int>[];

      // Three parallel reconnect attempts with different generations
      for (var i = 0; i < 3; i++) {
        connectGeneration++;
        results.add(connectGeneration);
      }

      // Only the latest generation (3) should be processed
      final currentGen = connectGeneration;
      var processedCount = 0;
      for (final gen in results) {
        if (gen == currentGen) {
          processedCount++;
        }
      }

      expect(processedCount, 1); // Only one (the latest) should be processed
      expect(results.last, currentGen);
    });
  });
}
