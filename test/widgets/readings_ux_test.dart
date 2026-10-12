import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/sensor_reading.dart';
import 'package:isdasafev2/models/trend_range.dart';
import 'package:isdasafev2/theme/app_theme.dart';
import 'package:isdasafev2/widgets/reading_history_table.dart';
import 'package:isdasafev2/widgets/timeframe_picker.dart';

void main() {
  void setScreen(WidgetTester tester, double width, [double height = 844]) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('TimeframePicker', () {
    final october = DateTimeRange(
      start: DateTime(2026, 10),
      end: DateTime(2026, 10, 11),
    );

    Future<void> pump(WidgetTester tester, TrendSelection selection) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: TimeframePicker(selection: selection, onChanged: (_) {}),
              ),
            ),
          ),
        );

    testWidgets('on a phone every preset and custom is on screen, apart', (
      tester,
    ) async {
      for (final width in [320.0, 360.0, 412.0]) {
        for (final selection in [
          const TrendSelection.preset(TrendRange.hourly),
          TrendSelection.dates(october),
        ]) {
          setScreen(tester, width);
          await pump(tester, selection);
          expect(tester.takeException(), isNull, reason: 'width $width');

          final customRect = tester.getRect(
            find.text(selection.customLabel ?? 'Custom'),
          );
          final presets = [
            for (final r in TrendRange.values)
              tester.getRect(find.text(r.label)),
          ];
          for (final (i, preset) in presets.indexed) {
            expect(preset.left, greaterThanOrEqualTo(0));
            expect(preset.right, lessThanOrEqualTo(width));
            expect(preset.overlaps(customRect), isFalse);
            expect(customRect.right, lessThanOrEqualTo(width));
            for (final other in presets.skip(i + 1)) {
              expect(preset.overlaps(other), isFalse);
            }
          }
          // Clearing and "Group by" only while a custom range is in use.
          final isCustom = selection.isCustom;
          expect(
            find.byTooltip('Clear custom timeframe'),
            isCustom ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Group by'),
            isCustom ? findsOneWidget : findsNothing,
          );
        }
      }
    });

    testWidgets('says what is shown', (tester) async {
      setScreen(tester, 1000);
      await pump(tester, const TrendSelection.preset(TrendRange.daily));
      expect(find.text('Last 7 days · by day'), findsOneWidget);

      await pump(tester, TrendSelection.dates(october));
      expect(find.text('Oct 1 – Oct 11 · by day'), findsOneWidget);
      await pump(
        tester,
        TrendSelection.dates(october, customStep: TrendStep.week),
      );
      expect(find.text('Oct 1 – Oct 11 · by week'), findsOneWidget);
    });

    testWidgets('on a wide screen the presets share one line', (tester) async {
      setScreen(tester, 1000);
      await pump(tester, const TrendSelection.preset(TrendRange.hourly));
      final first = tester.getRect(find.text(TrendRange.values.first.label));
      for (final r in TrendRange.values) {
        final rect = tester.getRect(find.text(r.label));
        expect((rect.center.dy - first.center.dy).abs(), lessThan(4));
      }
    });
  });

  group('ReadingHistoryTable', () {
    // 60 readings a minute apart, newest last.
    final now = DateTime(2026, 10, 11, 12);
    Map<MetricType, List<SensorReading>> history() => {
      for (final type in [
        MetricType.dissolvedOxygen,
        MetricType.temperature,
        MetricType.ph,
      ])
        type: [
          for (var i = 59; i >= 0; i--)
            SensorReading(
              type: type,
              value: switch (type) {
                MetricType.dissolvedOxygen => 6.0,
                MetricType.temperature => 27.0,
                _ => 7.2,
              },
              timestamp: now.subtract(Duration(minutes: i)),
            ),
        ],
    };

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ReadingHistoryTable(history: history()),
          ),
        ),
      ),
    );

    testWidgets('on a phone each value has its sensor name over it', (
      tester,
    ) async {
      setScreen(tester, 360);
      await pump(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final label = tester.getRect(find.text('Dissolved Oxygen').first);
      final value = tester.getRect(find.text('6.0mg/L').first);
      expect(label.bottom, lessThanOrEqualTo(value.top));
      expect(find.text('Water Temperature'), findsWidgets);
      expect(find.text('pH Level'), findsWidgets);
    });

    testWidgets('shows 20 readings, then more as you scroll down', (
      tester,
    ) async {
      setScreen(tester, 360);
      await pump(tester);
      await tester.pumpAndSettle();

      // Newest first: 12:00 PM ... 11:41 AM.
      expect(find.text('12:00 PM'), findsOneWidget);
      expect(find.text('11:41 AM'), findsOneWidget);
      expect(find.text('11:40 AM'), findsNothing);

      // Scroll to the end: the next page appears by itself.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      expect(find.text('11:40 AM'), findsOneWidget);

      // Keep going until every reading is shown.
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -10000),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('11:01 AM'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });
  });
}
