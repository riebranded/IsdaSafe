import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:isdasafev2/models/pond_verification.dart';
import 'package:isdasafev2/services/location_search_service.dart';
import 'package:isdasafev2/services/pond_photo_picker.dart';
import 'package:isdasafev2/widgets/pond_dialogs.dart';

class _FakePhotoPicker implements PondPhotoPicker {
  int picks = 0;

  @override
  bool get usesCamera => false;

  @override
  Future<List<PondPhoto>> pickPhotos({required int maxCount}) async {
    final photos = <PondPhoto>[];
    for (var i = 0; i < 2 && i < maxCount; i++) {
      photos.add((await pickPhoto())!);
    }
    return photos;
  }

  @override
  Future<PondPhoto?> pickPhoto() async {
    picks++;
    return PondPhoto(
      // 1x1 transparent PNG.
      bytes: Uint8List.fromList(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x0d,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1f,
        0x15,
        0xc4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0d,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9c,
        0x63,
        0xf8,
        0xff,
        0xff,
        0x3f,
        0x00,
        0x05,
        0xfe,
        0x02,
        0xfe,
        0xa7,
        0x35,
        0x81,
        0x84,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4e,
        0x44,
        0xae,
        0x42,
        0x60,
        0x82,
      ]),
      mediaType: 'image/png',
    );
  }
}

class _FakeLocationSearch implements LocationSearchService {
  _FakeLocationSearch({this.results = const [], this.error});

  final List<PlaceResult> results;
  final LocationSearchException? error;
  final queries = <String>[];

