import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/core/telephony/installed_apps_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kWatchedPackagesKey = 'watched_packages';
const _kMigratedKey = 'watched_packages_migrated';

/// Which installed apps' notifications get mirrored to the paired device.
/// Persists in SharedPreferences, same pattern as [LocaleNotifier]
/// (locale_service.dart).
final watchedAppsProvider =
    StateNotifierProvider<WatchedAppsNotifier, Set<String>>((ref) {
      return WatchedAppsNotifier();
    });

class WatchedAppsNotifier extends StateNotifier<Set<String>> {
  late final Future<void> _initialized;

  WatchedAppsNotifier() : super(const {}) {
    _initialized = _load();
  }

  Future<void> get initialized => _initialized;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(_kMigratedKey) ?? false;
    if (!migrated) {
      // First-run migration: seed the watched set with every currently
      // installed app, fetched once via the native app-list method, so
      // mirroring behavior is unchanged until the user manually
      // un-watches something -- avoids a silent regression from today's
      // "mirror everything" behavior (nothing filters notifications yet).
      final installed = await InstalledAppsChannel.getInstalledApps();
      final seeded = installed.map((app) => app.packageName).toSet();
      state = seeded;
      await prefs.setStringList(_kWatchedPackagesKey, seeded.toList());
      await prefs.setBool(_kMigratedKey, true);
      return;
    }
    final saved = prefs.getStringList(_kWatchedPackagesKey) ?? const [];
    state = saved.toSet();
  }

  bool isWatched(String packageName) => state.contains(packageName);

  Future<void> setWatched(String packageName, bool watched) async {
    final updated = Set<String>.from(state);
    if (watched) {
      updated.add(packageName);
    } else {
      updated.remove(packageName);
    }
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kWatchedPackagesKey, updated.toList());
  }
}
