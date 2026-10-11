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
    Future<void> pump(WidgetTester tester, {DateTimeRange? custom}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: TimeframePicker(
                  range: TrendRange.hourly,
                  custom: custom,
                  customLabel: custom == null ? null : '10/1/2026 – 10/11/2026',
                  onRange: (_) {},
                  onCustom: () {},
                  onClearCustom: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('on a phone the custom button has its own line', (
      tester,
    ) async {
      for (final width in [320.0, 360.0, 412.0]) {
        for (final custom in [
          null,
          DateTimeRange(start: DateTime(2026, 10), end: DateTime(2026, 10, 11)),
        ]) {
          setScreen(tester, width);
          await pump(tester, custom: custom);
          expect(tester.takeException(), isNull, reason: 'width $width');

          final customRect = tester.getRect(
            find.text(custom == null ? 'Custom' : '10/1/2026 – 10/11/2026'),
          );
          for (final r in TrendRange.values) {
            final preset = tester.getRect(find.text(r.label));
            expect(preset.overlaps(customRect), isFalse);
            expect(preset.bottom, lessThanOrEqualTo(customRect.top));
            expect(preset.right, lessThanOrEqualTo(width));
          }
          // The clear button only while a custom range is in use.
          expect(
            find.byTooltip('Clear custom timeframe'),
            custom == null ? findsNothing : findsOneWidget,
          );
        }
      }
    });

    testWidgets('on a wide screen it all fits one line', (tester) async {
      setScreen(tester, 1000);
      await pump(tester);
      final custom = tester.getRect(find.text('Custom'));
      final hourly = tester.getRect(find.text('Hourly'));
      expect((custom.center.dy - hourly.center.dy).abs(), lessThan(4));
      expect(hourly.overlaps(custom), isFalse);
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
