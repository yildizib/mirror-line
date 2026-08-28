import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/presentation/message_presentation_mapper.dart';
import 'package:mirrorline/core/services/verification_code_service.dart';

void main() {
  test('domain models do not depend on localization or crypto', () {
    final callModel = File(
      'lib/core/data/models/call_event.dart',
    ).readAsStringSync();
    final smsModel = File(
      'lib/core/data/models/sms_message.dart',
    ).readAsStringSync();
    final peerModel = File('lib/core/data/models/peer.dart').readAsStringSync();
    expect(callModel, isNot(contains('app_localizations.dart')));
    expect(smsModel, isNot(contains('app_localizations.dart')));
    expect(peerModel, isNot(contains('crypto_manager.dart')));
  });

  test('presentation and verification services are injectable contracts', () {
    expect(const MessagePresentationMapper(), isA<MessagePresentationMapper>());
    expect(
      const CryptoVerificationCodeService(),
      isA<VerificationCodeService>(),
    );
  });
}
