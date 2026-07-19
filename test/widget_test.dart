import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/app.dart';
import 'package:isdasafev2/providers/pond_provider.dart';

void main() {
  late GeolocatorPlatform originalGeolocator;

  setUpAll(() {
    originalGeolocator = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _DeniedGeolocator();
  });

  tearDownAll(() {
    GeolocatorPlatform.instance = originalGeolocator;
  });

  Widget buildApp() {
    return ChangeNotifierProvider(
      create: (_) => PondProvider(),
      child: const IsdaSafeApp(),
    );
  }

  testWidgets('shows the seeded mock ponds on launch', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('Pond A'), findsOneWidget);
    expect(find.text('Pond B'), findsOneWidget);
    expect(find.text('Pond C'), findsOneWidget);
  });

  testWidgets('adding a pond shows it in the list', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(
      find.text('Location unavailable. Pan the map to position the pin.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Pond D');
    await tester.drag(find.byType(FlutterMap), const Offset(40, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    expect(find.text('Pond D'), findsOneWidget);
  });

  testWidgets(
    'tapping a pond opens its dashboard with readings and suggestions',
    (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Pond A'));
      await tester.pumpAndSettle();

      expect(find.text('Latest readings'), findsOneWidget);
      expect(find.text('Water Temperature'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('Ammonia'), findsOneWidget);
      expect(find.text('Dissolved Oxygen'), findsOneWidget);
      expect(find.text('pH Level'), findsOneWidget);

      expect(find.text('Suitable fish species'), findsOneWidget);
      expect(find.text('Tilapia (Tilapia)'), findsOneWidget);
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
