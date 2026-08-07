import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sms_message.dart';
import '../../providers/connection_provider.dart';
import '../../providers/sms_list_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/sms_card.dart';

class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(smsListProvider);

    if (messages.isEmpty) {
      return const EmptyState(
        icon: Icons.message,
        message: 'Henüz mesaj yok',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
        title: Text(message.address),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Yanıtınızı yazın...',
            border: OutlineInputBorder(),
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
