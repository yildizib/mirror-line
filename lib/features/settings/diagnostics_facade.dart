import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';

enum TestEventType { call, sms, notification }

/// One "Run Tests" attempt, for the diagnostics screen's per-session log.
class TestRunRecord {
  final TestEventType type;
  final DateTime timestamp;

  /// true = sent immediately, false = queued for later delivery (peer
  /// currently unreachable) -- see ConnectionFacade.sendOrQueue.
  final bool delivered;

  TestRunRecord({
    required this.type,
    required this.timestamp,
    required this.delivered,
  });
}

final diagnosticsFacadeProvider =
    StateNotifierProvider<DiagnosticsFacade, List<TestRunRecord>>((ref) {
      return DiagnosticsFacade(ref);
    });

/// Orchestrates issue #42's "Run Tests" button: broadcasts one fake
/// call/SMS/notification event through the real facade send pipeline to
/// the paired device, and keeps an in-memory (not persisted -- a fresh
/// launch starts empty, which is the expected "did it work just now"
/// behavior) log of what was attempted.
class DiagnosticsFacade extends StateNotifier<List<TestRunRecord>> {
  final Ref _ref;

  DiagnosticsFacade(this._ref) : super(const []);

  /// Sequential (not Future.wait) so the log's insertion order matches
  /// the actual send order, and so ConnectionFacade's offline-queue
  /// writes (if disconnected) don't race each other.
  Future<void> runTests() async {
    final l = appL10n(_ref);

    final callSent = await _ref
        .read(callFacadeProvider.notifier)
        .sendCallNotification(
          'MIRRORLINE-TEST',
          contactName: l.runTestsCallLabel,
        );
    _record(TestEventType.call, callSent);

    final smsSent = await _ref
        .read(smsFacadeProvider.notifier)
        .sendSmsNotification('MIRRORLINE-TEST', l.runTestsSmsBody);
    _record(TestEventType.sms, smsSent);

    final notificationSent = await _ref
        .read(notificationFacadeProvider.notifier)
        .sendTestNotification(
          appName: l.runTestsNotificationApp,
          title: l.runTestsNotificationTitle,
          text: l.runTestsNotificationBody,
        );
    _record(TestEventType.notification, notificationSent);
  }

  void _record(TestEventType type, bool delivered) {
    state = [
      TestRunRecord(
        type: type,
        timestamp: DateTime.now(),
        delivered: delivered,
      ),
      ...state,
    ];
  }
}
