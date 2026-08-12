import 'package:flutter/material.dart';
import 'package:mirrorline/shared/widgets/date_header.dart';

/// Walks the already-sorted [items] and inserts a [DateHeader] before any
/// item whose calendar day differs from the previous item's -- returns a
/// flat widget list ready for `ListView(children: ...)`.
///
/// For screens using [SelectableListScaffold], pass `dateHeaderOf`/
/// `timestampOf` directly to that widget instead (it needs to interleave
/// headers *inside* its own selection-aware list building, which this
/// free function can't do) -- this helper is for plain, non-selectable
/// lists like SmsThreadScreen's message list.
List<Widget> buildDateGroupedItems<T>({
  required BuildContext context,
  required List<T> items,
  required DateTime Function(T item) timestampOf,
  required Widget Function(BuildContext context, T item) itemBuilder,
}) {
  final widgets = <Widget>[];
  DateTime? previousDay;

  for (final item in items) {
    final timestamp = timestampOf(item);
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (previousDay == null || day != previousDay) {
      widgets.add(DateHeader(date: day));
      previousDay = day;
    }
    widgets.add(itemBuilder(context, item));
  }

  return widgets;
}
