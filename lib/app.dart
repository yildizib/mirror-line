import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/services/locale_service.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/home/splash_screen.dart';

class MirrorLineApp extends ConsumerWidget {
  const MirrorLineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedLocale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'MirrorLine',
      debugShowCheckedModeBanner: false,
      theme: buildMirrorLineTheme(Brightness.light),
      darkTheme: buildMirrorLineTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: savedLocale,
      supportedLocales: LocaleNotifier.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}
