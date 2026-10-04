import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/app.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/app_shell.dart';

import 'support/fake_notification_repository.dart';
import 'support/fake_pond_repository.dart';

void main() {
  late GeolocatorPlatform originalGeolocator;

  setUpAll(() async {
    // AppShell's settings tab touches AuthService (-> Supabase.instance), so
    // initialize Supabase with throwaway credentials (see app_shell_test).
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : null,
        );
    await Supabase.initialize(
      url: 'http://localhost',
      publishableKey: 'test-key',
    );
    originalGeolocator = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _DeniedGeolocator();
  });

  tearDownAll(() {
    GeolocatorPlatform.instance = originalGeolocator;
  });

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PondProvider(repository: FakePondRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              NotificationProvider(repository: FakeNotificationRepository()),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const IsdaSafeApp(home: AppShell()),
    );
  }

  testWidgets('shows the seeded mock ponds on launch', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Pond A'), findsOneWidget);
    expect(find.text('Pond B'), findsOneWidget);
    expect(find.text('Pond C'), findsOneWidget);
  });

  testWidgets('adding a pond starts its verification', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(
      find.widgetWithText(TextField, 'Pond name'),
      'Pond D',
    );
    // Desktop test runs hit the manual lat/lng fallback (no Android/iOS/web
    // platform view); editing a coordinate simulates picking a location.
    await tester.enterText(find.byType(TextField).at(0), '10.3000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    // The dialog's spinner never settles, so pump a few frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // New ponds are verified before they reach the list, so the user is told
    // that's under way instead.
    expect(find.textContaining('Verifying'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'tapping a pond opens its dashboard with readings and suggestions',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Pond A'));
      await tester.pumpAndSettle();

      expect(find.text('Latest readings'), findsOneWidget);
      expect(find.text('Water Temperature'), findsAtLeastNWidgets(1));
      expect(find.text('Humidity'), findsAtLeastNWidgets(1));
      expect(find.text('Ammonia'), findsAtLeastNWidgets(1));
      expect(find.text('Dissolved Oxygen'), findsAtLeastNWidgets(1));
      expect(find.text('pH Level'), findsAtLeastNWidgets(1));

      expect(find.text('AI Recommended Species'), findsOneWidget);
    },
  );
}

class _DeniedGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;
}
