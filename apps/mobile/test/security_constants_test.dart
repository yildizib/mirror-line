import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/security_constants.dart';

void main() {
  test('security policy constants define bounded positive values', () {
    expect(SecurityConstants.protocolVersion, greaterThan(0));
    expect(SecurityConstants.maxFrameBytes, greaterThan(0));
    expect(SecurityConstants.maxJsonBytes, greaterThan(0));
    expect(SecurityConstants.maxPayloadBytes, greaterThan(0));
    expect(SecurityConstants.maxQueueItems, greaterThan(0));
    expect(SecurityConstants.maxQueueItemBytes, greaterThan(0));
    expect(SecurityConstants.maxQueueRetryCount, greaterThan(0));
    expect(SecurityConstants.maxAcceptedMessageIds, greaterThan(0));
  });

  test('nested transport limits remain within their enclosing limits', () {
    expect(
      SecurityConstants.maxPayloadBytes,
      lessThanOrEqualTo(SecurityConstants.maxJsonBytes),
    );
    expect(
      SecurityConstants.maxJsonBytes,
      lessThanOrEqualTo(SecurityConstants.maxFrameBytes),
    );
  });
}
