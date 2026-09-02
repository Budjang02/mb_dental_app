import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme preference, persisted locally. Singleton so [AppColors]
/// getters (theme.dart) and the MaterialApp can both react to it without
/// threading a BuildContext everywhere.
///
/// Three modes: [ThemeMode.system] (the default — follows the OS light/dark
/// setting live), [ThemeMode.light] and [ThemeMode.dark].
class ThemeController extends ChangeNotifier {
  static final ThemeController _instance = ThemeController._internal();
  factory ThemeController() => _instance;

  ThemeController._internal() {
    _platformBrightness = PlatformDispatcher.instance.platformBrightness;
    // The OS theme can flip while the app is running (or on a schedule), so
    // mirror it into our own notifier instead of reading it once at startup.
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      final brightness = PlatformDispatcher.instance.platformBrightness;
      if (brightness == _platformBrightness) return;
      _platformBrightness = brightness;
      if (_mode == ThemeMode.system) notifyListeners();
    };
  }

  static const _prefsKey = 'theme_mode';
  static const _legacyPrefsKey = 'is_dark_mode';

  ThemeMode _mode = ThemeMode.system;
  late Brightness _platformBrightness;

  ThemeMode get mode => _mode;

  /// Whether the app is currently rendering dark — resolves [ThemeMode.system]
  /// against the live OS brightness.
  bool get isDark => _mode == ThemeMode.system
      ? _platformBrightness == Brightness.dark
      : _mode == ThemeMode.dark;

  /// Label for the current mode, e.g. shown next to the Theme row in Profile.
  String get modeLabel {
    switch (_mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    ThemeMode? loaded = _parse(stored);

    // Migrate the old boolean preference so existing installs keep the theme
    // they were already on instead of silently jumping to System.
    if (loaded == null && prefs.containsKey(_legacyPrefsKey)) {
      loaded = prefs.getBool(_legacyPrefsKey) == true ? ThemeMode.dark : ThemeMode.light;
      await prefs.setString(_prefsKey, _serialize(loaded));
      await prefs.remove(_legacyPrefsKey);
    }

    if (loaded != null && loaded != _mode) {
      _mode = loaded;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _serialize(value));
  }

  /// Kept for call sites that just want a light/dark switch.
  Future<void> setDark(bool value) => setMode(value ? ThemeMode.dark : ThemeMode.light);

  Future<void> toggle() => setDark(!isDark);

  static String _serialize(ThemeMode mode) => mode.name;

  static ThemeMode? _parse(String? raw) {
    switch (raw) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}
