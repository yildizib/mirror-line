import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MirrorLineApp()));
    // Splash screen shown first -- verifies the app boots without crashing.
    // Deliberately not pumping further: HomeScreen underneath watches
    // ConnectionFacade, which spins up real timers/sockets that don't
    // belong in a lightweight smoke test.
    expect(find.text('MirrorLine'), findsOneWidget);
  });
}
