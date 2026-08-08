import 'package:flutter/material.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/theme/theme.dart';

class CallCard extends StatelessWidget {
  final CallEvent event;
  final VoidCallback onReject;

  const CallCard({
    required this.event,
    required this.onReject,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.call_rounded, color: colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.number,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(event.timestamp),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.call_end_rounded),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.6),
                foregroundColor: colorScheme.error,
              ),
              onPressed: onReject,
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
