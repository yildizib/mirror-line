class PaginatedListState<T> {
  final List<T> items;
  final bool isLoading;
  final bool hasReachedEnd;
  final int pageOffset;

  PaginatedListState({
    this.items = const [],
    this.isLoading = false,
    this.hasReachedEnd = false,
    this.pageOffset = 0,
  });

  PaginatedListState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? hasReachedEnd,
    int? pageOffset,
  }) {
    return PaginatedListState<T>(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      pageOffset: pageOffset ?? this.pageOffset,
    );
  }
}

const int kDefaultPageSize = 25;

/// Removes duplicate entries by identity, keeping the first occurrence.
/// Used when merging freshly-fetched rows into an already-loaded paginated
/// list so live updates don't duplicate items.
List<T> dedupeById<T>(List<T> items, String Function(T) idOf) {
  final seen = <String>{};
  return items.where((item) => seen.add(idOf(item))).toList();
}

DateTime yesterdayStart() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
}
