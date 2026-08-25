import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/pairing/pairing_endpoint_selector.dart';

void main() {
  const localIps = ['192.168.1.10', '2001:db8::1'];

  test('preserves a valid claimed endpoint', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: '10.8.0.4',
      liveIp: '10.8.0.4',
      fallbackIp: null,
      port: 45678,
      localIps: localIps,
    );

    expect(selection.ip, '10.8.0.4');
    expect(selection.diagnostic, isNull);
  });

  test('preserves claim-first behavior across multiple networks', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.accept,
      claimedIp: '10.8.0.4',
      liveIp: '192.168.1.20',
      fallbackIp: '172.20.10.2',
      port: 45678,
      localIps: localIps,
    );

    expect(selection.ip, '10.8.0.4');
    expect(selection.diagnostic?.issue, PairingEndpointIssue.staleClaim);
  });

  test('replaces a locally owned claim with the live endpoint', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: '192.168.1.10',
      liveIp: '192.168.1.20',
      fallbackIp: null,
      port: 45678,
      localIps: localIps,
    );

    expect(selection.ip, '192.168.1.20');
    expect(selection.diagnostic?.issue, PairingEndpointIssue.locallyOwnedClaim);
  });

  test('replaces a malformed claim with the live endpoint', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: {'ip': '192.168.1.20'},
      liveIp: '192.168.1.20',
      fallbackIp: null,
      port: 45678,
      localIps: localIps,
    );

    expect(selection.ip, '192.168.1.20');
    expect(selection.diagnostic?.issue, PairingEndpointIssue.invalidClaim);
  });

  test('uses a validated QR fallback for an unsafe accept claim', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.accept,
      claimedIp: '127.0.0.1',
      liveIp: null,
      fallbackIp: '192.168.1.20',
      port: 45678,
      localIps: localIps,
    );

    expect(selection.ip, '192.168.1.20');
    expect(selection.diagnostic?.issue, PairingEndpointIssue.invalidClaim);
  });

  test('fails when no endpoint is usable', () {
    final selection = selectPairingEndpoint(
      stage: PairingEndpointStage.request,
      claimedIp: '192.168.1.10',
      liveIp: '127.0.0.1',
      fallbackIp: null,
      port: 45678,
      localIps: localIps,
    );

    expect(selection.isUsable, false);
    expect(selection.diagnostic?.issue, PairingEndpointIssue.noUsableEndpoint);
  });
}
