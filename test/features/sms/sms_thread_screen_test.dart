import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/sms/sms_screen.dart';
import 'package:mirrorline/features/sms/sms_thread_provider.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:mirrorline/shared/pagination/paginated_list_state.dart';

class _FakeSmsThreadPaginated extends SmsThreadPaginated {
  _FakeSmsThreadPaginated(super.ref, List<SmsThread> threads) {
    state = PaginatedListState<SmsThread>(
      items: threads,
      hasLoadedInitial: true,
      hasReachedEnd: true,
    );
  }

  @override
  Future<void> loadInitial() async {}
}

class _FakeSmsThreadDetailPaginated extends SmsThreadDetailPaginated {
  _FakeSmsThreadDetailPaginated(super.ref, super.address);

  void complete(List<SmsMessage> messages) {
    state = PaginatedListState<SmsMessage>(
      items: messages,
      hasLoadedInitial: true,
      hasReachedEnd: true,
      pageOffset: messages.length,
    );
  }

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> refresh() async {}
}

class _TrackingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  final now = DateTime(2026, 8, 26, 12);
  final message = SmsMessage(
    id: 'message-1',
    threadId: 'thread-alice',
    address: '+111',
    contactName: 'Alice',
    body: 'Hello from Alice',
    encrypted: '',
    direction: 'incoming',
    status: 'received',
    timestamp: now,
    createdAt: now,
  );
  final thread = SmsThread(
    address: '+111',
    contactName: 'Alice',
    messages: [message],
    displayName: 'Alice',
  );

  List<Override> overrides() => [
    smsThreadsPaginatedProvider.overrideWith(
      (ref) => _FakeSmsThreadPaginated(ref, [thread]),
    ),
    smsThreadDetailPaginatedProvider.overrideWith((ref, address) {
      final notifier = _FakeSmsThreadDetailPaginated(ref, address);
      Future.microtask(
        () => notifier.complete(address == '+111' ? [message] : []),
      );
      return notifier;
    }),
    smsConnectionStatusProvider.overrideWithValue(false),
  ];

  Widget buildApp(Widget home, {List<NavigatorObserver> observers = const []}) {
    return ProviderScope(
      overrides: overrides(),
      child: MaterialApp(
        theme: buildMirrorLineTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: observers,
        home: home,
      ),
    );
  }

  testWidgets('one tap keeps a populated SMS thread open', (tester) async {
    final observer = _TrackingNavigatorObserver();
    await tester.pumpWidget(buildApp(const SmsScreen(), observers: [observer]));

    expect(find.text('Alice'), findsOneWidget);
    observer.popCount = 0;
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SmsThreadScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SmsThreadScreen),
        matching: find.text('Hello from Alice'),
      ),
      findsOneWidget,
    );
    expect(observer.popCount, 0);
  });

  testWidgets('confirmed empty SMS thread returns to its caller', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SmsThreadScreen(address: '+empty'),
                ),
              ),
              child: const Text('Open empty thread'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open empty thread'));
    await tester.pumpAndSettle();

    expect(find.byType(SmsThreadScreen), findsNothing);
    expect(find.text('Open empty thread'), findsOneWidget);
  });
}
