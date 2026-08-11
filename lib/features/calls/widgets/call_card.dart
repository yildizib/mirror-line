import 'package:flutter/material.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

class CallCard extends StatelessWidget {
  final CallEvent event;
  final VoidCallback onReject;

  /// When true the card shows a checkbox overlay and a tap toggles
  /// selection instead of any single-call action.
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;

  const CallCard({
    required this.event,
    required this.onReject,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
    super.key,
  });

  bool get _isActive => event.status == 'ringing';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final card = Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (isSelecting)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ),
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
                    event.displayName(l),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(event.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_isActive && !isSelecting)
              IconButton.filledTonal(
                icon: const Icon(Icons.call_end_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer.withValues(
                    alpha: 0.6,
                  ),
                  foregroundColor: colorScheme.error,
                ),
                onPressed: onReject,
              )
            else if (!isSelecting)
              _StatusChip(event: event),
          ],
        ),
      ),
    );

    if (!isSelecting) return card;

    return GestureDetector(
      onTap: onTapSelect,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (sameDay) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  final CallEvent event;

  const _StatusChip({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.status;
    final l = AppLocalizations.of(context);

    final color = switch (event.status) {
      'answered' => statusColors.success,
      'missed' => statusColors.warning,
      'rejected' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final label = event.statusLabel(l);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
