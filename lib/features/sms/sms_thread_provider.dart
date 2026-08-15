import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';
import 'package:mirrorline/shared/pagination/grouped_paginated_notifier.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

/// Every message exchanged with a single address, grouped so the SMS
/// screen can read as a normal conversation list instead of one flat,
/// unordered timeline of every incoming and outgoing message.
class SmsThread {
  final String address;
  final String contactName;
  final List<SmsMessage> messages; // chronological, oldest first

  /// Display name (contact name if resolved, else address, else
  /// placeholder), already localized at thread-build time.
  final String displayName;

  SmsThread({
    required this.address,
    required this.contactName,
    required this.messages,
    required this.displayName,
  });

  SmsMessage get lastMessage => messages.last;
}

/// Derives conversations from smsFacadeProvider's flat list, grouped by
/// address -- native never supplies a real Android thread id (see
/// MirrorLineService, which always sends threadId ""), so address is the
/// only key that reliably ties a reply to the message it answers. Sorted
/// most-recently-active conversation first.
final smsThreadsProvider = Provider<List<SmsThread>>((ref) {
  final messages = ref.watch(smsFacadeProvider);
  final l = appL10n(ref);
  final byAddress = <String, List<SmsMessage>>{};
  for (final m in messages) {
    (byAddress[m.address] ??= []).add(m);
  }

  final threads = byAddress.entries.map((entry) {
    final sorted = entry.value.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final contactName = sorted.reversed
        .map((m) => m.contactName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => '');
    return SmsThread(
      address: entry.key,
      contactName: contactName,
      messages: sorted,
      displayName: contactName.isNotEmpty
          ? contactName
          : (entry.key.isNotEmpty ? entry.key : l.smsUnknownSender),
    );
  }).toList();

  threads.sort(
    (a, b) => b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp),
  );
  return threads;
});

/// Paginated SMS thread list (today+yesterday default, 25 threads per page).
final smsThreadsPaginatedProvider =
    StateNotifierProvider<SmsThreadPaginated, PaginatedListState<SmsThread>>((
      ref,
    ) {
      final notifier = SmsThreadPaginated(ref);
      Future.microtask(() => notifier.loadInitial());
      return notifier;
    });

class SmsThreadPaginated
    extends GroupedPaginatedNotifier<SmsMessage, SmsThread> {
  SmsThreadPaginated(super.ref);

  @override
  Future<List<SmsMessage>> fetchRecent({required int limit}) {
    final facade = ref.read(smsFacadeProvider.notifier);
    return facade.loadRecent(limit: limit, since: yesterdayStart());
  }

  @override
  Future<List<SmsMessage>> fetchOlder({
    required int limit,
    required int offset,
  }) {
    final facade = ref.read(smsFacadeProvider.notifier);
    return facade.loadOlder(
      limit: limit,
      offset: offset,
      before: yesterdayStart(),
    );
  }

  @override
  String groupKeyOf(SmsMessage msg) => msg.address;

  @override
  SmsThread buildGroup(String key, List<SmsMessage> events) {
    final l = appL10n(ref);
    final sorted = events.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final contactName = sorted.reversed
        .map((m) => m.contactName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => '');
    return SmsThread(
      address: key,
      contactName: contactName,
      messages: sorted,
      displayName: contactName.isNotEmpty
          ? contactName
          : (key.isNotEmpty ? key : l.smsUnknownSender),
    );
  }

  @override
  DateTime groupTimestamp(SmsThread group) => group.lastMessage.timestamp;

  @override
  List<SmsThread> mergeGroups(
    List<SmsThread> existing,
    List<SmsThread> newGroups,
  ) {
    final map = <String, SmsThread>{};
    for (final g in existing) {
      map[g.address] = g;
    }
    for (final g in newGroups) {
      final prev = map[g.address];
      if (prev != null) {
        final merged = [...prev.messages, ...g.messages]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        map[g.address] = SmsThread(
          address: g.address,
          contactName: g.contactName,
          messages: merged,
          displayName: g.displayName,
        );
      } else {
        map[g.address] = g;
      }
    }
    final result = map.values.toList()
      ..sort(
        (a, b) => b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp),
      );
    return result;
  }
}

/// Paginated SMS thread detail (single conversation).
/// Loads newest 25 messages first (sorted ASC), then older messages
/// on [SmsThreadDetailPaginated.loadOlder] via upward scroll.
final smsThreadDetailPaginatedProvider =
    StateNotifierProvider.family<
      SmsThreadDetailPaginated,
      PaginatedListState<SmsMessage>,
      String
    >((ref, address) {
      final notifier = SmsThreadDetailPaginated(ref, address);
      Future.microtask(() => notifier.loadInitial());
      return notifier;
    });

class SmsThreadDetailPaginated
    extends StateNotifier<PaginatedListState<SmsMessage>> {
  SmsThreadDetailPaginated(this.ref, this.address)
    : super(PaginatedListState<SmsMessage>());

  final Ref ref;
  final String address;

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final facade = ref.read(smsFacadeProvider.notifier);
      final all = await facade.loadRecentByThread(
        threadId: address,
        limit: kDefaultPageSize,
      );
      state = PaginatedListState<SmsMessage>(
        items: all,
        isLoading: false,
        hasReachedEnd: all.length < kDefaultPageSize,
        pageOffset: all.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> loadOlder() async {
    if (state.isLoading || state.hasReachedEnd) return;
    state = state.copyWith(isLoading: true);
    try {
      final facade = ref.read(smsFacadeProvider.notifier);
      final older = await facade.loadOlderByThread(
        threadId: address,
        limit: kDefaultPageSize,
        offset: state.pageOffset,
      );
      final merged = [...older, ...state.items];
      state = PaginatedListState<SmsMessage>(
        items: merged,
        isLoading: false,
        hasReachedEnd: older.length < kDefaultPageSize,
        pageOffset: state.pageOffset + older.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }
}