  @override
  Future<List<PlaceResult>> search(String query) async {
    queries.add(query);
    if (error != null) throw error!;
    return results;
  }
}

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    required void Function(NewPondDraft?) onResult,
    CurrentLocationLoader? loader,
    PondPhotoPicker? picker,
    LocationSearchService? search,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              onResult(
                await showAddPondDialog(
                  context,
                  currentLocationLoader:
                      loader ?? () async => const LatLng(14.5995, 120.9842),
                  photoPicker: picker ?? _FakePhotoPicker(),
                  locationSearch: search ?? _FakeLocationSearch(),
                ),
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
  }

  testWidgets('current location initializes a valid pond pin', (tester) async {
    NewPondDraft? result;
    await openDialog(tester, onResult: (r) => result = r);

    expect(find.text("You're here"), findsOneWidget);
    // Desktop test runs hit the manual lat/lng fallback (no Android/iOS/web
    // platform view), which shows the resolved location's coordinates.
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '14.5995',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '120.9842',
    );

    await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Located pond');
    await tester.pump();

    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add pond'),
    );
    expect(addButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    // Returns straight away — verification happens later, on the server.
    expect(result?.name, 'Located pond');
    expect(result?.latitude, 14.5995);
    expect(result?.longitude, 120.9842);
    expect(result?.verification.method, VerificationMethod.satellite);
    expect(result?.verification.photo, isNull);
  });

  testWidgets('in-house pond skips satellite and needs at least 3 photos', (
    tester,
  ) async {
    NewPondDraft? result;
    await openDialog(tester, onResult: (r) => result = r);
    await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Backyard tank');
    await tester.pump();

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    // No separate step any more: the same form, with the photos now required.
    expect(find.text('Required'), findsOneWidget);
    expect(find.textContaining('0 of 3 photos'), findsOneWidget);
    Finder add() => find.widgetWithText(FilledButton, 'Add pond');
    expect(tester.widget<FilledButton>(add()).onPressed, isNull);

    await tester.ensureVisible(find.text('Add photos'));
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 3 photos'), findsOneWidget);
    expect(tester.widget<FilledButton>(add()).onPressed, isNull);

    await tester.ensureVisible(find.text('Add photos'));
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(add()).onPressed, isNotNull);

    await tester.tap(add());
    await tester.pumpAndSettle();

    expect(result?.name, 'Backyard tank');
    expect(result?.verification.method, VerificationMethod.photo);
    expect(result?.verification.evidencePhotos, hasLength(4));
  });

  testWidgets('map opens immediately and preserves manual adjustment', (
    tester,
  ) async {
    final location = Completer<LatLng?>();
    NewPondDraft? result;
    await openDialog(
      tester,
      onResult: (r) => result = r,
      loader: () => location.future,
    );

    // Desktop test runs hit the manual lat/lng fallback (no Android/iOS/web
    // platform view).
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Manual pond');
    await tester.enterText(find.byType(TextField).at(0), '15.0000');
    await tester.pump();

    location.complete(const LatLng(14.5995, 120.9842));
    await tester.pump();
    await tester.pump();

    expect(find.text("You're here"), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Manual pond');
    expect(result?.latitude, isNot(14.5995));
    expect(result?.longitude, isNot(120.9842));
  });

  testWidgets('searching for a place and picking a result moves the pin', (
    tester,
  ) async {
    NewPondDraft? result;
    final search = _FakeLocationSearch(
      results: const [
        PlaceResult(
          displayName: 'Calamba, Laguna, Calabarzon, Philippines',
          latitude: 14.2117,
          longitude: 121.1653,
        ),
      ],
    );
    // No device location, so the pin only moves because of the search.
    await openDialog(
      tester,
      onResult: (r) => result = r,
      loader: () async => null,
      search: search,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Lakeside pond');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add pond'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).at(3), 'Calamba');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(search.queries, ['Calamba']);
    expect(find.widgetWithText(ListTile, 'Calamba'), findsOneWidget);
    expect(find.text('Laguna, Calabarzon, Philippines'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Calamba'));
    await tester.pumpAndSettle();

    // Results close, the pin sits on the place, and the pond can be added.
    expect(find.text('Laguna, Calabarzon, Philippines'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
    await tester.pumpAndSettle();

    expect(result?.latitude, 14.2117);
    expect(result?.longitude, 121.1653);
  });

  testWidgets('search says so when nothing is found or the search fails', (
    tester,
  ) async {
    await openDialog(tester, onResult: (_) {}, search: _FakeLocationSearch());
    await tester.enterText(find.byType(TextField).at(3), 'Nowhereville');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('No places found'), findsOneWidget);
  });

  testWidgets('a failed search shows the error and keeps the dialog usable', (
    tester,
  ) async {
    await openDialog(
      tester,
      onResult: (_) {},
      search: _FakeLocationSearch(
        error: const LocationSearchException('Search is busy right now.'),
      ),
    );
    await tester.enterText(find.byType(TextField).at(3), 'Calamba');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search is busy right now.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add pond'), findsOneWidget);
  });

  testWidgets('verification started dialog explains the follow-up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showVerificationStartedDialog(
              context,
              pondName: 'Pond X',
              method: VerificationMethod.photo,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    // Not pumpAndSettle: the dialog shows a spinner that never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Pond X'), findsOneWidget);
    expect(find.text('Checking your pond photos'), findsOneWidget);
    expect(find.textContaining('notify you on your device'), findsOneWidget);
    // SMS is switched off, so the dialog must not promise a text.
    expect(find.textContaining('text'), findsNothing);
    expect(find.textContaining('notify you on your device'), findsOneWidget);
    expect(find.textContaining('appears on your dashboard'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Pond X'), findsNothing);
  });

  testWidgets('edit location dialog opens centered on current location', (
    tester,
  ) async {
    LocationDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showEditLocationDialog(
                context,
                initialLatitude: 10.0,
                initialLongitude: 100.0,
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

    // Centers on the current location, not the pond's saved coordinates.
    expect(find.text('14.5995, 120.9842'), findsOneWidget);
    expect(find.text("You're here"), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Save location'));
    await tester.pumpAndSettle();

    expect(result?.latitude, 14.5995);
    expect(result?.longitude, 120.9842);
  });

  testWidgets(
    'edit location dialog falls back to the pond location when current '
    'location is unavailable',
    (tester) async {
      LocationDraft? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showEditLocationDialog(
                  context,
                  initialLatitude: 10.0,
                  initialLongitude: 100.0,
                  currentLocationLoader: () async => null,
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

      expect(find.text('10.0000, 100.0000'), findsOneWidget);
      expect(find.text("You're here"), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save location'));
      await tester.pumpAndSettle();

      expect(result?.latitude, 10.0);
      expect(result?.longitude, 100.0);
    },
  );

  testWidgets('edit location locate-me button recenters without a snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await showEditLocationDialog(
                context,
                initialLatitude: 10.0,
                initialLongitude: 100.0,
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

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Use my current location'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  group('photos section on the add pond form', () {
    Future<void> addPhotos(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Add photos'));
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'accepts several pictures and sends them when there are enough',
      (tester) async {
        NewPondDraft? result;
        await openDialog(tester, onResult: (r) => result = r);
        await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Roof pond');
        await tester.pump();

        expect(find.text('Photos of your pond'), findsOneWidget);
        expect(find.text('Optional'), findsOneWidget);

        // One pick adds two pictures at once...
        await addPhotos(tester);
        expect(find.byType(Image), findsNWidgets(2));
        // ...and a second pick takes it past the minimum.
        await addPhotos(tester);
        expect(find.byType(Image), findsNWidgets(4));
        expect(find.text('4 photos ready.'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
        await tester.pumpAndSettle();

        expect(result?.verification.method, VerificationMethod.satellite);
        expect(result?.verification.evidencePhotos, hasLength(4));
      },
    );

    testWidgets('fewer than the minimum are explained and not sent', (
      tester,
    ) async {
      NewPondDraft? result;
      await openDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.widgetWithText(TextField, 'Pond name'), 'Roof pond');
      await tester.pump();

      await addPhotos(tester);
      expect(find.textContaining('Add 1 more'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add pond'));
      await tester.pumpAndSettle();

      expect(result?.name, 'Roof pond');
      expect(result?.verification.evidencePhotos, isEmpty);
    });

    testWidgets('a photo can be removed again', (tester) async {
      await openDialog(tester, onResult: (_) {});
      await addPhotos(tester);
      expect(find.byType(Image), findsNWidgets(2));

      await tester.tap(find.bySemanticsLabel('Remove photo').first);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(1));
    });

    testWidgets(
      'the section stays for in-house ponds, switching from optional to required',
      (tester) async {
        await openDialog(tester, onResult: (_) {});
        expect(find.text('Photos of your pond'), findsOneWidget);
        expect(find.text('Optional'), findsOneWidget);

        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();

        expect(find.text('Photos of your pond'), findsOneWidget);
        expect(find.text('Required'), findsOneWidget);
        expect(find.text('Optional'), findsNothing);
      },
    );
  });

  group('evidence photos dialog', () {
    Future<void> open(
      WidgetTester tester, {
      required void Function(List<PondPhoto>?) onResult,
      PondPhotoPicker? picker,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                onResult(
                  await showEvidencePhotosDialog(
                    context,
                    pondName: 'Roof Pond',
                    photoPicker: picker ?? _FakePhotoPicker(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Finder submit() => find.byType(FilledButton).last;

    testWidgets('needs at least 3 photos before it can be submitted', (
      tester,
    ) async {
      List<PondPhoto>? result;
      await open(tester, onResult: (r) => result = r);

      expect(find.textContaining('Roof Pond'), findsOneWidget);
      expect(find.textContaining('0 of 3 photos'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit()).onPressed, isNull);

      // A single pick brings in two pictures: still short of three.
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 3 photos'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit()).onPressed, isNull);

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 photos added'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit()).onPressed, isNotNull);

      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(result, hasLength(4));
    });

    testWidgets('the add button disappears at the maximum', (tester) async {
      await open(tester, onResult: (_) {});

      for (var i = 0; i < kMaxEvidencePhotos ~/ 2; i++) {
        await tester.tap(find.text('Add photos'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Add photos'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Remove photo').first);
      await tester.pumpAndSettle();
      expect(find.text('Add photos'), findsOneWidget);
    });

    testWidgets('cancel returns nothing', (tester) async {
      var called = false;
      List<PondPhoto>? result;
      await open(
        tester,
        onResult: (r) {
          called = true;
          result = r;
        },
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(result, isNull);
    });
  });
}
