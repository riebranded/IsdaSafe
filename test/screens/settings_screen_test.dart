import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/settings_screen.dart';
import 'package:isdasafev2/theme/app_theme.dart';

void main() {
  // SettingsScreen reads AuthService (→ Supabase.instance) at build. Init
  // Supabase once with throwaway creds (no session → null user, no network);
  // the mocked shared_preferences store backs both Supabase's local storage
  // and ThemeProvider's persistence.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://localhost', publishableKey: 'test-key');
  });

  testWidgets('choosing an Appearance option updates the app-wide ThemeProvider', (tester) async {
    final themeProvider = ThemeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The three appearance options are shown, defaulting to System.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(themeProvider.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(themeProvider.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(themeProvider.themeMode, ThemeMode.light);
  });
}
