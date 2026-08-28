import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/presentation/message_presentation_extensions.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'presentation extensions keep localization out of domain models',
    (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final call = CallEvent(
        id: '1',
        direction: 'incoming',
        number: '',
        timestamp: DateTime(2024),
        encrypted: '',
        status: 'missed',
        createdAt: DateTime(2024),
      );
      final sms = SmsMessage(
        id: '1',
        threadId: '1',
        address: '',
        body: '',
        encrypted: '',
        direction: 'incoming',
        status: 'received',
        timestamp: DateTime(2024),
        createdAt: DateTime(2024),
      );
      expect(call.displayName(l), l.callUnknownNumber);
      expect(call.statusLabel(l), l.callStatusMissed);
      expect(sms.displayName(l), l.smsUnknownSender);
      expect(sms.statusLabel(l), l.smsStatusReceived);
    },
  );
}
