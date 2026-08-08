import 'package:flutter/material.dart';

import 'ui/screens/splash_screen.dart';
import 'ui/theme.dart';

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
