import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/screens/devices_screen.dart';
import 'package:isdasafev2/services/device_location_history.dart';
import 'package:isdasafev2/theme/app_theme.dart';

class _FakeHistory implements DeviceLocationHistory {
  _FakeHistory(this._stays);

  final List<DeviceStay> _stays;

  @override
  Future<List<String>> devices() async => ['6C383B124B00'];

  @override
  Future<List<DeviceStay>> stays(String deviceId) async => _stays;
}

DeviceStay _stay(
  int id,
  String? pondId,
  String? name,
  double? lat,
  int day,
  int readings, {
  bool current = false,
}) => DeviceStay(
  id: id,
  deviceId: '6C383B124B00',
  pondId: pondId,
  pondName: name,
  latitude: lat,
  longitude: lat == null ? null : 120.5,
  startedAt: DateTime(2026, 10, day),
  endedAt: current ? null : DateTime(2026, 10, day, 12),
  readingCount: readings,
);

void main() {
  // A device's history as the server returns it for one account: only that
  // account's own ponds, newest first. Ivory Pond was visited three times.
  final stays = [
    _stay(10, 'tilapia', 'Tilapia Pond', 14.66, 14, 40),
    _stay(7, 'ivory', 'Ivory Pond', 14.54, 12, 82),
    _stay(5, 'ivory', 'Ivory Pond', 14.54, 10, 2228),
    _stay(3, 'ivory', 'Ivory Pond', 14.54, 8, 107),
  ];

  setUp(() => DeviceLocationHistory.instance = _FakeHistory(stays));

  Future<void> pumpWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: DevicesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseDevice(WidgetTester tester) async {
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts by choosing a device', (tester) async {
    await pumpWide(tester);

    expect(find.text('Choose a device'), findsOneWidget);
    // Not in a pond now: where it was last, and how much it measured.
    expect(find.text('Last in Tilapia Pond'), findsOneWidget);
    expect(find.text('2 ponds · 2,457 complete readings'), findsOneWidget);
    expect(find.textContaining('tap one to see'), findsNothing);

    await chooseDevice(tester);
    expect(find.textContaining('2 ponds · tap one'), findsOneWidget);

    // Back to the chooser.
    await tester.tap(find.byTooltip('All devices'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a device'), findsOneWidget);
  });

  testWidgets('lists each pond once, with every visit to it', (tester) async {
    await pumpWide(tester);
    await chooseDevice(tester);

    expect(find.textContaining('2 ponds'), findsOneWidget);
    expect(find.text('Ivory Pond'), findsOneWidget);
    expect(find.text('3 visits'), findsOneWidget);
    // All three Ivory Pond visits' readings together.
    expect(find.text('2,417 complete readings'), findsOneWidget);
    // No numbers beside pond names.
    for (final n in ['1', '2', '3', '4']) {
      expect(find.text(n), findsNothing);
    }
  });

  testWidgets('opening a pond shows its visits and readings', (tester) async {
    await pumpWide(tester);
    await chooseDevice(tester);

    await tester.tap(find.text('Ivory Pond'));
    await tester.pumpAndSettle();

    // Its three visits, newest first, each with its own readings; the
    // newest is shown.
    for (final visit in ['Visit 1', 'Visit 2', 'Visit 3']) {
      expect(find.text(visit), findsOneWidget);
    }
    expect(find.text('Complete readings · visit 3'), findsOneWidget);
    expect(find.text('2,417'), findsOneWidget);

    await tester.tap(find.text('Visit 1'));
    await tester.pumpAndSettle();
    expect(find.text('Complete readings · visit 1'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Visit 1'), findsNothing);
    expect(find.textContaining('2 ponds'), findsOneWidget);
  });
}
