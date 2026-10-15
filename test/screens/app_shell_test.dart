import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/pond_verification.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/l10n/language_provider.dart';
import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/app_shell.dart';
import 'package:isdasafev2/widgets/app_tour.dart';
import 'package:isdasafev2/theme/app_theme.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_pond_repository.dart';

void main() {
  // AppShell mounts all 5 destinations via IndexedStack, and SettingsScreen
  // touches AuthService (→ Supabase.instance) at build. Initialize Supabase
  // once with throwaway credentials so those calls no-op (no session → null
  // user, no network) instead of asserting `_isInitialized`. We render
  // AppShell directly rather than the full app so these tests exercise the
  // side panel without going through the auth gate / a live session.
  // PondProvider itself is given a FakePondRepository (below) rather than
  // going through this Supabase client, since it's never pointed at a real
  // project.
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
    await Supabase.initialize(
      url: 'http://localhost',
      publishableKey: 'test-key',
    );
  });

  Widget buildApp({
    FakeNotificationRepository? notifications,
    FakePondRepository? ponds,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              PondProvider(repository: ponds ?? FakePondRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(
            repository: notifications ?? FakeNotificationRepository(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
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
      for (final name in [
        'dashboard',
        'map',
        'analytics',
        'notifications',
        'settings',
      ]) {
        expect(find.byKey(ValueKey('nav-$name')), findsOneWidget);
      }

      // Dashboard is active by default → its pond sub-buttons show, its FAB
      // shows, and the pond list (not a pond detail) is displayed.
      for (final id in ['pond-a', 'pond-b', 'pond-c']) {
        expect(find.byKey(ValueKey('pond-nav-$id')), findsOneWidget);
      }
      expect(find.text('Add pond'), findsOneWidget);
      expect(find.text('AI Recommended Species'), findsNothing);
    },
  );

  testWidgets('tapping the logo and name goes back to the Dashboard', (
    tester,
  ) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Add pond'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pumpAndSettle();
    expect(find.text('Add pond'), findsOneWidget);
    expect(find.byKey(const ValueKey('pond-nav-pond-a')), findsOneWidget);
  });

  testWidgets('the Ask AI button asks which pond, then opens the chat', (
    tester,
  ) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    expect(find.text('Which pond?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-pond-pond-a')));
    await tester.pumpAndSettle();
    expect(find.text('Pond assistant'), findsOneWidget);
    expect(find.text('Is my pond healthy right now?'), findsOneWidget);
  });

  testWidgets('switching away from Dashboard hides its pond sub-buttons', (
    tester,
  ) async {
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

  testWidgets(
    'tapping a pond opens its dashboard in the content area with the side panel intact',
    (tester) async {
      await setWideSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('AI Recommended Species'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pond-nav-pond-a')));
      await tester.pumpAndSettle();

      // Content area now shows the pond's dashboard (not a full-screen push):
      // the side panel nav is still present, and there's a back action.
      expect(find.text('AI Recommended Species'), findsAtLeastNWidgets(1));
      expect(find.text('All ponds'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-dashboard')), findsOneWidget);
      expect(find.byKey(const ValueKey('pond-nav-pond-a')), findsOneWidget);

      // Back action returns to the pond list.
      await tester.tap(find.text('All ponds'));
      await tester.pumpAndSettle();
      expect(find.text('AI Recommended Species'), findsNothing);
    },
  );

  Future<void> setNarrowSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'mobile layout shows a greeting bar (avatar + bell) and a 5-item bottom nav without Notifications',
    (tester) async {
      await setNarrowSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Greeting header with a time-based greeting and the user's avatar.
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.byType(CircleAvatar), findsAtLeastNWidgets(1));

      // Notification bell lives in the top bar now (as an icon).
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

      // Bottom nav has 5 destinations (Devices included) and no
      // Notifications entry.
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Notifications'), findsNothing);
    },
  );

  testWidgets('tapping the bell opens the Notifications page', (tester) async {
    await setNarrowSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    // The pushed Notifications page shows its own titled AppBar.
    expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
  });

  testWidgets('a new notification pops a snackbar that can be dismissed', (
    tester,
  ) async {
    await setNarrowSurface(tester);
    final notifications = FakeNotificationRepository();
    await tester.pumpWidget(buildApp(notifications: notifications));
    await tester.pumpAndSettle();

    notifications.push(
      fakeNotification(
        'n1',
        title: 'Pond verified',
        body: 'Pond X was verified.',
      ),
    );
    // Settles the snackbar's slide-in (its 8s auto-hide timer isn't a frame).
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Pond verified'), findsWidgets);
    expect(find.text('View'), findsOneWidget);

    // The close (X) button dismisses it without waiting out the timer.
    await tester.tap(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'a "photos needed" snackbar offers Add photos, which opens the photo modal',
    (tester) async {
      await setNarrowSurface(tester);
      final notifications = FakeNotificationRepository();
      final ponds = FakePondRepository(
        seed: [
          Pond(
            id: 'bld',
            name: 'Roof Pond',
            verificationStatus: VerificationStatus.needsPhotos,
          ),
        ],
      );
      await tester.pumpWidget(
        buildApp(notifications: notifications, ponds: ponds),
      );
      await tester.pumpAndSettle();

      notifications.push(
        fakeNotification(
          'n1',
          type: 'pond_needs_photos',
          title: 'Photos needed',
          body: 'Add at least 3 photos.',
        ).copyWithPond('bld'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('View'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Add photos'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add photos of “Roof Pond”'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the pop-up card itself for a "photos needed" notification opens the photo modal',
    (tester) async {
      await setNarrowSurface(tester);
      final notifications = FakeNotificationRepository();
      final ponds = FakePondRepository(
        seed: [
          Pond(
            id: 'bld',
            name: 'Roof Pond',
            verificationStatus: VerificationStatus.needsPhotos,
          ),
        ],
      );
      await tester.pumpWidget(
        buildApp(notifications: notifications, ponds: ponds),
      );
      await tester.pumpAndSettle();

      notifications.push(
        fakeNotification(
          'n1',
          type: 'pond_needs_photos',
          title: 'Photos needed',
          body: 'Add at least 3 photos.',
        ).copyWithPond('bld'),
      );
      await tester.pumpAndSettle();

      // Tap the message text, not the button.
      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Add at least 3 photos.'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add photos of “Roof Pond”'), findsOneWidget);
      // The pop-up is dismissed once acted on.
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  group('app tour', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => AppTour.autoStartEnabled = false);

    /// Presses Next (Finish on the last step) until the tour closes,
    /// returning how many steps were shown.
    Future<int> runThrough(WidgetTester tester) async {
      var steps = 0;
      while (find.byKey(const ValueKey('tour-next')).evaluate().isNotEmpty) {
        steps++;
        await tester.tap(find.byKey(const ValueKey('tour-next')));
        await tester.pumpAndSettle();
      }
      return steps;
    }

    testWidgets(
      'starts on first launch, walks every destination, and is not shown again',
      (tester) async {
        AppTour.autoStartEnabled = true;
        await setWideSurface(tester);
        await tester.pumpWidget(buildApp());
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(find.text('Welcome to Isda Safe'), findsOneWidget);
        expect(find.text('1 of 12'), findsOneWidget);

        // Each feature step switches to its destination behind the overlay.
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byKey(const ValueKey('tour-next')));
          await tester.pumpAndSettle();
        }
        expect(find.text('6 of 12'), findsOneWidget);
        expect(
          find.textContaining('Every pond pinned on one map'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('tour-back')));
        await tester.pumpAndSettle();
        expect(find.text('5 of 12'), findsOneWidget);

        for (var i = 0; i < 7; i++) {
          await tester.tap(find.byKey(const ValueKey('tour-next')));
          await tester.pumpAndSettle();
        }
        expect(find.text("You're all set!"), findsOneWidget);
        expect(find.text('Finish'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tour-next')));
        await tester.pumpAndSettle();

        expect(AppTour.isShowing, isFalse);
        expect(find.text("You're all set!"), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('app_tour_seen_v1'), isTrue);
        expect(await AppTour.shouldAutoStart(), isFalse);
      },
    );

    testWidgets('can be skipped, and replayed from Settings on mobile', (
      tester,
    ) async {
      AppTour.autoStartEnabled = true;
      await setNarrowSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tour-skip')));
      await tester.pumpAndSettle();
      expect(AppTour.isShowing, isFalse);

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('settings-app-tour'));
      await tester.scrollUntilVisible(tile, 200);
      // Bring it clear of the bottom nav bar before tapping.
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Tutorial'), findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Isda Safe'), findsOneWidget);
      expect(await runThrough(tester), 12);
      expect(AppTour.isShowing, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
