import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/models/metric_guidance.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/sensor_reading.dart';
import 'package:isdasafev2/models/trend_range.dart';
import 'package:isdasafev2/services/pond_snapshot_cache.dart';
import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';
import 'package:isdasafev2/theme/app_theme.dart';
import 'package:isdasafev2/widgets/individual_trend_chart.dart';
import 'package:isdasafev2/widgets/metric_detail_view.dart';
import 'package:isdasafev2/widgets/reading_grid.dart';

void main() {
  final pond = Pond(id: 'pond-a', name: 'Pond A');

  Future<void> showDetail(
    WidgetTester tester,
    MetricType type, {
    bool showHeader = true,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MetricDetailView(
            pond: pond,
            type: type,
            cache: PondSnapshotCache(),
            initialRange: TrendRange.hourly,
            showHeader: showHeader,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('leads with the current value, then explains the metric', (
    tester,
  ) async {
    await showDetail(tester, MetricType.dissolvedOxygen);

    // Header: the metric and its pond, with a close button.
    expect(find.text('Pond A'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    // The current value, its status and where it sits in the healthy range.
    expect(find.textContaining('Healthy:'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);
    // What it is.
    expect(find.text('What is Dissolved Oxygen?'), findsOneWidget);
    expect(find.text(MetricType.dissolvedOxygen.description), findsOneWidget);
    // Healthy readings: nothing to act on.
    expect(find.textContaining('What to do'), findsNothing);
    // The trend, with a custom timeframe, and the readings folded away.
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byType(IndividualTrendChart), findsOneWidget);
    expect(find.text('Show readings'), findsOneWidget);
  });

  testWidgets('on its own page the app bar has the title instead', (
    tester,
  ) async {
    await showDetail(tester, MetricType.ph, showHeader: false);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.text('What is pH Level?'), findsOneWidget);
  });

  testWidgets('humidity also shows the air temperature', (tester) async {
    await showDetail(tester, MetricType.humidity);

    // Both current values.
    expect(find.textContaining('Healthy:'), findsNWidgets(2));
    // The companion's explanation folds open on tap.
    expect(find.text(MetricType.airTemperature.description), findsNothing);
    await tester.tap(find.text('What is Air Temperature?'));
    await tester.pumpAndSettle();
    expect(find.text(MetricType.airTemperature.description), findsOneWidget);

    // One trend at a time; the switch picks which.
    expect(find.byType(IndividualTrendChart), findsOneWidget);
    final chart = find.byType(IndividualTrendChart);
    expect(
      tester.widget<IndividualTrendChart>(chart).type,
      MetricType.humidity,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<MetricType>),
        matching: find.text('Air Temperature'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<IndividualTrendChart>(chart).type,
      MetricType.airTemperature,
    );
  });

  testWidgets('ammonia also shows the free ammonia', (tester) async {
    await showDetail(tester, MetricType.ammonia);

    expect(find.text(MetricType.ammonia.description), findsOneWidget);
    expect(find.text('What is Free Ammonia?'), findsOneWidget);
    expect(find.text('Free Ammonia'), findsWidgets);
  });

  testWidgets('a value outside the healthy range says what to do', (
    tester,
  ) async {
    final previous = PondReadingsStore.instance;
    addTearDown(() => PondReadingsStore.instance = previous);
    PondReadingsStore.instance = PondReadingsStore(
      source: _OneReadingSource({
        MetricType.dissolvedOxygen: 2.5,
        MetricType.ph: 7,
        MetricType.ammonia: 0.02,
        MetricType.temperature: 27,
        MetricType.humidity: 70,
      }),
    );
    await tester.runAsync(PondReadingsStore.instance.refresh);

    await showDetail(tester, MetricType.dissolvedOxygen);
    expect(find.text('What to do: Dissolved Oxygen'), findsOneWidget);
    expect(
      find.text(guidanceFor(MetricType.dissolvedOxygen, 2.5)!),
      findsOneWidget,
    );
  });

  testWidgets('two readings fit a phone screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MetricDetailView(
            pond: pond,
            type: MetricType.humidity,
            cache: PondSnapshotCache(),
            initialRange: TrendRange.hourly,
            showHeader: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the custom timeframe sits below the presets', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MetricDetailView(
              pond: pond,
              type: MetricType.dissolvedOxygen,
              cache: PondSnapshotCache(),
              initialRange: TrendRange.hourly,
              showHeader: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');

      final custom = tester.getRect(find.text('Custom'));
      for (final r in TrendRange.values) {
        final preset = tester.getRect(find.text(r.label));
        expect(
          preset.overlaps(custom),
          isFalse,
          reason: '${r.label} overlaps Custom at width $width',
        );
        expect(preset.bottom, lessThanOrEqualTo(custom.top));
        // Every preset is fully on screen, not scrolled out of view.
        expect(preset.left, greaterThanOrEqualTo(0));
        expect(preset.right, lessThanOrEqualTo(width));
      }
    }
  });

  test('guidance only for values outside the healthy range', () {
    expect(guidanceFor(MetricType.dissolvedOxygen, 6), isNull);
    expect(guidanceFor(MetricType.dissolvedOxygen, 2.5), contains('aerat'));
    expect(guidanceFor(MetricType.ph, 5.8), contains('lime'));
    expect(guidanceFor(MetricType.ph, 9.2), contains('alkaline'));
    expect(
      guidanceFor(MetricType.freeAmmonia, 0.185),
      contains('Stop feeding'),
    );
  });

  testWidgets('tapping a reading card reports its metric', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final tapped = <MetricType>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ReadingGrid(
            readings: {
              MetricType.humidity: SensorReading(
                type: MetricType.humidity,
                value: 78,
                timestamp: now,
              ),
            },
            history: const {},
            onTapMetric: tapped.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Humidity'));
    // A metric without a reading yet still opens its explanation.
    await tester.tap(find.text('Free Ammonia'));
    expect(tapped, [MetricType.humidity, MetricType.freeAmmonia]);
  });
}

/// One paired pond ("pond-a") whose device uploaded one reading of [values].
class _OneReadingSource implements PondReadingsSource {
  _OneReadingSource(this.values);

  final Map<MetricType, double> values;

  @override
  Future<Map<String, String>> devicesByPond() async => {
    'pond-a': 'A1B2C3D4E5F6',
  };

  @override
  Future<List<StoredReading>> recentReadings(
    String pondId, {
    int limit = 200,
  }) async => [(time: DateTime.now(), values: values)];
}
