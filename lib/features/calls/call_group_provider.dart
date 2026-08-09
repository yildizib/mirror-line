import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/features/calls/call_list_provider.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

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

  CallGroup({required this.key, required this.displayName, required this.calls});

  CallEvent get lastCall => calls.first;

  int get count => calls.length;

  /// True when there's still a ringing call in the group -- the calls list
  /// uses this to keep showing the reject button on the grouped row.
  bool get hasActive => calls.any((c) => c.status == 'ringing');

  /// Aggregated status label for the group row: if any call is still
  /// ringing, that; otherwise the most recent call's status.
  String statusLabel(AppLocalizations l) {
    if (hasActive) return l.callStatusRinging;
    return lastCall.statusLabel(l);
  }
}

/// Derives call groups from callListProvider's flat list, grouped by
/// identity (contact name -> number -> unknown). Sorted with the most
/// recently active group first.
final callGroupsProvider = Provider<List<CallGroup>>((ref) {
  final calls = ref.watch(callListProvider);
  final l = appL10n(ref);
  final byKey = <String, List<CallEvent>>{};

  for (final call in calls) {
    (byKey[call.groupKey] ??= []).add(call);
  }

  final groups = byKey.entries.map((entry) {
    final sorted = entry.value.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return CallGroup(
      key: entry.key,
      displayName: sorted.first.displayName(l),
      calls: sorted,
    );
  }).toList();

  groups.sort((a, b) => b.lastCall.timestamp.compareTo(a.lastCall.timestamp));
  return groups;
});