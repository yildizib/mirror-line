import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'app_locale';

/// Holds the app's current locale and lets the user override the system
/// language from Settings. Persists the choice in SharedPreferences.
///
/// On first launch (no saved preference) the platform's locale is used.
/// When the user picks a language explicitly we store its BCP-47 tag;
/// passing `null` clears the override and falls back to the system locale.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null) {
    _load();
  }

  /// All locales the app ships translations for. Keep in sync with the
  /// ARB files under lib/l10n.
  static const supportedLocales = [
    Locale('tr'),
    Locale('en'),
  ];

  /// Default fallback when neither the saved preference nor the platform
  /// locale is in [supportedLocales].
  static const fallback = Locale('tr');

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_kLocaleKey);
    if (tag != null) {
      state = _parseTag(tag);
    }
  }

  /// Persist a manual language choice. Pass `null` to clear it and go
  /// back to following the system locale.
  Future<void> set(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_kLocaleKey);
    } else {
      await prefs.setString(_kLocaleKey, locale.toLanguageTag());
    }
  }

  /// Resolve the locale actually used for localization delegates: the
  /// user's explicit choice if set, else the platform locale if it's one
  /// we support, else the fallback.
  Locale resolve(Iterable<Locale> systemLocales) {
    final explicit = state;
    if (explicit != null) return explicit;
    return resolveSystem(systemLocales);
  }

  /// Same matching rule as [resolve], minus the explicit-override check --
  /// shared with [appL10n], which needs it outside the widget tree.
  static Locale resolveSystem(Iterable<Locale> systemLocales) {
    for (final sys in systemLocales) {
      for (final supported in supportedLocales) {
        if (sys.languageCode == supported.languageCode) return supported;
      }
    }
    return fallback;
  }

  Locale _parseTag(String tag) {
    final parts = tag.split('-');
    return Locale(parts[0], parts.length > 1 ? parts[1] : null);
  }
}

/// Resolves [AppLocalizations] outside the widget tree -- background
/// handlers (CallEventHandler/SmsEventHandler building notification text)
/// and providers (call/SMS grouping) that have a [Ref] but no
/// [BuildContext]. Follows the same locale-resolution rule as the widget
/// tree's [LocalizationsDelegate] (see [LocaleNotifier.resolve]).
AppLocalizations appL10n(Ref ref) {
  final explicit = ref.read(localeProvider);
  final locale = explicit ?? LocaleNotifier.resolveSystem(PlatformDispatcher.instance.locales);
  return lookupAppLocalizations(locale);
}