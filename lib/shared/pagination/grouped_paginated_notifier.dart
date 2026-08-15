import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

/// Base notifier for paginated + grouped lists (calls by contact,
/// notifications by app).
///
/// Flow:
/// 1. [loadInitial] fetches today+yesterday events (date-filtered).
///    Groups them. Shows up to 25 groups. Remembers the rest.
/// 2. [loadMore] first drains remaining today+yesterday groups.
///    If exhausted, re-fetches recent with a larger window to get
///    more today+yesterday events (some may form new groups).
///    If today+yesterday is fully exhausted, fetches older events
///    (before yesterday) via [fetchOlder] with offset pagination.
abstract class GroupedPaginatedNotifier<E, G>
    extends StateNotifier<PaginatedListState<G>> {
  GroupedPaginatedNotifier(this.ref) : super(PaginatedListState<G>());

  final Ref ref;

  int get rawPageSize => kDefaultPageSize * 5;

  Future<List<E>> fetchRecent({required int limit});
  Future<List<E>> fetchOlder({required int limit, required int offset});
  String groupKeyOf(E event);
  G buildGroup(String key, List<E> events);
  DateTime groupTimestamp(G group);
  List<G> mergeGroups(List<G> existing, List<G> newGroups);

  List<G> _remainingGroups = [];
  bool _hasMoreRecent = false;
  bool _exhaustedOlder = false;
  int _recentLimit = 0;

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);

    try {
      _recentLimit = rawPageSize;
      final raw = await fetchRecent(limit: _recentLimit);
      final allGroups = _groupAndSort(raw);
      _hasMoreRecent = raw.length >= _recentLimit;
      final visible = allGroups.length > kDefaultPageSize
          ? kDefaultPageSize
          : allGroups.length;
      _remainingGroups = allGroups.sublist(visible);
      final reachedEnd = !_hasMoreRecent && _remainingGroups.isEmpty;
      state = PaginatedListState<G>(
        items: allGroups.sublist(0, visible),
        isLoading: false,
        hasReachedEnd: reachedEnd,
        pageOffset: 0,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.hasReachedEnd) return;
    state = state.copyWith(isLoading: true);

    try {
      if (_remainingGroups.isNotEmpty) {
        final take = _remainingGroups.length > kDefaultPageSize
            ? kDefaultPageSize
            : _remainingGroups.length;
        final next = _remainingGroups.sublist(0, take);
        _remainingGroups = _remainingGroups.sublist(take);
        final merged = mergeGroups(state.items, next);
        state = state.copyWith(
          items: merged,
          isLoading: false,
          hasReachedEnd:
              _remainingGroups.isEmpty && !_hasMoreRecent && _exhaustedOlder,
        );
        return;
      }

      if (_hasMoreRecent) {
        _recentLimit += rawPageSize;
        final raw = await fetchRecent(limit: _recentLimit);
        final allGroups = _groupAndSort(raw);
        _hasMoreRecent = raw.length >= _recentLimit;
        final visible = allGroups.length > kDefaultPageSize
            ? kDefaultPageSize
            : allGroups.length;
        _remainingGroups = allGroups.sublist(visible);
        final reachedEnd =
            !_hasMoreRecent && _remainingGroups.isEmpty && _exhaustedOlder;
        state = PaginatedListState<G>(
          items: allGroups.sublist(0, visible),
          isLoading: false,
          hasReachedEnd: reachedEnd,
          pageOffset: 0,
        );
        return;
      }

      final raw = await fetchOlder(
        limit: rawPageSize,
        offset: state.pageOffset,
      );
      final newGroups = _groupAndSort(raw);
      final merged = mergeGroups(state.items, newGroups);
      final hasReachedEnd = raw.length < rawPageSize;
      _exhaustedOlder = hasReachedEnd;
      state = PaginatedListState<G>(
        items: merged,
        isLoading: false,
        hasReachedEnd: hasReachedEnd,
        pageOffset: state.pageOffset + raw.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  List<G> _groupAndSort(List<E> raw) {
    final map = <String, List<E>>{};
    for (final e in raw) {
      final key = groupKeyOf(e);
      map.putIfAbsent(key, () => []).add(e);
    }
    final groups = map.entries.map((e) => buildGroup(e.key, e.value)).toList();
    groups.sort((a, b) => groupTimestamp(b).compareTo(groupTimestamp(a)));
    return groups;
  }
}
