import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/shared/pagination/grouped_paginated_notifier.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

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

  groups.sort((a, b) => b.lastEvent.timestamp.compareTo(a.lastEvent.timestamp));
  return groups;
});

/// Paginated version of [notificationGroupsProvider].
/// Loads today+yesterday first (capped at 25 groups), then older
/// groups on [NotificationGroupPaginated.loadMore].
final notificationGroupsPaginatedProvider =
    StateNotifierProvider<
      NotificationGroupPaginated,
      PaginatedListState<NotificationGroup>
    >((ref) {
      final notifier = NotificationGroupPaginated(ref);
      Future.microtask(() => notifier.loadInitial());
      ref.listen(notificationFacadeProvider, (_, _) {
        Future.microtask(() => notifier.refresh());
      });
      return notifier;
    });

class NotificationGroupPaginated
    extends GroupedPaginatedNotifier<NotificationEvent, NotificationGroup> {
  NotificationGroupPaginated(super.ref);

  @override
  Future<List<NotificationEvent>> fetchRecent({required int limit}) {
    final facade = ref.read(notificationFacadeProvider.notifier);
    return facade.loadRecent(limit: limit, since: yesterdayStart());
  }

  @override
  Future<List<NotificationEvent>> fetchOlder({
    required int limit,
    required int offset,
  }) {
    final facade = ref.read(notificationFacadeProvider.notifier);
    return facade.loadOlder(
      limit: limit,
      offset: offset,
      before: yesterdayStart(),
    );
  }

  @override
  String groupKeyOf(NotificationEvent event) => event.groupKey;

  @override
  NotificationGroup buildGroup(String key, List<NotificationEvent> events) {
    final sorted = events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return NotificationGroup(
      key: key,
      appName: sorted.first.displayName,
      events: sorted,
    );
  }

  @override
  DateTime groupTimestamp(NotificationGroup group) => group.lastEvent.timestamp;

  @override
  List<NotificationGroup> mergeGroups(
    List<NotificationGroup> existing,
    List<NotificationGroup> newGroups,
  ) {
    final map = <String, NotificationGroup>{};
    for (final g in existing) {
      map[g.key] = g;
    }
    for (final g in newGroups) {
      final prev = map[g.key];
      if (prev != null) {
        final merged = dedupeById([...g.events, ...prev.events], (e) => e.id)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        map[g.key] = NotificationGroup(
          key: g.key,
          appName: g.appName,
          events: merged,
        );
      } else {
        map[g.key] = g;
      }
    }
    final result = map.values.toList()
      ..sort((a, b) => b.lastEvent.timestamp.compareTo(a.lastEvent.timestamp));
    return result;
  }

  @override
  List<NotificationGroup> replaceRecentGroups(
    List<NotificationGroup> existing,
    List<NotificationGroup> fresh,
  ) {
    final cutoff = yesterdayStart();
    final freshByKey = {for (final group in fresh) group.key: group};
    final result = <NotificationGroup>[];
    for (final group in existing) {
      final recent = freshByKey.remove(group.key);
      final older = group.events
          .where((event) => event.timestamp.isBefore(cutoff))
          .toList();
      if (recent != null) {
        final events = [...recent.events, ...older]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        result.add(
          NotificationGroup(
            key: recent.key,
            appName: recent.appName,
            events: events,
          ),
        );
      } else if (older.isNotEmpty) {
        result.add(
          NotificationGroup(
            key: group.key,
            appName: group.appName,
            events: older,
          ),
        );
      }
    }
    result.addAll(freshByKey.values);
    result.sort(
      (a, b) => b.lastEvent.timestamp.compareTo(a.lastEvent.timestamp),
    );
    return result;
  }
}
