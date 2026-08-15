import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

/// One entry in the unified Home Feed -- wraps a call, SMS or mirrored
/// notification event so the feed can merge and sort all three by
/// timestamp without caring which kind each one is.
sealed class HomeFeedItem {
  DateTime get timestamp;

  String get id;
}

class CallFeedItem extends HomeFeedItem {
  final CallEvent event;

  CallFeedItem(this.event);

  @override
  DateTime get timestamp => event.timestamp;

  @override
  String get id => event.id;
}

class SmsFeedItem extends HomeFeedItem {
  final SmsMessage message;

  SmsFeedItem(this.message);

  @override
  DateTime get timestamp => message.timestamp;

  @override
  String get id => message.id;
}

class NotificationFeedItem extends HomeFeedItem {
  final NotificationEvent event;

  NotificationFeedItem(this.event);

  @override
  DateTime get timestamp => event.timestamp;

  @override
  String get id => event.id;
}

/// Merges callFacadeProvider + smsFacadeProvider + notificationFacadeProvider
/// into one chronological stream, newest first. Read-only by design (see
/// HomeFeedScreen) -- this is a flat view for browsing, not a place to
/// mutate any of the three underlying lists.
final homeFeedProvider = Provider<List<HomeFeedItem>>((ref) {
  final calls = ref.watch(callFacadeProvider);
  final sms = ref.watch(smsFacadeProvider);
  final notifications = ref.watch(notificationFacadeProvider);

  final items = <HomeFeedItem>[
    ...calls.map(CallFeedItem.new),
    ...sms.map(SmsFeedItem.new),
    ...notifications.map(NotificationFeedItem.new),
  ];
  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
});

/// Paginated home feed. Source pages are retained until displayed so offsets
/// never skip records that were fetched in a larger cross-source batch.
final homeFeedPaginatedProvider =
    StateNotifierProvider<HomeFeedPaginated, PaginatedListState<HomeFeedItem>>((
      ref,
    ) {
      final notifier = HomeFeedPaginated(ref);
      Future.microtask(() => notifier.loadInitial());
      ref.listen(callFacadeProvider, (_, _) {
        Future.microtask(() => notifier.refresh());
      });
      ref.listen(smsFacadeProvider, (_, _) {
        Future.microtask(() => notifier.refresh());
      });
      ref.listen(notificationFacadeProvider, (_, _) {
        Future.microtask(() => notifier.refresh());
      });
      return notifier;
    });

class HomeFeedPaginated
    extends StateNotifier<PaginatedListState<HomeFeedItem>> {
  HomeFeedPaginated(this.ref) : super(PaginatedListState<HomeFeedItem>());

  final Ref ref;
  final List<HomeFeedItem> _remaining = [];
  bool _callsExhausted = false;
  bool _smsExhausted = false;
  bool _notificationsExhausted = false;

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final since = yesterdayStart();
      final callFuture = ref
          .read(callFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);
      final smsFuture = ref
          .read(smsFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);
      final notifFuture = ref
          .read(notificationFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);

      final calls = await callFuture;
      final sms = await smsFuture;
      final notifications = await notifFuture;

      final merged = _mergeAndSort(calls, sms, notifications);
      final visible = merged.length.clamp(0, kDefaultPageSize);
      _remaining
        ..clear()
        ..addAll(merged.skip(visible));
      _callsExhausted = calls.length < kDefaultPageSize;
      _smsExhausted = sms.length < kDefaultPageSize;
      _notificationsExhausted = notifications.length < kDefaultPageSize;
      state = PaginatedListState<HomeFeedItem>(
        items: merged.sublist(0, visible),
        isLoading: false,
        hasReachedEnd:
            _remaining.isEmpty &&
            _callsExhausted &&
            _smsExhausted &&
            _notificationsExhausted,
        pageOffset: 0,
      );
      _callOffset = calls.length;
      _smsOffset = sms.length;
      _notifOffset = notifications.length;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.hasReachedEnd) return;
    state = state.copyWith(isLoading: true);
    try {
      if (_remaining.isNotEmpty) {
        final take = _remaining.length.clamp(0, kDefaultPageSize);
        final next = _remaining.sublist(0, take);
        _remaining.removeRange(0, take);
        state = PaginatedListState<HomeFeedItem>(
          items: [...state.items, ...next],
          isLoading: false,
          hasReachedEnd:
              _remaining.isEmpty &&
              _callsExhausted &&
              _smsExhausted &&
              _notificationsExhausted,
        );
        return;
      }
      final callFuture = ref
          .read(callFacadeProvider.notifier)
          .loadOlder(limit: kDefaultPageSize, offset: _callOffset);
      final smsFuture = ref
          .read(smsFacadeProvider.notifier)
          .loadOlder(limit: kDefaultPageSize, offset: _smsOffset);
      final notifFuture = ref
          .read(notificationFacadeProvider.notifier)
          .loadOlder(limit: kDefaultPageSize, offset: _notifOffset);

      final calls = await callFuture;
      final sms = await smsFuture;
      final notifications = await notifFuture;

      final merged = _mergeAndSort(calls, sms, notifications);
      _callsExhausted = calls.length < kDefaultPageSize;
      _smsExhausted = sms.length < kDefaultPageSize;
      _notificationsExhausted = notifications.length < kDefaultPageSize;
      final visible = merged.length.clamp(0, kDefaultPageSize);
      _remaining.addAll(merged.skip(visible));
      state = PaginatedListState<HomeFeedItem>(
        items: [...state.items, ...merged.take(visible)],
        isLoading: false,
        hasReachedEnd:
            _remaining.isEmpty &&
            _callsExhausted &&
            _smsExhausted &&
            _notificationsExhausted,
      );
      _callOffset += calls.length;
      _smsOffset += sms.length;
      _notifOffset += notifications.length;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  List<HomeFeedItem> _mergeAndSort(
    List<CallEvent> calls,
    List<SmsMessage> sms,
    List<NotificationEvent> notifications,
  ) {
    final items = <HomeFeedItem>[
      ...calls.map(CallFeedItem.new),
      ...sms.map(SmsFeedItem.new),
      ...notifications.map(NotificationFeedItem.new),
    ];
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  /// Re-fetches the recent window from all three sources and merges any
  /// new items into the already-loaded list (deduped by id) so live
  /// updates from the socket appear without an app restart.
  Future<void> refresh() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true);
    try {
      final since = yesterdayStart();
      final callFuture = ref
          .read(callFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);
      final smsFuture = ref
          .read(smsFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);
      final notifFuture = ref
          .read(notificationFacadeProvider.notifier)
          .loadRecent(limit: kDefaultPageSize, since: since);

      final calls = await callFuture;
      final sms = await smsFuture;
      final notifications = await notifFuture;
      if (!mounted) return;

      final fresh = _mergeAndSort(calls, sms, notifications);
      final merged = dedupeById([...fresh, ...state.items], (i) => i.id)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = PaginatedListState<HomeFeedItem>(
        items: merged,
        isLoading: false,
        hasReachedEnd: state.hasReachedEnd,
        pageOffset: state.pageOffset,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  int _callOffset = 0;
  int _smsOffset = 0;
  int _notifOffset = 0;
}
