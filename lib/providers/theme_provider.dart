import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app's light/dark/system theme selection and persists it across
/// launches. [IsdaSafeApp] watches this to drive `MaterialApp.themeMode`,
/// and the Settings screen writes to it via [setThemeMode].
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _load();
  }

  static const _prefsKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Restores the saved choice on startup (defaults to [ThemeMode.system]
  /// when nothing is stored or the value is unrecognized).
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return;

    final restored = ThemeMode.values.where((m) => m.name == stored).firstOrNull;
    if (restored != null && restored != _themeMode) {
      _themeMode = restored;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
