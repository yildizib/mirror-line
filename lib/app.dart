import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';

class MirrorLineApp extends StatelessWidget {
  const MirrorLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MirrorLine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const HomeScreen(),
    );
  }
}
