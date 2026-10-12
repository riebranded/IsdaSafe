import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/app.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/l10n/language_provider.dart';
import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/app_shell.dart';
import 'package:isdasafev2/services/usb_sensor/device_registry.dart';
import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';
import 'package:isdasafev2/services/usb_sensor/usb_sensor_hub.dart';

import 'support/fake_notification_repository.dart';
import 'support/fake_serial_link.dart';
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
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
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
    final link = FakeSerialLink();
    final registry = FakeDeviceRegistry();
    UsbSensorHub.instance = UsbSensorHub(link: link);
    DeviceRegistry.instance = registry;

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Location first: no device step until the pond is verified.
    expect(find.text('Connect your IsdaSafe device'), findsNothing);
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
    expect(registry.claims, isEmpty);
    expect(link.written, isEmpty);
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'a verified pond shows no readings until a device is paired, then shows the device readings',
    (tester) async {
      final link = FakeSerialLink();
      final registry = FakeDeviceRegistry();
      final source = FakePondReadingsSource(registry);
      UsbSensorHub.instance = UsbSensorHub(link: link);
      DeviceRegistry.instance = registry;
      PondReadingsStore.instance = PondReadingsStore(source: source);
      addTearDown(
        () => PondReadingsStore.instance = PondReadingsStore.everyPondPaired(),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      Finder inPondA(Finder finder) => find.descendant(
        of: find.ancestor(of: find.text('Pond A'), matching: find.byType(Card)),
        matching: finder,
      );

      // No device paired: no readings, a pair prompt on the card instead.
      expect(inPondA(find.text('Pair a device')), findsOneWidget);
      expect(find.text('27.4°C'), findsNothing);

      // Pairing is by the device's QR label; tests have no camera, so type
      // the label's code instead.
      await tester.tap(inPondA(find.text('Pair a device')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Scan the device's QR label"), findsOneWidget);
      await tester.tap(find.text('Enter code instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'A1B2C3D4E5F6');
      await tester.enterText(find.byType(TextField).at(1), 'ABCD-2345-EFGH');
      await tester.tap(find.text('Pair'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The device is claimed and filed under Pond A; nothing goes over USB.
      expect(registry.claims.single, (
        'A1B2C3D4E5F6',
        'ABCD2345EFGH',
        'pond-a',
      ));
      expect(link.written, isEmpty);

      // Then how to put the device on WiFi: its setup hotspot.
      expect(find.text('Connect the device to WiFi'), findsOneWidget);
      expect(
        find.textContaining('IsdaSafe-E5F6', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Pond A has no species yet, so it's asked next.
      expect(find.text('Add fish species'), findsOneWidget);
      Navigator.of(tester.element(find.text('Add fish species'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The device's uploaded reading now shows on Pond A's card.
      expect(inPondA(find.text('Pair a device')), findsNothing);
      expect(inPondA(find.text('27.4°C')), findsOneWidget);
    },
  );

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
      expect(find.text('Free Ammonia'), findsAtLeastNWidgets(1));
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
