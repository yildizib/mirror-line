import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/presentation/message_presentation_extensions.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:mirrorline/shared/pagination/grouped_paginated_notifier.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

/// All calls from the same number (or the same unknown-number placeholder
/// when no number was resolved), grouped so the calls list can show one
/// row per caller instead of one row per call -- with a count and the most
/// recent timestamp, like a normal phone app's recents tab.
class CallGroup {
  /// The grouping key: contact name if known, else the raw number, else ''
  /// for unresolved calls (see [CallEvent.groupKey]). All calls in this
  /// group share this identity.
  final String key;

  /// Display name (contact name if resolved, else number, else placeholder),
  /// already localized at group-build time.
  final String displayName;

  /// Every call in this group, newest first.
  final List<CallEvent> calls;

  CallGroup({
    required this.key,
    required this.displayName,
    required this.calls,
  });

  CallEvent get lastCall => calls.first;

  int get count => calls.length;

  /// The currently ringing call, if any. The UI uses the same event both to
  /// decide whether Reject is available and to target that action.
  CallEvent? get activeCall =>
      calls.where((c) => c.status == 'ringing').firstOrNull;

  bool get hasActive => activeCall != null;

  /// Aggregated status label for the group row: if any call is still
  /// ringing, that; otherwise the most recent call's status.
  String statusLabel(AppLocalizations l) {
    if (hasActive) return l.callStatusRinging;
    return lastCall.statusLabel(l);
  }
}

/// Derives call groups from callFacadeProvider's flat list, grouped by
/// identity (contact name -> number -> unknown). Sorted with the most
/// recently active group first.
final callGroupsProvider = Provider<List<CallGroup>>((ref) {
  final calls = ref.watch(callFacadeProvider);
  final l = appL10n(ref);
  final byKey = <String, List<CallEvent>>{};

  for (final call in calls) {
    (byKey[call.groupKey] ??= []).add(call);
  }

  final groups = byKey.entries.map((entry) {
    final sorted = entry.value.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return CallGroup(
      key: entry.key,
      displayName: sorted.first.displayName(l),
      calls: sorted,
    );
  }).toList();

  groups.sort((a, b) => b.lastCall.timestamp.compareTo(a.lastCall.timestamp));
  return groups;
});

/// Paginated version of [callGroupsProvider].
/// Loads today+yesterday first (capped at 25 groups), then older
/// groups on [CallGroupPaginated.loadMore].
final callGroupsPaginatedProvider =
    StateNotifierProvider<CallGroupPaginated, PaginatedListState<CallGroup>>((
      ref,
    ) {
      final notifier = CallGroupPaginated(ref);
      Future.microtask(() => notifier.loadInitial());
      ref.listen(callFacadeProvider, (_, _) {
        Future.microtask(() => notifier.refresh());
      });
      return notifier;
    });

class CallGroupPaginated
    extends GroupedPaginatedNotifier<CallEvent, CallGroup> {
  CallGroupPaginated(super.ref);

  @override
  Future<List<CallEvent>> fetchRecent({required int limit}) {
    final facade = ref.read(callFacadeProvider.notifier);
    return facade.loadRecent(limit: limit, since: yesterdayStart());
  }

  @override
  Future<List<CallEvent>> fetchOlder({
    required int limit,
    required int offset,
  }) {
    final facade = ref.read(callFacadeProvider.notifier);
    return facade.loadOlder(
      limit: limit,
      offset: offset,
      before: yesterdayStart(),
    );
  }

  @override
  String groupKeyOf(CallEvent event) => event.groupKey;

  @override
  String groupKeyOfGroup(CallGroup group) => group.key;

  @override
  List<CallEvent> eventsOfGroup(CallGroup group) => group.calls;

  @override
  bool isRecentEvent(CallEvent event) =>
      !event.timestamp.isBefore(yesterdayStart());

  @override
  CallGroup buildGroup(String key, List<CallEvent> events) {
    final l = appL10n(ref);
    final sorted = events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return CallGroup(
      key: key,
      displayName: sorted.first.displayName(l),
      calls: sorted,
    );
  }

  @override
  DateTime groupTimestamp(CallGroup group) => group.lastCall.timestamp;

  @override
  List<CallGroup> mergeGroups(
    List<CallGroup> existing,
    List<CallGroup> newGroups,
  ) {
    final freshIds = newGroups
        .expand((group) => group.calls)
        .map((call) => call.id)
        .toSet();
    final map = <String, CallGroup>{};
    for (final g in existing) {
      final retained = g.calls
          .where((call) => !freshIds.contains(call.id))
          .toList();
      if (retained.isNotEmpty) {
        map[g.key] = CallGroup(
          key: g.key,
          displayName: g.displayName,
          calls: retained,
        );
      }
    }
    for (final g in newGroups) {
      final prev = map[g.key];
      if (prev != null) {
        final merged = dedupeById([...g.calls, ...prev.calls], (c) => c.id)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        map[g.key] = CallGroup(
          key: g.key,
          displayName: g.displayName,
          calls: merged,
        );
      } else {
        map[g.key] = g;
      }
    }
    final result = map.values.toList()
      ..sort((a, b) => b.lastCall.timestamp.compareTo(a.lastCall.timestamp));
    return result;
  }
}
