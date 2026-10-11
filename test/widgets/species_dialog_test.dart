import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/widgets/pond_dialogs.dart';

void main() {
  /// Opens the species dialog and records what it returns.
  Future<List<SpeciesSelection?>> open(
    WidgetTester tester, {
    List<String> initialSelection = const [],
    Map<String, double> initialBiomassKg = const {},
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final results = <SpeciesSelection?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await showSelectSpeciesDialog(
                  context,
                  initialSelection: initialSelection,
                  initialBiomassKg: initialBiomassKg,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder biomassField(String species) =>
      find.widgetWithText(TextField, 'Biomass of $species (kg)');

  testWidgets('asks the biomass of each species picked', (tester) async {
    final results = await open(tester);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.textContaining('Tilapia'));
    await tester.pump();
    await tester.tap(find.textContaining('Milkfish'));
    await tester.pump();
    expect(biomassField('Tilapia'), findsOneWidget);
    expect(biomassField('Milkfish'), findsOneWidget);

    await tester.enterText(biomassField('Tilapia'), '120');
    await tester.enterText(biomassField('Milkfish'), '1,045.5');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(results.single?.names, ['Tilapia', 'Milkfish']);
    expect(results.single?.biomassKg, {'Tilapia': 120.0, 'Milkfish': 1045.5});
  });

  testWidgets('a picked species needs a valid biomass', (tester) async {
    final results = await open(tester);
    await tester.tap(find.textContaining('Tilapia'));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Enter the biomass in kg'), findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(biomassField('Tilapia'), '-5');
    await tester.pump();
    expect(find.textContaining('Enter a number between 0 and'), findsOneWidget);

    await tester.enterText(biomassField('Tilapia'), '80');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(results.single?.biomassKg, {'Tilapia': 80.0});
  });

  testWidgets('editing pre-fills the saved biomass', (tester) async {
    final results = await open(
      tester,
      initialSelection: ['Tilapia'],
      initialBiomassKg: {'Tilapia': 150},
    );
    expect(
      tester.widget<TextField>(biomassField('Tilapia')).controller!.text,
      '150',
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(results.single?.biomassKg, {'Tilapia': 150.0});
  });

  test('parseBiomassKg accepts plausible weights only', () {
    expect(parseBiomassKg('120'), 120);
    expect(parseBiomassKg(' 1,200.5 '), 1200.5);
    expect(parseBiomassKg('0'), isNull);
    expect(parseBiomassKg('-3'), isNull);
    expect(parseBiomassKg('abc'), isNull);
    expect(parseBiomassKg('200000'), isNull);
  });
}
