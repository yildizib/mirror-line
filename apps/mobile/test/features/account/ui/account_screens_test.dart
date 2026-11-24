import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/account/ui/account_screens.dart';
import 'package:mirrorline/features/account/ui/widgets/auth_widgets.dart';
import 'package:mirrorline/l10n/app_localizations.dart';

void main() {
  Widget buildApp(
    Widget child, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildMirrorLineTheme(Brightness.light),
      darkTheme: buildMirrorLineTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );
  }

  testWidgets(
    'welcome localizes Turkish actions and exposes button semantics',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          WelcomeScreen(onSignIn: () {}, onCreateAccount: () {}),
          locale: const Locale('tr'),
        ),
      );

      expect(find.text('Telefonlarını tek yerden takip et'), findsOneWidget);
      expect(find.bySemanticsLabel('Giriş yap'), findsOneWidget);
      expect(find.bySemanticsLabel('Hesap oluştur'), findsOneWidget);
    },
  );

  testWidgets('password field has an accessible visibility control', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'secret');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: AuthTextField(
            controller: controller,
            label: 'Password field',
            password: true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('sign in preserves entries when a submission failure arrives', (
    tester,
  ) async {
    const key = ValueKey('sign-in');
    await tester.pumpWidget(
      buildApp(
        SignInScreen(
          key: key,
          viewModel: const SignInViewModel(),
          onSubmit: (_, _) {},
          onForgotPassword: () {},
          onCreateAccount: () {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secure password');
    await tester.pumpWidget(
      buildApp(
        SignInScreen(
          key: key,
          viewModel: const SignInViewModel(state: AccountRequestState.failed),
          onSubmit: (_, _) {},
          onForgotPassword: () {},
          onCreateAccount: () {},
        ),
      ),
    );

    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'person@example.com',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'secure password',
    );
  });

  testWidgets('register device remains scrollable at 200 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        RegisterDeviceScreen(
          state: AccountRequestState.failed,
          onRegister: () {},
        ),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Register this device'), findsWidgets);
  });

  testWidgets(
    'create account updates requirements and preserves fields and terms on failure',
    (tester) async {
      const key = ValueKey('create-account');
      await tester.pumpWidget(
        buildApp(
          CreateAccountScreen(
            key: key,
            viewModel: const CreateAccountViewModel(),
            onSubmit: (_, _, _, _) {},
            onSignIn: () {},
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).at(0),
        'person@example.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'Password12345');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      await tester.pumpWidget(
        buildApp(
          CreateAccountScreen(
            key: key,
            viewModel: const CreateAccountViewModel(
              state: AccountRequestState.failed,
            ),
            onSubmit: (_, _, _, _) {},
            onSignIn: () {},
          ),
        ),
      );
      expect(
        find.text('An account already exists for this email.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        'person@example.com',
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    },
  );

  testWidgets(
    'verification panel covers cooldown terminal and resend failure states',
    (tester) async {
      Future<void> pump(VerificationState state) => tester.pumpWidget(
        buildApp(
          VerifyEmailScreen(
            email: 'person@example.com',
            state: state,
            cooldownSeconds: 30,
            onCheckAgain: () {},
            onResend: () {},
            onChangeEmail: () {},
            onSignOut: () {},
          ),
        ),
      );

      await pump(VerificationState.cooldown);
      expect(find.text('You can resend in 30 seconds.'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await pump(VerificationState.sent);
      expect(find.text('Verification email sent again.'), findsOneWidget);
      await pump(VerificationState.expired);
      expect(
        find.text('This verification link has expired. Request a new one.'),
        findsOneWidget,
      );
      await pump(VerificationState.resendFailed);
      expect(
        find.text('Verification email couldn’t be resent. Try again.'),
        findsOneWidget,
      );
      await pump(VerificationState.verified);
      expect(find.text('Email verified.'), findsOneWidget);
    },
  );

  testWidgets(
    'password reset forms show offline failure expiry and success feedback',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          ForgotPasswordScreen(
            state: AccountRequestState.offline,
            onSubmit: (_) {},
          ),
        ),
      );
      expect(
        find.text(
          'Couldn’t connect. Your entries were kept; you can try again.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        buildApp(
          ForgotPasswordScreen(
            state: AccountRequestState.failed,
            onSubmit: (_) {},
          ),
        ),
      );
      expect(
        find.text(
          'Couldn’t connect. Your entries were kept; you can try again.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(buildApp(ResetEmailSentScreen(onDone: () {})));
      expect(
        find.text('If an account matches, we sent a password reset link.'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        buildApp(
          NewPasswordScreen(
            expired: true,
            state: AccountRequestState.success,
            onSubmit: (_, _) {},
          ),
        ),
      );
      expect(
        find.text('This verification link has expired. Request a new one.'),
        findsOneWidget,
      );
      expect(
        find.text('Your password was updated. You can now sign in.'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        buildApp(
          NewPasswordScreen(
            state: AccountRequestState.offline,
            onSubmit: (_, _) {},
          ),
        ),
      );
      expect(
        find.text(
          'Couldn’t connect. Your entries were kept; you can try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('role selection uses approved Turkish copy and callbacks', (
    tester,
  ) async {
    PhoneRole? selected;
    await tester.pumpWidget(
      buildApp(
        ChooseRoleScreen(onSelect: (role) => selected = role),
        locale: const Locale('tr'),
      ),
    );
    expect(find.text('Bu telefonu nasıl kullanacaksın?'), findsOneWidget);
    expect(
      find.text(
        'Kaynak Telefonlarından gelen çağrı, SMS ve bildirimleri burada gör.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Kaynak Telefon'));
    expect(selected, PhoneRole.source);
    await tester.pumpWidget(buildApp(ChooseRoleScreen(onSelect: (_) {})));
    expect(find.text('How will you use this phone?'), findsOneWidget);
    expect(
      find.text(
        'View calls, SMS, and notifications from your Source Phones here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('confirm role exposes the supplied Main role callback', (
    tester,
  ) async {
    var confirmed = false;
    await tester.pumpWidget(
      buildApp(
        ConfirmRoleScreen(
          role: PhoneRole.main,
          onConfirm: () => confirmed = true,
          onBack: () {},
        ),
      ),
    );
    expect(
      find.text('This phone will show activity from your Sources.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    expect(confirmed, isTrue);
  });

  testWidgets('register device exposes registering and failure states', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        RegisterDeviceScreen(
          state: AccountRequestState.submitting,
          onRegister: () {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(
      buildApp(
        RegisterDeviceScreen(
          state: AccountRequestState.failed,
          onRegister: () {},
        ),
      ),
    );
    expect(
      find.text('This device could not be registered. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'long Turkish create account form has no overflow at 200 percent text scale',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          CreateAccountScreen(
            viewModel: const CreateAccountViewModel(),
            onSubmit: (_, _, _, _) {},
            onSignIn: () {},
          ),
          locale: const Locale('tr'),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    },
  );
}
