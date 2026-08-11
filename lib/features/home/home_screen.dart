import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/core/services/permission_service.dart';
import 'package:mirrorline/core/theme/theme.dart';
import 'package:mirrorline/features/calls/calls_screen.dart';
import 'package:mirrorline/features/connection/connection_provider.dart';
import 'package:mirrorline/features/connection/widgets/connection_banner.dart';
import 'package:mirrorline/features/settings/settings_screen.dart';
import 'package:mirrorline/features/sms/sms_screen.dart';
import 'package:mirrorline/features/sms/sms_thread_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  final _pages = const [CallsScreen(), SmsScreen(), SettingsScreen()];

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
      _consumePendingNavRequest();
    });
    // A notification tap may arrive at any time, not just during the first
    // frame -- listen for the lifetime of this screen.
    NotificationRouter.instance.requests.addListener(_handleNavRequest);
  }

  @override
  void dispose() {
    NotificationRouter.instance.requests.removeListener(_handleNavRequest);
    super.dispose();
  }

  void _handleNavRequest() {
    final req = NotificationRouter.instance.requests.value;
    if (req == null) return;
    NotificationRouter.instance.consume();

    final payload = req.payload;
    switch (payload.type) {
      case 'call':
        setState(() => _selectedIndex = 0);
        break;
      case 'sms':
        setState(() => _selectedIndex = 1);
        if (payload.address != null && payload.address!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SmsThreadScreen(address: payload.address!),
              ),
            );
          });
        }
        break;
      case 'mirrored':
        // Mirrored notifications don't deep-link anywhere -- the app just
        // comes to the foreground; leave the current tab as-is.
        break;
    }
  }

  void _consumePendingNavRequest() {
    // A tap that happened before this screen existed is still sitting in
    // the router; process it now that we have a context to navigate with.
    if (NotificationRouter.instance.requests.value != null) {
      _handleNavRequest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionProvider);
    final theme = Theme.of(context);
    final status = theme.status;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.appTitle),
            const SizedBox(width: AppSpacing.sm),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected
                    ? status.success
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          ConnectionBanner(isConnected: isConnected),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.call_outlined),
            selectedIcon: const Icon(Icons.call_rounded),
            label: l.navCalls,
          ),
          NavigationDestination(
            icon: const Icon(Icons.message_outlined),
            selectedIcon: const Icon(Icons.message_rounded),
            label: l.navSms,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: l.navSettings,
          ),
        ],
      ),
    );
  }
}
