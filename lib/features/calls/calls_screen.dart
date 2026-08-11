import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/call_group_detail_screen.dart';
import 'package:mirrorline/features/calls/call_group_provider.dart';
import 'package:mirrorline/features/calls/call_list_provider.dart';
import 'package:mirrorline/features/connection/connection_provider.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(callGroupsProvider);
    final l = AppLocalizations.of(context);

    if (groups.isEmpty) {
      return EmptyState(icon: Icons.call_end_rounded, message: l.callsEmpty);
    }

    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final group = groups[index];
          final isSelected = _selected.contains(group.key);
          return _GroupedCallCard(
            group: group,
            isSelecting: _selecting,
            isSelected: isSelected,
            onTapSelect: () => _toggleSelect(group.key),
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
          );
        },
      ),
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              ),
              title: Text(l.callsSelectedCount(_selected.length)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_rounded),
                  tooltip: l.commonDeleteSelected,
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _deleteSelected(context, groups),
                ),
              ],
            )
          : null,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: l.callsSelectMode,
              onPressed: () => setState(() => _selecting = true),
              child: const Icon(Icons.checklist_rounded),
            ),
    );
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _deleteSelected(BuildContext context, List<CallGroup> groups) {
    final selectedGroups = groups
        .where((g) => _selected.contains(g.key))
        .toList();
    final ids = <String>{};
    for (final g in selectedGroups) {
      ids.addAll(g.calls.map((c) => c.id));
    }
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.callsDeleteSelected),
        content: Text(
          l.callsDeleteConfirmBody(selectedGroups.length, ids.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              await ref
                  .read(callListProvider.notifier)
                  .removeMany(ids.toList());
              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l.callsDeleted)));
              }
              _exitSelectionMode();
            },
            child: Text(
              l.commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _handleReject(BuildContext context, WidgetRef ref, CallEvent call) {
    ref.read(callListProvider.notifier).updateStatus(call.id, 'rejected');

    ref.read(connectionProvider.notifier).sendCallRejected(call.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).callsRejected)),
    );
  }
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
