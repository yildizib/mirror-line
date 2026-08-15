import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/call_group_detail_screen.dart';
import 'package:mirrorline/features/home/home_feed_provider.dart';
import 'package:mirrorline/features/notifications/notification_group_detail_screen.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';
import 'package:mirrorline/shared/widgets/date_header.dart';
import 'package:mirrorline/shared/widgets/empty_state.dart';

/// Default landing screen: SMS + Call + Notification events merged into
/// one read-only chronological stream (see homeFeedProvider). Tapping a
/// row opens the same detail screen its dedicated tab would -- no
/// delete/multi-select here, that stays on the per-type screens.
class HomeFeedScreen extends ConsumerWidget {
  const HomeFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(homeFeedPaginatedProvider);
    final items = feedState.items;
    final l = AppLocalizations.of(context);

    if (items.isEmpty && !feedState.isLoading) {
      return EmptyState(icon: Icons.dashboard_outlined, message: l.homeFeedEmpty);
    }

    // items are already sorted newest first by homeFeedProvider. Walk the
    // list and insert a DateHeader between rows whenever the calendar day
    // changes (same HR divider the per-type screens use).
    final children = <Widget>[];
    DateTime? previousDay;
    for (final item in items) {
      final ts = item.timestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (previousDay == null || day != previousDay) {
        if (children.isNotEmpty) children.add(const SizedBox(height: AppSpacing.sm));
        children.add(DateHeader(date: day));
        previousDay = day;
      }
 children.add(const SizedBox(height: AppSpacing.sm));
 children.add(_FeedTile(item: item));
 }
 if (feedState.isLoading) {
 children.add(const SizedBox(height: AppSpacing.md));
 children.add(const Center(
 child: SizedBox(
 width: 24,
 height: 24,
 child: CircularProgressIndicator(strokeWidth: 2),
 ),
 ));
 }

 return NotificationListener<ScrollNotification>(
 onNotification: (notification) {
 if (notification is ScrollEndNotification &&
 !feedState.isLoading &&
 !feedState.hasReachedEnd) {
 final metrics = notification.metrics;
 if (metrics.pixels >= metrics.maxScrollExtent - 500) {
 ref.read(homeFeedPaginatedProvider.notifier).loadMore();
 }
 }
 return false;
 },
 child: ListView(
 padding: const EdgeInsets.all(AppSpacing.md),
 children: children,
 ),
 );
 }
}

class _FeedTile extends StatelessWidget {
  final HomeFeedItem item;

  const _FeedTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final IconData icon;
    final String title;
    final String subtitle;
    final DateTime timestamp;
    final VoidCallback onTap;

    switch (item) {
      case CallFeedItem(:final event):
        icon = event.direction == 'incoming'
            ? Icons.call_received_rounded
            : Icons.call_made_rounded;
        title = event.displayName(l);
        subtitle = event.statusLabel(l);
        timestamp = event.timestamp;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallGroupDetailScreen(groupKey: event.groupKey),
          ),
        );
      case SmsFeedItem(:final message):
        icon = message.direction == 'incoming'
            ? Icons.sms_rounded
            : Icons.send_rounded;
        title = message.displayName(l);
        subtitle = message.body;
        timestamp = message.timestamp;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SmsThreadScreen(address: message.address),
          ),
        );
      case NotificationFeedItem(:final event):
        icon = Icons.notifications_rounded;
        title = event.displayName;
        subtitle = (event.title.isNotEmpty && event.title != event.appName)
            ? '${event.title}: ${event.text}'
            : event.text;
        timestamp = event.timestamp;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                NotificationGroupDetailScreen(packageName: event.packageName),
          ),
        );
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
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
              Text(
                _formatTime(timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
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
    if (sameDay) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
  }
}
