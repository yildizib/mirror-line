import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/telephony/installed_apps_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kWatchedPackagesKey = 'watched_packages';
const _kMigratedKey = 'watched_packages_migrated';

/// Which installed apps' notifications get mirrored to the paired device.
/// Persists in SharedPreferences, same pattern as [LocaleNotifier]
/// (locale_service.dart).
final watchedAppsProvider =
    StateNotifierProvider<WatchedAppsNotifier, WatchedAppsState>((ref) {
      return WatchedAppsNotifier();
    });

class WatchedAppsState {
  const WatchedAppsState({
    this.packages = const {},
    this.isInitialized = false,
  });

  final Set<String> packages;
  final bool isInitialized;
}

class WatchedAppsNotifier extends StateNotifier<WatchedAppsState> {
  final Future<SharedPreferences> Function() _getPreferences;
  final Future<List<InstalledApp>> Function() _getInstalledApps;
  late final Future<void> _initialized;
  Future<void>? _mutationQueue;

  WatchedAppsNotifier({
    Future<SharedPreferences> Function()? getPreferences,
    Future<List<InstalledApp>> Function()? getInstalledApps,
  }) : _getPreferences = getPreferences ?? SharedPreferences.getInstance,
       _getInstalledApps =
           getInstalledApps ?? InstalledAppsChannel.getInstalledApps,
       super(const WatchedAppsState()) {
    _initialized = _load();
  }

  Future<void> get initialized => _initialized;

  Future<void> _load() async {
    final prefs = await _getPreferences();
    final migrated = prefs.getBool(_kMigratedKey) ?? false;
    if (!migrated) {
      // First-run migration: seed the watched set with every currently
      // installed app, fetched once via the native app-list method, so
      // mirroring behavior is unchanged until the user manually
      // un-watches something -- avoids a silent regression from today's
      // "mirror everything" behavior (nothing filters notifications yet).
      final installed = await _getInstalledApps();
      final seeded = installed.map((app) => app.packageName).toSet();
      await prefs.setStringList(_kWatchedPackagesKey, seeded.toList());
      await prefs.setBool(_kMigratedKey, true);
      state = WatchedAppsState(packages: seeded, isInitialized: true);
      return;
    }
    final saved = prefs.getStringList(_kWatchedPackagesKey) ?? const [];
    state = WatchedAppsState(packages: saved.toSet(), isInitialized: true);
  }

  bool isWatched(String packageName) => state.packages.contains(packageName);

  Future<void> setWatched(String packageName, bool watched) {
    final previous = _mutationQueue;
    final queueCompleter = Completer<void>();
    _mutationQueue = queueCompleter.future;

    Future<void> run() async {
      if (previous != null) await previous;
      await initialized;
      final updated = Set<String>.from(state.packages);
      if (watched) {
        updated.add(packageName);
      } else {
        updated.remove(packageName);
      }
      final prefs = await _getPreferences();
      await prefs.setStringList(_kWatchedPackagesKey, updated.toList());
      state = WatchedAppsState(packages: updated, isInitialized: true);
    }

    return run().whenComplete(queueCompleter.complete);
  }
}
