import 'package:flutter/material.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

class SmsBubble extends StatelessWidget {
  final SmsMessage message;

  const SmsBubble({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final isOutgoing = message.direction == 'outgoing';
    final isFailed = message.status == 'failed';

    final bubbleColor = isOutgoing
        ? (isFailed ? colorScheme.errorContainer : colorScheme.primary)
        : colorScheme.surfaceContainerHigh;
    final textColor = isOutgoing
        ? (isFailed ? colorScheme.onErrorContainer : colorScheme.onPrimary)
        : colorScheme.onSurface;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.md),
            topRight: const Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(isOutgoing ? AppRadius.md : 4),
            bottomRight: Radius.circular(isOutgoing ? 4 : AppRadius.md),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.body, style: TextStyle(color: textColor, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              isOutgoing
                  ? '${_formatTime(message.timestamp)} · ${message.statusLabel(l)}'
                  : _formatTime(message.timestamp),
              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
