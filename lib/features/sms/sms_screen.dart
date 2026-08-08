import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/connection/connection_provider.dart';
import 'package:mirrorline/features/sms/sms_list_provider.dart';
import 'package:mirrorline/features/sms/widgets/sms_card.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(smsListProvider);

    if (messages.isEmpty) {
      return const EmptyState(
        icon: Icons.message_rounded,
        message: 'Henüz mesaj yok',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final message = messages[index];
        return SmsCard(
          message: message,
          onReply: () => _showReplyDialog(context, ref, message),
        );
      },
    );
  }

  void _showReplyDialog(BuildContext context, WidgetRef ref, SmsMessage message) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.displayName),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Yanıtınızı yazın...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final reply = SmsMessage(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  threadId: message.threadId,
                  address: message.address,
                  body: text,
                  encrypted: '',
                  direction: 'outgoing',
                  status: 'pending',
                  timestamp: DateTime.now(),
                  createdAt: DateTime.now(),
                );
                ref.read(smsListProvider.notifier).add(reply);

                // Send to peer device via socket
                ref.read(connectionProvider.notifier).sendReplySms(
                  message.address,
                  text,
                  id: reply.id,
                );

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mesaj gönderildi')),
                );
              }
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }
}
