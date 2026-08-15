import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/call_group_detail_screen.dart';
import 'package:mirrorline/features/calls/call_group_provider.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';
import 'package:mirrorline/shared/widgets/selectable_list_scaffold.dart';

class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

 @override
 Widget build(BuildContext context, WidgetRef ref) {
 final groupsState = ref.watch(callGroupsPaginatedProvider);
 final groups = groupsState.items;
 final l = AppLocalizations.of(context);

 return SelectableListScaffold(
 items: groups,
 itemKey: (group) => group.key,
 dateHeaderOf: (group) => group.lastCall.timestamp,
 onLoadMore: ref.read(callGroupsPaginatedProvider.notifier).loadMore,
 isLoadingMore: groupsState.isLoading,
 hasReachedEnd: groupsState.hasReachedEnd,
 itemBuilder: (context, group, isSelecting, isSelected, onTapSelect) =>
 _GroupedCallCard(
            group: group,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onReject: () => _handleReject(context, ref, group.lastCall),
            onTap: () {
              if (group.count > 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallGroupDetailScreen(groupKey: group.key),
                  ),
                );
              }
            },
          ),
      emptyMessage: l.callsEmpty,
      emptyBuilder: (context) =>
          EmptyState(icon: Icons.call_end_rounded, message: l.callsEmpty),
      selectModeTooltip: l.callsSelectMode,
      selectedCountLabel: (count) => l.callsSelectedCount(count),
      deleteTooltip: l.commonDeleteSelected,
      deleteTitle: l.callsDeleteSelected,
      deleteConfirm: (selectedGroups) => l.callsDeleteConfirmBody(
        selectedGroups.length,
        _flattenCallIds(selectedGroups).length,
      ),
      deletedMessage: l.callsDeleted,
      onDeleteSelected: (context, selectedGroups) async {
        await ref
            .read(callFacadeProvider.notifier)
            .removeMany(_flattenCallIds(selectedGroups));
      },
    );
  }

  void _handleReject(BuildContext context, WidgetRef ref, CallEvent call) {
    ref.read(callFacadeProvider.notifier).updateStatus(call.id, 'rejected');

    ref.read(connectionFacadeProvider.notifier).sendCallRejected(call.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).callsRejected)),
    );
  }
}

Set<String> _flattenCallIds(List<CallGroup> groups) {
  final ids = <String>{};
  for (final g in groups) {
    ids.addAll(g.calls.map((c) => c.id));
  }
  return ids;
}

/// One row per caller (grouped). Single-call groups render like a normal
/// call card; multi-call groups show a count badge and open the detail
/// screen on tap.
class _GroupedCallCard extends StatelessWidget {
  final CallGroup group;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;
  final VoidCallback onReject;
  final VoidCallback? onTap;

  const _GroupedCallCard({
    required this.group,
    required this.onReject,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final last = group.lastCall;
    final multi = group.count > 1;

    final card = Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: isSelecting ? onTapSelect : (multi ? onTap : null),
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
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outline,
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
                      group.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(last.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${group.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (group.hasActive && !isSelecting)
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
                _StatusChip(
                  label: group.statusLabel(l),
                  color: _statusColor(theme, last.status),
                ),
            ],
          ),
        ),
      ),
    );

    return card;
  }

  Color _statusColor(ThemeData theme, String status) {
    final statusColors = theme.status;
    return switch (status) {
      'answered' => statusColors.success,
      'missed' => statusColors.warning,
      'rejected' => theme.colorScheme.error,
      'ringing' => statusColors.success,
      _ => theme.colorScheme.onSurfaceVariant,
    };
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
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
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
