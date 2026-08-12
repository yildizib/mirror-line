import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/notifications/notification_group_provider.dart';
import 'package:mirrorline/shared/widgets/selectable_list_scaffold.dart';

/// Shows every individual notification from one app -- opened by tapping a
/// grouped row on the notifications list. Same "pass only the key,
/// re-derive live, auto-pop on empty" pattern as CallGroupDetailScreen.
class NotificationGroupDetailScreen extends ConsumerWidget {
  final String packageName;

  const NotificationGroupDetailScreen({
    required this.packageName,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final groups = ref.watch(notificationGroupsProvider);

    NotificationGroup? group;
    for (final g in groups) {
      if (g.key == packageName) {
        group = g;
        break;
      }
    }

    // The group can disappear entirely if every notification in it was
    // deleted or dismissed -- pop back to the list instead of rendering
    // an empty screen.
    if (group == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.maybePop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final resolvedGroup = group;

    return SelectableListScaffold<NotificationEvent>(
      items: resolvedGroup.events,
      itemKey: (event) => event.id,
      dateHeaderOf: (event) => event.timestamp,
      itemBuilder: (context, event, isSelecting, isSelected, onTapSelect) =>
          _NotificationDetailTile(
            event: event,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onTapSelect: onTapSelect,
          ),
      // Unreachable in practice: a group with zero events doesn't exist in
      // notificationGroupsProvider, so `group` would already be null above.
      emptyMessage: l.notificationsEmpty,
      useAppBarEntryPoint: true,
      nonSelectingTitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(resolvedGroup.appName, style: const TextStyle(fontSize: 17)),
          Text(
            l.notificationsEventCount(resolvedGroup.count),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      selectModeTooltip: l.commonSelect,
      selectedCountLabel: (count) => l.notificationsSelectedCount(count),
      deleteTooltip: l.commonDeleteSelected,
      deleteTitle: l.notificationsDeleteSelected,
      deleteConfirm: (selected) => l.notificationsDeleteOne(selected.length),
      deletedMessage: l.notificationsDeleted,
      onDeleteSelected: (context, selected) async {
        await ref
            .read(notificationFacadeProvider.notifier)
            .removeMany(selected.map((e) => e.id));
      },
    );
  }
}

class _NotificationDetailTile extends StatelessWidget {
  final NotificationEvent event;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onTapSelect;

  const _NotificationDetailTile({
    required this.event,
    this.isSelecting = false,
    this.isSelected = false,
    this.onTapSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = (event.title.isNotEmpty && event.title != event.appName)
        ? '${event.title}: ${event.text}'
        : event.text;

    final tile = Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.notifications_rounded,
              color: colorScheme.onSurfaceVariant,
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
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
