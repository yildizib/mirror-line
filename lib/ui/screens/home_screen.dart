import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../../providers/connection_provider.dart';
import '../../services/permission_service.dart';
import '../theme.dart';
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
  void initState() {
    super.initState();
    // Requested here (after the home page's first frame), not at app
    // launch, so the splash screen and home UI are visible before any
    // system permission dialog appears.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PermissionService.requestNotifications();
      } catch (e) {
        Logger().e('Notification permission request failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionProvider);
    final theme = Theme.of(context);
    final status = theme.status;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('MirrorLine'),
            const SizedBox(width: AppSpacing.sm),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? status.success : theme.colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          ConnectionBanner(isConnected: isConnected),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_selectedIndex),
                child: _pages[_selectedIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: 'Aramalar',
          ),
          NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message_rounded),
            label: 'SMS',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}
