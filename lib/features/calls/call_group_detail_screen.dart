import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/presentation/message_presentation_extensions.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/call_group_provider.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/shared/widgets/selectable_list_scaffold.dart';

/// Shows every individual call in a [CallGroup], each with its own
/// timestamp and status -- opened by tapping a grouped row on the calls
/// list when a caller has called more than once.
///
/// Takes the group's key (not the CallGroup itself) and re-derives the
/// live group from [callGroupsProvider] on every build, so deletes on
/// this screen are reflected immediately instead of showing a stale
/// snapshot until the screen is reopened.
class CallGroupDetailScreen extends ConsumerWidget {
  final String groupKey;

  const CallGroupDetailScreen({required this.groupKey, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final groups = ref.watch(callGroupsProvider);

    CallGroup? group;
    for (final g in groups) {
      if (g.key == groupKey) {
        group = g;
        break;
      }
    }

    // The group can disappear entirely if every call in it was deleted --
    // pop back to the calls list instead of rendering an empty screen.
    if (group == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.maybePop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final resolvedGroup = group;

    return SelectableListScaffold<CallEvent>(
      items: resolvedGroup.calls,
      itemKey: (event) => event.id,
      dateHeaderOf: (event) => event.timestamp,
      itemBuilder: (context, event, isSelecting, isSelected, onTapSelect) =>
          _CallDetailTile(
            event: event,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
          ),
      // Unreachable in practice: a group with zero calls doesn't exist in
      // callGroupsProvider, so `group` would already be null above.
      emptyMessage: l.callsEmpty,
      useAppBarEntryPoint: true,
      nonSelectingTitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(resolvedGroup.displayName, style: const TextStyle(fontSize: 17)),
          Text(
            l.callsCallCount(resolvedGroup.count),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      selectModeTooltip: l.commonSelect,
      selectedCountLabel: (count) => l.callsSelectedCount(count),
      deleteTooltip: l.commonDeleteSelected,
      deleteTitle: l.callsDeleteSelected,
      deleteConfirm: (selected) => l.callsDeleteOne(selected.length),
      deletedMessage: l.callsDeleted,
      onDeleteSelected: (context, selected) async {
        await ref
            .read(callFacadeProvider.notifier)
            .removeMany(selected.map((e) => e.id));
      },
    );
  }
}

class _CallDetailTile extends StatelessWidget {
  final CallEvent event;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;

  const _CallDetailTile({
    required this.event,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.status;
    final l = AppLocalizations.of(context);

    final statusColor = switch (event.status) {
      'answered' => statusColors.success,
      'missed' => statusColors.warning,
      'rejected' => colorScheme.error,
      'ringing' => statusColors.success,
      _ => colorScheme.onSurfaceVariant,
    };

    final tile = Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              event.direction == 'incoming'
                  ? Icons.call_received_rounded
                  : Icons.call_made_rounded,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatFullTime(event.timestamp, context),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.statusLabel(l),
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelecting)
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
          ],
        ),
      ),
    );

    if (!isSelecting) return tile;
    return GestureDetector(
      onTap: onTapSelect,
      behavior: HitTestBehavior.opaque,
      child: tile,
    );
  }

  String _formatFullTime(DateTime time, BuildContext context) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final l = AppLocalizations.of(context);
    if (sameDay) return '${l.commonToday} $hh:$mm';
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}.${time.year} $hh:$mm';
  }
}
