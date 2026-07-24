import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/app_shell.dart';
import 'package:isdasafev2/theme/app_theme.dart';

void main() {
  // AppShell mounts all 5 destinations via IndexedStack, and SettingsScreen
  // touches AuthService (→ Supabase.instance) at build. Initialize Supabase
  // once with throwaway credentials so those calls no-op (no session → null
  // user, no network) instead of asserting `_isInitialized`. We render
  // AppShell directly rather than the full app so these tests exercise the
  // side panel without going through the auth gate / a live session.
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // Supabase's default local storage reads the shared_preferences plugin
    // during initialize; stub its channel (there's no native side in a unit
    // test) so init completes with an empty store instead of throwing
    // MissingPluginException.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : null,
    );
    await Supabase.initialize(url: 'http://localhost', publishableKey: 'test-key');
  });

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PondProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AppShell(),
      ),
    );
  }

  /// Above the shell's wide-layout breakpoint (1024px), the shell shows the
  /// persistent side panel beside the content instead of a bottom
  /// [NavigationBar] under it.
  Future<void> setWideSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'wide layout shows the side panel nav; pond sub-buttons appear under Dashboard (active by default)',
    (tester) async {
      await setWideSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      // Wide/web layout has no top AppBar — the full-height side panel is the
      // header, so nothing sits above its "IsdaSafe" branding.
      expect(find.byType(AppBar), findsNothing);

      // All 5 destination buttons are present in the side panel.
      for (final name in ['dashboard', 'map', 'analytics', 'notifications', 'settings']) {
        expect(find.byKey(ValueKey('nav-$name')), findsOneWidget);
      }

      // Dashboard is active by default → its pond sub-buttons show, its FAB
      // shows, and the pond list (not a pond detail) is displayed.
      for (final id in ['pond-a', 'pond-b', 'pond-c']) {
        expect(find.byKey(ValueKey('pond-nav-$id')), findsOneWidget);
      }
      expect(find.text('Add pond'), findsOneWidget);
      expect(find.text('Suitable fish species'), findsNothing);
    },
  );

  testWidgets('switching away from Dashboard hides its pond sub-buttons', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pond-nav-pond-a')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-map')));
    await tester.pumpAndSettle();

    // Map (index 1): no pond sub-buttons, no "Add pond" FAB, no AppBar.
    expect(find.byKey(const ValueKey('pond-nav-pond-a')), findsNothing);
    expect(find.text('Add pond'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('tapping a pond opens its dashboard in the content area with the side panel intact', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Suitable fish species'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pond-nav-pond-a')));
    await tester.pumpAndSettle();

    // Content area now shows the pond's dashboard (not a full-screen push):
    // the side panel nav is still present, and there's a back action.
    expect(find.text('Suitable fish species'), findsAtLeastNWidgets(1));
    expect(find.text('All ponds'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-dashboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('pond-nav-pond-a')), findsOneWidget);

    // Back action returns to the pond list.
    await tester.tap(find.text('All ponds'));
    await tester.pumpAndSettle();
    expect(find.text('Suitable fish species'), findsNothing);
  });

  Future<void> setNarrowSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('mobile layout shows a greeting bar (avatar + bell) and a 4-item bottom nav without Notifications', (
    tester,
  ) async {
    await setNarrowSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Greeting header with a time-based greeting and the user's avatar.
    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.byType(CircleAvatar), findsAtLeastNWidgets(1));

    // Notification bell lives in the top bar now (as an icon).
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

    // Bottom nav has 4 destinations and no Notifications entry.
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.destinations.length, 4);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('tapping the bell opens the Notifications page', (tester) async {
    await setNarrowSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    // The pushed Notifications page shows its own titled AppBar.
    expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
  });
}
