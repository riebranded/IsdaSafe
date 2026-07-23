import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/mock_sensor_service.dart';
import 'package:isdasafev2/theme/app_theme.dart';
import 'package:isdasafev2/widgets/reading_card.dart';
import 'package:isdasafev2/widgets/reading_grid.dart';

void main() {
  final snapshot = MockSensorService().generateSnapshot(Pond(id: 'p1', name: 'Pond A'));

  Widget wrap({required double boxWidth}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: boxWidth,
            child: SingleChildScrollView(
              child: ReadingGrid(readings: snapshot.readings, history: snapshot.history),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> setWideWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  SliverGridDelegate delegateOf(WidgetTester tester) {
    return tester.widget<GridView>(find.byType(GridView)).gridDelegate;
  }

  testWidgets(
    "narrow container on a wide window uses the responsive delegate and doesn't overflow "
    '(regression: the map page embeds this in a ~360px side panel)',
    (tester) async {
      await setWideWindow(tester);
      await tester.pumpWidget(wrap(boxWidth: 360));
      await tester.pumpAndSettle();

      // No RenderFlex overflow was recorded while laying the 5 cards out.
      expect(tester.takeException(), isNull);
      expect(find.byType(ReadingCard), findsNWidgets(5));
      // A fixed 5-column row can't fit 360px, so it must fall back to the
      // width-driven responsive delegate.
      expect(delegateOf(tester), isA<SliverGridDelegateWithMaxCrossAxisExtent>());
    },
  );

  testWidgets('a genuinely wide container on a wide window keeps the single fixed 5-column row', (tester) async {
    await setWideWindow(tester);
    await tester.pumpWidget(wrap(boxWidth: 1000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final delegate = delegateOf(tester);
    expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
    expect((delegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, 5);
  });
}
