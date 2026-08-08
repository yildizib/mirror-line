import 'package:flutter/material.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';

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
    final colorScheme = theme.colorScheme;
    final status = theme.status;
    final isIncoming = message.direction == 'incoming';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isIncoming ? colorScheme.primaryContainer : status.successContainer,
              child: Icon(
                isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded,
                color: isIncoming ? colorScheme.primary : status.success,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(message.timestamp)} · ${message.status}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.reply_rounded),
              onPressed: onReply,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
