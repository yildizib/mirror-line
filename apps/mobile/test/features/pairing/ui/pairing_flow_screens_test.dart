import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/pairing/ui/pairing_flow_screens.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  Widget app(
    Widget child, {
    Locale locale = const Locale('en'),
    double scale = 1,
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildMirrorLineTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    );
  }

  testWidgets('P01 through P17 render every required state', (tester) async {
    void noop() {}
    final screens = <Widget>[
      // P01 capacity: 0, 1-4, 5, unavailable.
      SourceListScreen(
        current: 0,
        maximum: 5,
        phase: PairingPhase.active,
        onAdd: noop,
        onManage: noop,
      ),
      SourceListScreen(
        current: 3,
        maximum: 5,
        phase: PairingPhase.active,
        onAdd: noop,
        onManage: noop,
      ),
      SourceListScreen(
        current: 5,
        maximum: 5,
        phase: PairingPhase.active,
        onAdd: noop,
        onManage: noop,
      ),
      SourceListScreen(
        current: 1,
        maximum: 5,
        phase: PairingPhase.unavailable,
        onAdd: noop,
        onManage: noop,
      ),
      // P02 and P03.
      PairingEligibilityScreen(phase: PairingPhase.checking, onRetry: noop),
      PairingEligibilityScreen(phase: PairingPhase.failed, onRetry: noop),
      PairingLimitScreen(onManage: noop),
      // P04 and P05: active, expiring, expired, refreshing.
      PairingIntroductionScreen(onContinue: noop),
      MainPairingCodeScreen(
        payload: 'opaque-presentation-data',
        code: 'ABCDE23456',
        remaining: '01:00',
        phase: PairingPhase.active,
        onRefresh: noop,
        onCancel: noop,
      ),
      MainPairingCodeScreen(
        payload: 'opaque-presentation-data',
        code: 'ABCDE23456',
        remaining: '00:10',
        phase: PairingPhase.expiring,
        onRefresh: noop,
        onCancel: noop,
      ),
      MainPairingCodeScreen(
        payload: 'opaque-presentation-data',
        code: 'ABCDE23456',
        remaining: '00:00',
        phase: PairingPhase.expired,
        onRefresh: noop,
        onCancel: noop,
      ),
      MainPairingCodeScreen(
        payload: 'opaque-presentation-data',
        code: 'ABCDE23456',
        remaining: '01:00',
        phase: PairingPhase.refreshing,
        onRefresh: noop,
        onCancel: noop,
      ),
      // P06, P07 and P08.
      SourceScannerScreen(
        phase: PairingPhase.active,
        onScan: noop,
        onManual: noop,
        onBack: noop,
      ),
      SourceScannerScreen(
        phase: PairingPhase.denied,
        onScan: noop,
        onManual: noop,
        onBack: noop,
      ),
      SourceScannerScreen(
        phase: PairingPhase.unavailable,
        onScan: noop,
        onManual: noop,
        onBack: noop,
      ),
      ManualCodeScreen(
        phase: PairingPhase.active,
        onSubmit: (_) {},
        onBack: noop,
      ),
      ManualCodeScreen(
        phase: PairingPhase.invalid,
        onSubmit: (_) {},
        onBack: noop,
      ),
      ManualCodeScreen(
        phase: PairingPhase.expired,
        onSubmit: (_) {},
        onBack: noop,
      ),
      ManualCodeScreen(
        phase: PairingPhase.submitting,
        onSubmit: (_) {},
        onBack: noop,
      ),
      InvalidPairingCodeScreen(
        phase: PairingPhase.invalid,
        onNewCode: noop,
        onCancel: noop,
      ),
      InvalidPairingCodeScreen(
        phase: PairingPhase.expired,
        onNewCode: noop,
        onCancel: noop,
      ),
      // P09 through P17.
      VerificationComparisonScreen(
        role: PairingRole.main,
        code: '654 321',
        onMatch: noop,
        onMismatch: noop,
      ),
      VerificationComparisonScreen(
        role: PairingRole.source,
        code: '654 321',
        onMatch: noop,
        onMismatch: noop,
      ),
      ReviewSourceScreen(
        sourceName: 'Source Phone',
        deviceLabel: 'Phone',
        submitting: false,
        onConfirm: noop,
      ),
      ReviewSourceScreen(
        sourceName: 'Source Phone',
        deviceLabel: 'Phone',
        submitting: true,
        onConfirm: noop,
      ),
      PairingSuccessScreen(
        role: PairingRole.main,
        sourceName: 'Source Phone',
        onNext: noop,
      ),
      PairingSuccessScreen(
        role: PairingRole.source,
        sourceName: 'Source Phone',
        onNext: noop,
      ),
      PairingFailureScreen(
        phase: PairingPhase.genericFailure,
        onRetry: noop,
        onCancel: noop,
        onManage: noop,
      ),
      PairingFailureScreen(
        phase: PairingPhase.rejected,
        onRetry: noop,
        onCancel: noop,
        onManage: noop,
      ),
      PairingFailureScreen(
        phase: PairingPhase.timedOut,
        onRetry: noop,
        onCancel: noop,
        onManage: noop,
      ),
      PairingFailureScreen(
        phase: PairingPhase.quotaChanged,
        onRetry: noop,
        onCancel: noop,
        onManage: noop,
      ),
      AlreadyPairedScreen(phase: PairingPhase.connected, onRemove: noop),
      AlreadyPairedScreen(phase: PairingPhase.mainUnavailable, onRemove: noop),
      RemoveMainWarningScreen(onContinue: noop, onCancel: noop),
      UnpairReauthenticationScreen(
        phase: PairingPhase.active,
        onConfirm: (_) {},
      ),
      UnpairReauthenticationScreen(
        phase: PairingPhase.failed,
        onConfirm: (_) {},
      ),
      UnpairReauthenticationScreen(
        phase: PairingPhase.submitting,
        onConfirm: (_) {},
      ),
      ConnectionRemovedScreen(onStartNew: noop),
      PairingSecurityStatusScreen(
        phase: PairingPhase.waitingProof,
        onContinue: noop,
        onCancel: noop,
      ),
      PairingSecurityStatusScreen(
        phase: PairingPhase.comparisonRequired,
        onContinue: noop,
        onCancel: noop,
      ),
      PairingSecurityStatusScreen(
        phase: PairingPhase.verified,
        onContinue: noop,
        onCancel: noop,
      ),
      PairingSecurityStatusScreen(
        phase: PairingPhase.securityFailed,
        onContinue: noop,
        onCancel: noop,
      ),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(app(screen));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('actions invoke callbacks and loading states disable actions', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      app(
        SourceListScreen(
          current: 0,
          maximum: 5,
          phase: PairingPhase.active,
          onAdd: () => count++,
          onManage: () => count++,
        ),
      ),
    );
    await tester.tap(find.text('Add Source Phone'));
    expect(count, 1);

    await tester.pumpWidget(
      app(
        MainPairingCodeScreen(
          payload: 'opaque',
          code: 'ABCDE23456',
          remaining: '00:00',
          phase: PairingPhase.expired,
          onRefresh: () => count++,
          onCancel: () => count++,
        ),
      ),
    );
    expect(find.byType(QrImageView), findsNothing);
    await tester.tap(find.text('Generate new code'));
    expect(count, 2);

    await tester.pumpWidget(
      app(
        MainPairingCodeScreen(
          payload: 'opaque',
          code: 'ABCDE23456',
          remaining: '01:00',
          phase: PairingPhase.refreshing,
          onRefresh: () => count++,
          onCancel: () => count++,
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('ABCDE 23456'), findsNothing);

    await tester.pumpWidget(
      app(
        SourceScannerScreen(
          phase: PairingPhase.denied,
          onScan: () => count++,
          onManual: () => count++,
          onBack: () => count++,
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Enter code manually'));
    expect(count, 3);
    expect(find.text('Back'), findsOneWidget);

    await tester.pumpWidget(
      app(
        SourceScannerScreen(
          phase: PairingPhase.active,
          onScan: () => count++,
          onManual: () => count++,
          onBack: () => count++,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );

    await tester.pumpWidget(
      app(
        VerificationComparisonScreen(
          role: PairingRole.main,
          code: '654 321',
          onMatch: () => count++,
          onMismatch: () => count++,
        ),
      ),
    );
    await tester.tap(find.text('Codes match'));
    expect(count, 4);
    await tester.tap(find.text('Codes don’t match'));
    expect(count, 5);

    await tester.pumpWidget(
      app(
        UnpairReauthenticationScreen(
          phase: PairingPhase.submitting,
          onConfirm: (_) => count++,
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.pumpWidget(
      app(
        PairingSecurityStatusScreen(
          phase: PairingPhase.waitingProof,
          onContinue: () => count++,
          onCancel: () => count++,
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);

    await tester.pumpWidget(
      app(
        PairingSecurityStatusScreen(
          phase: PairingPhase.securityFailed,
          onContinue: () => count++,
          onRetry: () => count++,
          onCancel: () => count++,
        ),
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(count, 6);

    await tester.pumpWidget(
      app(
        PairingSecurityStatusScreen(
          phase: PairingPhase.comparisonRequired,
          onContinue: () => count++,
          onCancel: () => count++,
        ),
      ),
    );
    await tester.tap(find.text('Confirm'));
    expect(count, 7);
  });

  testWidgets(
    'manual code uses ten grouped transfer characters and rejects excluded input',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        app(
          ManualCodeScreen(
            phase: PairingPhase.active,
            onSubmit: (value) => submitted = value,
            onBack: () {},
          ),
        ),
      );
      for (var index = 0; index < 10; index++) {
        expect(
          find.byKey(ValueKey('pairing-code-segment-$index')),
          findsOneWidget,
        );
      }
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'abcde23456o789');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      expect(submitted, 'ABCDE23456');
    },
  );

  testWidgets('transfer code is presented as an accessible 5 plus 5 value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        MainPairingCodeScreen(
          payload: 'opaque',
          code: 'abcde23456',
          remaining: '01:00',
          phase: PairingPhase.active,
          onRefresh: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('ABCDE 23456'), findsOneWidget);
    expect(find.bySemanticsLabel('ABCDE 23456'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'copy, semantics, password visibility and safe presentation work in English and Turkish',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          VerificationComparisonScreen(
            role: PairingRole.source,
            code: '654 321',
            onMatch: () {},
            onMismatch: () {},
          ),
          locale: const Locale('tr'),
        ),
      );
      expect(find.text('Kodları karşılaştır'), findsOneWidget);
      expect(find.text('Kaynak Telefonundaki kod'), findsOneWidget);
      expect(find.bySemanticsLabel('654 321'), findsOneWidget);
      expect(find.text('Anahtar'), findsNothing);
      for (final term in [
        'key',
        'signature',
        'token',
        'deviceid',
        'ip',
        'port',
        'relay',
      ]) {
        final technicalText = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.toLowerCase().contains(term) ?? false),
        );
        expect(technicalText, findsNothing);
      }
      semantics.dispose();

      await tester.pumpWidget(
        app(
          SourceScannerScreen(
            phase: PairingPhase.denied,
            onScan: () {},
            onManual: () {},
            onBack: () {},
          ),
          locale: const Locale('tr'),
        ),
      );
      expect(find.text('Geri'), findsOneWidget);

      await tester.pumpWidget(
        app(
          UnpairReauthenticationScreen(
            phase: PairingPhase.active,
            onConfirm: (_) {},
          ),
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      expect(find.text('Remove current connection'), findsWidgets);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(IconButton)).height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  testWidgets(
    'long Turkish forms do not overflow at 200 percent on a small viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screens = <Widget>[
        SourceListScreen(
          current: 5,
          maximum: 5,
          phase: PairingPhase.unavailable,
          onAdd: () {},
          onManage: () {},
        ),
        PairingIntroductionScreen(onContinue: () {}),
        ManualCodeScreen(
          phase: PairingPhase.invalid,
          onSubmit: (_) {},
          onBack: () {},
        ),
        UnpairReauthenticationScreen(
          phase: PairingPhase.failed,
          onConfirm: (_) {},
        ),
        PairingSecurityStatusScreen(
          phase: PairingPhase.comparisonRequired,
          onContinue: () {},
          onCancel: () {},
        ),
      ];
      for (final screen in screens) {
        await tester.pumpWidget(
          app(screen, locale: const Locale('tr'), scale: 2),
        );
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
