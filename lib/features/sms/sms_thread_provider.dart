import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/features/sms/sms_list_provider.dart';

/// Every message exchanged with a single address, grouped so the SMS
/// screen can read as a normal conversation list instead of one flat,
/// unordered timeline of every incoming and outgoing message.
class SmsThread {
  final String address;
  final String contactName;
  final List<SmsMessage> messages; // chronological, oldest first

  /// Display name (contact name if resolved, else address, else
  /// placeholder), already localized at thread-build time.
  final String displayName;

  SmsThread({
    required this.address,
    required this.contactName,
    required this.messages,
    required this.displayName,
  });

  SmsMessage get lastMessage => messages.last;
}

/// Derives conversations from smsListProvider's flat list, grouped by
/// address -- native never supplies a real Android thread id (see
/// MirrorLineService, which always sends threadId ""), so address is the
/// only key that reliably ties a reply to the message it answers. Sorted
/// most-recently-active conversation first.
final smsThreadsProvider = Provider<List<SmsThread>>((ref) {
  final messages = ref.watch(smsListProvider);
  final l = appL10n(ref);
  final byAddress = <String, List<SmsMessage>>{};
  for (final m in messages) {
    (byAddress[m.address] ??= []).add(m);
  }

  final threads = byAddress.entries.map((entry) {
    final sorted = entry.value.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final contactName = sorted.reversed
        .map((m) => m.contactName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => '');
    return SmsThread(
      address: entry.key,
      contactName: contactName,
      messages: sorted,
      displayName: contactName.isNotEmpty
          ? contactName
          : (entry.key.isNotEmpty ? entry.key : l.smsUnknownSender),
    );
  }).toList();

  threads.sort((a, b) => b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp));
  return threads;
});
