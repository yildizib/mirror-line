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
}

class CallFeedItem extends HomeFeedItem {
  final CallEvent event;

  CallFeedItem(this.event);

  @override
  DateTime get timestamp => event.timestamp;
}

class SmsFeedItem extends HomeFeedItem {
  final SmsMessage message;

  SmsFeedItem(this.message);

  @override
  DateTime get timestamp => message.timestamp;
}

class NotificationFeedItem extends HomeFeedItem {
  final NotificationEvent event;

  NotificationFeedItem(this.event);

  @override
  DateTime get timestamp => event.timestamp;
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
 ...notifications.map(NotificationFeedItem.new)];
 items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
 return items;
});

/// Paginated home feed: fetches 25 from each source in parallel,
/// merges by timestamp DESC, truncates to 25. loadMore advances
/// all 3 offsets and re-merges.
final homeFeedPaginatedProvider =
    StateNotifierProvider<HomeFeedPaginated, PaginatedListState<HomeFeedItem>>(
        (ref) {
  final notifier = HomeFeedPaginated(ref);
  Future.microtask(() => notifier.loadInitial());
  return notifier;
});

class HomeFeedPaginated
    extends StateNotifier<PaginatedListState<HomeFeedItem>> {
  HomeFeedPaginated(this.ref) : super(PaginatedListState<HomeFeedItem>());

  final Ref ref;

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
      final visible = merged.length > kDefaultPageSize
          ? kDefaultPageSize
          : merged.length;
      final hasMore = calls.length >= kDefaultPageSize ||
          sms.length >= kDefaultPageSize ||
          notifications.length >= kDefaultPageSize;
      state = PaginatedListState<HomeFeedItem>(
        items: merged.sublist(0, visible),
        isLoading: false,
        hasReachedEnd: !hasMore && visible == merged.length,
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
      final combined = [...state.items, ...merged]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final visible = combined.length > kDefaultPageSize * 2
          ? kDefaultPageSize * 2
          : combined.length;
      final hasReachedEnd = calls.length < kDefaultPageSize &&
          sms.length < kDefaultPageSize &&
          notifications.length < kDefaultPageSize;
      state = PaginatedListState<HomeFeedItem>(
        items: combined.sublist(0, visible),
        isLoading: false,
        hasReachedEnd: hasReachedEnd,
        pageOffset: 0,
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

  int _callOffset = 0;
  int _smsOffset = 0;
  int _notifOffset = 0;
}
