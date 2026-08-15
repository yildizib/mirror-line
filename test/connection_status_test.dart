// Verifies the ConnectionStatus discovery/force-connect live progress
// fields and the ConnectionStatusNotifier methods that drive them.
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/connection/connection_status_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initial status is idle with empty log', () {
    final notifier = ConnectionStatusNotifier();
    final status = notifier.state;
    expect(status.discoveryState, DiscoveryState.idle);
    expect(status.discoveryDetail, isNull);
    expect(status.forceConnectActive, isFalse);
    expect(status.discoveryLog, isEmpty);
  });

  test('beginForceConnect clears log and sets active flag', () {
    final notifier = ConnectionStatusNotifier();
    // Seed some prior log entries to ensure beginForceConnect clears them.
    notifier.logDiscovery('old entry 1');
    notifier.logDiscovery('old entry 2');
    expect(notifier.state.discoveryLog, hasLength(2));

    notifier.beginForceConnect();

    expect(notifier.state.forceConnectActive, isTrue);
    expect(
      notifier.state.discoveryLog,
      isEmpty,
      reason: 'new session starts clean',
    );
    expect(notifier.state.discoveryState, DiscoveryState.idle);
    expect(notifier.state.discoveryDetail, isNull);
  });

  test('endForceConnect clears active flag and detail but keeps state', () {
    final notifier = ConnectionStatusNotifier();
    notifier.beginForceConnect();
    notifier.setDiscoveryState(
      DiscoveryState.connecting,
      detail: 'Connecting to 1.2.3.4',
    );
    notifier.endForceConnect();

    expect(notifier.state.forceConnectActive, isFalse);
    expect(notifier.state.discoveryDetail, isNull);
    // If we were connecting, state flips to connected; otherwise stays.
    expect(notifier.state.discoveryState, DiscoveryState.connected);
  });

  test('setDiscoveryState updates state and detail', () {
    final notifier = ConnectionStatusNotifier();
    notifier.setDiscoveryState(
      DiscoveryState.scanningSubnet,
      detail: 'Scanning batch 3/11',
    );

    expect(notifier.state.discoveryState, DiscoveryState.scanningSubnet);
    expect(notifier.state.discoveryDetail, 'Scanning batch 3/11');
  });

  test('logDiscovery appends entries with timestamps and flags', () {
    final notifier = ConnectionStatusNotifier();
    notifier.logDiscovery('Trying stored IP...');
    notifier.logDiscovery('Failed', isError: true);
    notifier.logDiscovery('Connected!', isSuccess: true);

    expect(notifier.state.discoveryLog, hasLength(3));
    expect(notifier.state.discoveryLog[0].message, 'Trying stored IP...');
    expect(notifier.state.discoveryLog[0].isSuccess, isFalse);
    expect(notifier.state.discoveryLog[0].isError, isFalse);

    expect(notifier.state.discoveryLog[1].message, 'Failed');
    expect(notifier.state.discoveryLog[1].isError, isTrue);

    expect(notifier.state.discoveryLog[2].message, 'Connected!');
    expect(notifier.state.discoveryLog[2].isSuccess, isTrue);
  });

  test('logDiscovery trims to last 50 entries', () {
    final notifier = ConnectionStatusNotifier();
    for (var i = 0; i < 60; i++) {
      notifier.logDiscovery('entry $i');
    }
    expect(notifier.state.discoveryLog, hasLength(50));
    // Oldest entries removed, newest kept.
    expect(notifier.state.discoveryLog.first.message, 'entry 10');
    expect(notifier.state.discoveryLog.last.message, 'entry 59');
  });

  test('recordConnectAttempt increments count and sets error', () {
    final notifier = ConnectionStatusNotifier();
    notifier.recordConnectAttempt(
      ConnectionErrorCode.connectFailed,
      errorDetail: '1.2.3.4:45678',
    );

    expect(notifier.state.connectAttempts, 1);
    expect(notifier.state.lastErrorCode, ConnectionErrorCode.connectFailed);
    expect(notifier.state.lastErrorDetail, '1.2.3.4:45678');

    notifier.recordConnectAttempt(null);
    expect(notifier.state.connectAttempts, 2);
    expect(notifier.state.lastErrorCode, isNull);
    expect(notifier.state.lastErrorDetail, isNull);
  });

  test('discovery state transitions match a typical force-connect flow', () {
    final notifier = ConnectionStatusNotifier();

    // User presses button.
    notifier.beginForceConnect();
    expect(notifier.state.discoveryState, DiscoveryState.idle);

    // Trying stored IP.
    notifier.setDiscoveryState(
      DiscoveryState.tryingStoredIp,
      detail: 'Trying 1.2.3.4...',
    );
    notifier.logDiscovery('Trying stored IP 1.2.3.4...');
    expect(notifier.state.discoveryState, DiscoveryState.tryingStoredIp);

    // Fails -> scanning.
    notifier.setDiscoveryState(
      DiscoveryState.scanningSubnet,
      detail: 'Scanning 192.168.1.0/24 (batch 1/11)',
    );
    notifier.logDiscovery('Stored IP failed', isError: true);
    notifier.logDiscovery('Scanning subnet...');
    expect(notifier.state.discoveryState, DiscoveryState.scanningSubnet);

    // Scan finds host -> connecting.
    notifier.setDiscoveryState(
      DiscoveryState.connecting,
      detail: 'Connecting to 192.168.1.99...',
    );
    notifier.logDiscovery('Scan found 192.168.1.99', isSuccess: true);
    expect(notifier.state.discoveryState, DiscoveryState.connecting);

    // Connected.
    notifier.setDiscoveryState(
      DiscoveryState.connected,
      detail: 'Connected to 192.168.1.99',
    );
    notifier.logDiscovery('Connected!', isSuccess: true);
    notifier.endForceConnect();

    expect(notifier.state.forceConnectActive, isFalse);
    expect(notifier.state.discoveryState, DiscoveryState.connected);
    expect(notifier.state.discoveryLog, hasLength(5));
  });
}
