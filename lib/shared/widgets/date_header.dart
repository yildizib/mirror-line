import 'package:flutter/material.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

/// A divider with a centered date label, inserted between rows of a
/// chronological list wherever the calendar day changes (see
/// date_grouped_list.dart and SelectableListScaffold's dateHeaderOf).
class DateHeader extends StatelessWidget {
  final DateTime date;

  const DateHeader({required this.date, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _labelFor(date, AppLocalizations.of(context));

    return Row(
      children: [
        Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
      ],
    );
  }

  String _labelFor(DateTime date, AppLocalizations l) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return l.commonToday;
    if (day == yesterday) return l.commonYesterday;
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}
