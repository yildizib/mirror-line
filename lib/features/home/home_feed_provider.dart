import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:mirrorline/features/notifications/notification_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';

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
    ...notifications.map(NotificationFeedItem.new),
  ];
  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
});
