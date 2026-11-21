import 'package:mirrorline/features/calls/domain/call_event.dart';
import 'package:mirrorline/features/sms/domain/sms_message.dart';
import 'package:mirrorline/core/presentation/message_presentation_mapper.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

extension CallEventPresentation on CallEvent {
  String displayName(AppLocalizations l) =>
      const MessagePresentationMapper().callDisplayName(this, l);
  String statusLabel(AppLocalizations l) =>
      const MessagePresentationMapper().callStatus(this, l);
}

extension SmsMessagePresentation on SmsMessage {
  String displayName(AppLocalizations l) =>
      const MessagePresentationMapper().smsDisplayName(this, l);
  String statusLabel(AppLocalizations l) =>
      const MessagePresentationMapper().smsStatus(this, l);
}
