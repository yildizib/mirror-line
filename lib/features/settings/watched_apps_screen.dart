import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/services/watched_apps_service.dart';
import 'package:mirrorline/core/telephony/installed_apps_channel.dart';

class WatchedAppsScreen extends ConsumerStatefulWidget {
  const WatchedAppsScreen({super.key});

  @override
  ConsumerState<WatchedAppsScreen> createState() => _WatchedAppsScreenState();
}

class _WatchedAppsScreenState extends ConsumerState<WatchedAppsScreen> {
  List<InstalledApp> _apps = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final apps = await InstalledAppsChannel.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final watched = ref.watch(watchedAppsProvider);
    final filtered = _query.isEmpty
        ? _apps
        : _apps
              .where(
                (app) =>
                    app.appName.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.watchedAppsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l.watchedAppsSearchHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: _loading || !watched.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      return SwitchListTile(
                        secondary: _AppIcon(packageName: app.packageName),
                        title: Text(app.appName),
                        value: watched.packages.contains(app.packageName),
                        onChanged: (value) => ref
                            .read(watchedAppsProvider.notifier)
                            .setWatched(app.packageName, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String packageName;

  const _AppIcon({required this.packageName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: InstalledAppsChannel.getAppIcon(packageName),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const CircleAvatar(child: Icon(Icons.apps_rounded));
        }
        return CircleAvatar(backgroundImage: MemoryImage(bytes));
      },
    );
  }
}
