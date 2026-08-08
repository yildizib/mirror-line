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

  bool get _isActive => event.status == 'ringing';

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
                    event.displayName,
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
            if (_isActive)
              IconButton.filledTonal(
                icon: const Icon(Icons.call_end_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.6),
                  foregroundColor: colorScheme.error,
                ),
                onPressed: onReject,
              )
            else
              _StatusChip(event: event),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  final CallEvent event;

  const _StatusChip({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.status;

    final color = switch (event.status) {
      'answered' => statusColors.success,
      'missed' => statusColors.warning,
      'rejected' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final label = event.statusLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
