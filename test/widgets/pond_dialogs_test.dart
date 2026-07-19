import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:isdasafev2/widgets/location_picker_map.dart';
import 'package:isdasafev2/widgets/pond_dialogs.dart';

void main() {
  testWidgets('current location initializes a valid pond pin', (tester) async {
    NewPondDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showAddPondDialog(
                context,
                currentLocationLoader: () async =>
                    const LatLng(14.5995, 120.9842),
              );
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();
    await tester.pump();

    expect(find.text('14.5995, 120.9842'), findsOneWidget);
    expect(find.text("You're here"), findsOneWidget);
    expect(
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.initialZoom,
      kUserLocationMapZoom,
    );
    final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tileLayer.panBuffer, 0);
    expect(tileLayer.keepBuffer, 1);
    expect(
      tileLayer.tileDisplay.when(
        instantaneous: (_) => true,
        fadeIn: (_) => false,
      ),
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'Located pond');
    await tester.pump();

    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add pond'),
    );
    expect(addButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Located pond');
    expect(result?.latitude, 14.5995);
    expect(result?.longitude, 120.9842);
  });

  testWidgets('map opens immediately and preserves manual adjustment', (
    tester,
  ) async {
    final location = Completer<LatLng?>();
    NewPondDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showAddPondDialog(
                context,
                currentLocationLoader: () => location.future,
              );
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.text('Finding your location… You can adjust the map now.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Manual pond');
    await tester.drag(find.byType(FlutterMap), const Offset(60, 0));
    await tester.pump();

    location.complete(const LatLng(14.5995, 120.9842));
    await tester.pump();
    await tester.pump();

    expect(find.text('14.5995, 120.9842'), findsNothing);
    expect(find.text("You're here"), findsNothing);
    expect(
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.initialZoom,
      kDefaultMapZoom,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Manual pond');
    expect(result?.latitude, isNot(14.5995));
    expect(result?.longitude, isNot(120.9842));
  });
}
