import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isdasafev2/l10n/language_provider.dart';
import 'package:isdasafev2/l10n/tagalog_strings.dart';
import 'package:isdasafev2/l10n/tr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LanguageProvider.current = AppLanguage.english;
  });
  tearDown(() => LanguageProvider.current = AppLanguage.english);

  test('English leaves strings untouched', () {
    expect('Sign out'.tr, 'Sign out');
  });

  test(
    'Tagalog translates known strings and falls back to English otherwise',
    () {
      LanguageProvider.current = AppLanguage.tagalog;
      expect('Sign out'.tr, 'Mag-sign out');
      expect('Not in the dictionary'.tr, 'Not in the dictionary');
    },
  );

  test('placeholders are filled after translating', () {
    LanguageProvider.current = AppLanguage.tagalog;
    expect('Retry in {0}'.trf(['0:30']), 'Subukan muli sa 0:30');
    LanguageProvider.current = AppLanguage.english;
    expect('Retry in {0}'.trf(['0:30']), 'Retry in 0:30');
  });

  test('every translation keeps the placeholders of its English text', () {
    final placeholder = RegExp(r'\{\d+\}');
    tagalogStrings.forEach((english, tagalog) {
      expect(
        placeholder.allMatches(tagalog).map((m) => m.group(0)).toSet(),
        placeholder.allMatches(english).map((m) => m.group(0)).toSet(),
        reason: english,
      );
    });
  });

  test('the language is remembered and exposed for the AI calls', () async {
    final provider = LanguageProvider();
    await provider.setLanguage(AppLanguage.tagalog);
    expect(LanguageProvider.current.code, 'tl');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language'), 'tagalog');
  });
}
