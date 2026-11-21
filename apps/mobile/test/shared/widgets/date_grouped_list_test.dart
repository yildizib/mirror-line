import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/shared/widgets/date_header.dart';
import 'package:mirrorline/shared/widgets/date_grouped_list.dart';

void main() {
  testWidgets('inserts a header at each day boundary, ascending input', (
    tester,
  ) async {
    late List<Widget> built;
    final items = [
      DateTime(2026, 1, 1, 9),
      DateTime(2026, 1, 1, 10),
      DateTime(2026, 1, 2, 8),
      DateTime(2026, 1, 3, 23),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            built = buildDateGroupedItems<DateTime>(
              context: context,
              items: items,
              timestampOf: (d) => d,
              itemBuilder: (context, d) => Text(d.toIso8601String()),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    // 4 items + 3 day-boundary headers (one before each of day1, day2, day3).
    expect(built.whereType<DateHeader>(), hasLength(3));
    expect(built.length, 7);
    // Header, item, item (same day), header, item, header, item.
    expect(built[0], isA<DateHeader>());
    expect(built[1], isA<Text>());
    expect(built[2], isA<Text>());
    expect(built[3], isA<DateHeader>());
    expect(built[4], isA<Text>());
    expect(built[5], isA<DateHeader>());
    expect(built[6], isA<Text>());
  });

  testWidgets('inserts a header at each day boundary, descending input', (
    tester,
  ) async {
    late List<Widget> built;
    final items = [
      DateTime(2026, 1, 3, 23),
      DateTime(2026, 1, 2, 8),
      DateTime(2026, 1, 1, 10),
      DateTime(2026, 1, 1, 9),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            built = buildDateGroupedItems<DateTime>(
              context: context,
              items: items,
              timestampOf: (d) => d,
              itemBuilder: (context, d) => Text(d.toIso8601String()),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(built.whereType<DateHeader>(), hasLength(3));
    expect(built.length, 7);
    expect(built[0], isA<DateHeader>());
    expect(built[1], isA<Text>());
    expect(built[2], isA<DateHeader>());
    expect(built[3], isA<Text>());
    expect(built[4], isA<DateHeader>());
    expect(built[5], isA<Text>());
    expect(built[6], isA<Text>());
  });

  testWidgets('never inserts a header between two same-day items', (
    tester,
  ) async {
    late List<Widget> built;
    final items = [
      DateTime(2026, 1, 1, 0, 1),
      DateTime(2026, 1, 1, 12),
      DateTime(2026, 1, 1, 23, 59),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            built = buildDateGroupedItems<DateTime>(
              context: context,
              items: items,
              timestampOf: (d) => d,
              itemBuilder: (context, d) => Text(d.toIso8601String()),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(built.whereType<DateHeader>(), hasLength(1));
    expect(built.length, 4);
  });
}
