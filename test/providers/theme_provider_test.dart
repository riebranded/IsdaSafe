import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to system when nothing is stored', () {
    expect(ThemeProvider().themeMode, ThemeMode.system);
  });

  test('setThemeMode updates the value and persists it', () async {
    final provider = ThemeProvider();

    await provider.setThemeMode(ThemeMode.light);

    expect(provider.themeMode, ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('restores a persisted choice on construction', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

    final provider = ThemeProvider();
    // _load() runs asynchronously in the constructor.
    await Future<void>.delayed(Duration.zero);

    expect(provider.themeMode, ThemeMode.dark);
  });

  testWidgets('the app renders with the theme matching the selected mode', (tester) async {
    final provider = ThemeProvider();
    late BuildContext captured;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: Consumer<ThemeProvider>(
          builder: (context, tp, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: tp.themeMode,
            home: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    await provider.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(captured).brightness, Brightness.dark);

    // Switching back to light mode makes the app switch to the light theme.
    await provider.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(Theme.of(captured).brightness, Brightness.light);
  });
}
