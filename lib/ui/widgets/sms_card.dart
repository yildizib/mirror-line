import 'package:flutter/material.dart';

import '../../data/models/sms_message.dart';

class SmsCard extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback onReply;

  const SmsCard({
    required this.message,
    required this.onReply,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncoming = message.direction == 'incoming';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isIncoming ? theme.colorScheme.primaryContainer : Colors.green[100],
          child: Icon(Icons.message, color: isIncoming ? theme.colorScheme.primary : Colors.green),
        ),
        title: Text(
          message.address,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatTime(message.timestamp)} · ${message.status}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.reply, color: theme.colorScheme.primary),
          onPressed: onReply,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
