import 'package:flutter/material.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/home/splash_screen.dart';

class MirrorLineApp extends StatelessWidget {
  const MirrorLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MirrorLine',
      debugShowCheckedModeBanner: false,
      theme: buildMirrorLineTheme(Brightness.light),
      darkTheme: buildMirrorLineTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
