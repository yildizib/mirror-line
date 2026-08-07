import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connection_provider.dart';
import '../widgets/connection_banner.dart';
import 'calls_screen.dart';
import 'settings_screen.dart';
import 'sms_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  final _pages = const [
    CallsScreen(),
    SmsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MirrorLine'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          ConnectionBanner(isConnected: isConnected),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Aramalar',
          ),
          NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message),
            label: 'SMS',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}
