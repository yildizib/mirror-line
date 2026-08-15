import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/notifications/notification_group_detail_screen.dart';
import 'package:mirrorline/features/notifications/notification_group_provider.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';
import 'package:mirrorline/shared/widgets/selectable_list_scaffold.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

 @override
 Widget build(BuildContext context, WidgetRef ref) {
 final groupsState = ref.watch(notificationGroupsPaginatedProvider);
 final groups = groupsState.items;
 final l = AppLocalizations.of(context);

 return SelectableListScaffold(
 items: groups,
 itemKey: (group) => group.key,
 dateHeaderOf: (group) => group.lastEvent.timestamp,
 onLoadMore: ref.read(notificationGroupsPaginatedProvider.notifier).loadMore,
 isLoadingMore: groupsState.isLoading,
 hasReachedEnd: groupsState.hasReachedEnd,
 itemBuilder: (context, group, isSelecting, isSelected, onTapSelect) =>
 _GroupedNotificationCard(
            group: group,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NotificationGroupDetailScreen(packageName: group.key),
              ),
            ),
          ),
      emptyMessage: l.notificationsEmpty,
      emptyBuilder: (context) => EmptyState(
        icon: Icons.notifications_none_rounded,
        message: l.notificationsEmpty,
      ),
      selectModeTooltip: l.notificationsSelectMode,
      selectedCountLabel: (count) => l.notificationsSelectedCount(count),
      deleteTooltip: l.commonDeleteSelected,
      deleteTitle: l.notificationsDeleteSelected,
      deleteConfirm: (selectedGroups) => l.notificationsDeleteConfirmBody(
        _flattenEventIds(selectedGroups).length,
      ),
      deletedMessage: l.notificationsDeleted,
      onDeleteSelected: (context, selectedGroups) async {
        await ref
            .read(notificationFacadeProvider.notifier)
            .removeMany(_flattenEventIds(selectedGroups));
      },
    );
  }
}

Set<String> _flattenEventIds(List<NotificationGroup> groups) {
  final ids = <String>{};
  for (final g in groups) {
    ids.addAll(g.events.map((e) => e.id));
  }
  return ids;
}

/// One row per app (grouped). Multi-notification groups show a count
/// badge, same visual language as _GroupedCallCard.
class _GroupedNotificationCard extends StatelessWidget {
  final NotificationGroup group;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;
  final VoidCallback? onTap;

  const _GroupedNotificationCard({
    required this.group,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final last = group.lastEvent;
    final multi = group.count > 1;
    final subtitle = (last.title.isNotEmpty && last.title != last.appName)
        ? '${last.title}: ${last.text}'
        : last.text;

    return Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: isSelecting ? onTapSelect : onTap,
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
                child: Icon(
                  Icons.notifications_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.appName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  _formatTime(last.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} '
        '$hh:$mm';
  }
}
