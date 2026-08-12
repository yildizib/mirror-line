import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';

/// All mirrored notifications from the same app, grouped so the
/// notifications list can show one row per app instead of one row per
/// notification -- with a count and the most recent timestamp, mirroring
/// [CallGroup]'s shape (call_group_provider.dart).
class NotificationGroup {
  /// The grouping key: the app's package name (see
  /// [NotificationEvent.groupKey]). All events in this group share it.
  final String key;

  /// The app's display name, from the most recent event in the group.
  final String appName;

  /// Every event in this group, newest first.
  final List<NotificationEvent> events;

  NotificationGroup({
    required this.key,
    required this.appName,
    required this.events,
  });

  NotificationEvent get lastEvent => events.first;

  int get count => events.length;
}

/// Derives notification groups from notificationFacadeProvider's flat
/// list, grouped by package name. Sorted with the most recently active
/// group first.
final notificationGroupsProvider = Provider<List<NotificationGroup>>((ref) {
  final events = ref.watch(notificationFacadeProvider);
  final byKey = <String, List<NotificationEvent>>{};

  for (final event in events) {
    (byKey[event.groupKey] ??= []).add(event);
  }

  final groups = byKey.entries.map((entry) {
    final sorted = entry.value.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return NotificationGroup(
      key: entry.key,
      appName: sorted.first.displayName,
      events: sorted,
    );
  }).toList();

  groups.sort(
    (a, b) => b.lastEvent.timestamp.compareTo(a.lastEvent.timestamp),
  );
  return groups;
});
