import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/presentation/message_presentation_mapper.dart';
import 'package:mirrorline/core/services/verification_code_service.dart';

void main() {
  test('domain models do not depend on localization or crypto', () {
    final callModel = File(
      'lib/features/calls/domain/call_event.dart',
    ).readAsStringSync();
    final smsModel = File(
      'lib/features/sms/domain/sms_message.dart',
    ).readAsStringSync();
    final peerModel = File(
      'lib/features/pairing/domain/peer.dart',
    ).readAsStringSync();
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

  test(
    'UI imports only UI services, domain values, and shared presentation',
    () {
      final violations = _dartFilesBelow('lib/features', '/ui/')
          .where((file) {
            final source = file.readAsStringSync();
            return source.contains('/base/') ||
                source.contains('/facade/') ||
                source.contains('/core/services/') ||
                source.contains('/core/telephony/');
          })
          .map((file) => file.path)
          .toList();

      expect(violations, isEmpty, reason: 'Forbidden UI imports: $violations');
    },
  );

  test('UI services never import base or native platform implementations', () {
    final violations = _dartFilesBelow('lib/features', '/ui_service/')
        .where((file) {
          final source = file.readAsStringSync();
          return source.contains('/base/') ||
              source.contains('/core/network/') ||
              source.contains('/core/telephony/');
        })
        .map((file) => file.path)
        .toList();

    expect(
      violations,
      isEmpty,
      reason: 'Forbidden UI-service imports: $violations',
    );
  });

  test('legacy transport and Android bridges have explicit module homes', () {
    expect(
      File(
        'lib/features/sync/base/legacy_lan/'
        'legacy_lan_transport_adapter.dart',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/features/pairing/base/'
        'legacy_pairing_handshake_adapter.dart',
      ).existsSync(),
      isTrue,
    );
    for (final packageName in [
      'bridge',
      'telephony',
      'notifications',
      'lifecycle',
      'runtime',
    ]) {
      expect(
        Directory(
          'android/app/src/main/kotlin/io/github/yildizib/mirrorline/'
          '$packageName',
        ).existsSync(),
        isTrue,
      );
    }
  });
}

Iterable<File> _dartFilesBelow(String root, String pathSegment) =>
    Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path.replaceAll('\\', '/').contains(pathSegment));
