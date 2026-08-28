import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';

class MessagePresentationMapper {
  const MessagePresentationMapper();

  String callDisplayName(CallEvent event, AppLocalizations l) =>
      event.contactName.isNotEmpty
      ? event.contactName
      : event.number.isNotEmpty
      ? event.number
      : l.callUnknownNumber;

  String callStatus(CallEvent event, AppLocalizations l) =>
      switch (event.status) {
        'ringing' => l.callStatusRinging,
        'answered' => l.callStatusAnswered,
        'missed' => l.callStatusMissed,
        'rejected' => l.callStatusRejected,
        'ended' => l.callStatusEnded,
        'failed' => l.callStatusFailed,
        _ => event.status,
      };

  String smsDisplayName(SmsMessage message, AppLocalizations l) =>
      message.contactName.isNotEmpty
      ? message.contactName
      : message.address.isNotEmpty
      ? message.address
      : l.smsUnknownSender;

  String smsStatus(SmsMessage message, AppLocalizations l) =>
      switch (message.status) {
        'received' => l.smsStatusReceived,
        'sent' => l.smsStatusSent,
        'delivered' => l.smsStatusDelivered,
        'pending' => l.smsStatusSending,
        'failed' => l.smsStatusFailed,
        _ => message.status,
      };
}
