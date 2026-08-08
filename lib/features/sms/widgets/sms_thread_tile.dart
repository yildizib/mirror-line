import 'package:flutter/material.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';

class SmsThreadTile extends StatelessWidget {
  final SmsThread thread;
  final VoidCallback onTap;

  const SmsThreadTile({
    required this.thread,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final last = thread.lastMessage;
    final isFailed = last.status == 'failed';
    final isPending = last.status == 'pending';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  _initial(thread.displayName),
                  style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          _formatTime(last.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (last.direction == 'outgoing') ...[
                          Icon(Icons.reply_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            last.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isFailed ? theme.colorScheme.error : colorScheme.onSurfaceVariant,
                              fontWeight: isFailed ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (thread.messages.length > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              '${thread.messages.length}',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String name) => name.isNotEmpty ? name[0].toUpperCase() : '#';

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
  }
}
