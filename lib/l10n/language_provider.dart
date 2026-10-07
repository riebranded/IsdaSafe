import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english('en', 'English'),
  tagalog('tl', 'Tagalog');

  const AppLanguage(this.code, this.label);

  /// Sent to the AI edge functions as `language` so replies match the UI.
  final String code;
  final String label;
}

/// The app's display language (English or Tagalog), persisted across
/// launches. Strings are translated with the `.tr` extension (see `tr.dart`),
/// which reads [LanguageProvider.current]; changing the language rebuilds the
/// whole widget tree in place, so navigation and form state are kept.
class LanguageProvider extends ChangeNotifier {
  LanguageProvider() {
    _load();
  }

  static const _prefsKey = 'app_language';

  /// Read by `.tr` — static so strings can be translated without a
  /// BuildContext (including inside `const` widget trees' builders).
  static AppLanguage current = AppLanguage.english;

  /// Bumped on every language change, for non-widget holders of translated
  /// content (e.g. AI answers that must be re-fetched in the new language).
  static final ValueNotifier<int> revision = ValueNotifier(0);

  AppLanguage get language => current;
  bool get isTagalog => current == AppLanguage.tagalog;

  Locale get locale => isTagalog ? const Locale('fil') : const Locale('en');

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      final restored = AppLanguage.values
          .where((l) => l.name == stored)
          .firstOrNull;
      if (restored != null && restored != current) _apply(restored);
    } catch (_) {
      // Fall back to English if storage is unavailable.
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == current) return;
    _apply(language);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, language.name);
    } catch (_) {}
  }

  void _apply(AppLanguage language) {
    current = language;
    revision.value++;
    notifyListeners();
    // `.tr` doesn't register a dependency, so mark every element dirty once
    // the new locale is in place.
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static void _rebuildAll() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}
