import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import 'pond_snapshot_cache.dart';
import 'usb_sensor/pond_readings_store.dart';

/// One step of a trend: the readings taken from [time] until the next step.
@immutable
class TrendPoint {
  const TrendPoint({
    required this.time,
    required this.avg,
    required this.min,
    required this.max,
    required this.count,
  });

  /// When the step starts.
  final DateTime time;
  final double avg;
  final double min;
  final double max;

  /// How many readings it's based on.
  final int count;

  /// The step as a single value (its average), for the chart's line.
  SensorReading asReading(MetricType type) =>
      SensorReading(type: type, value: avg, timestamp: time);
}

/// Each metric's steps, oldest first. Steps without readings are left out.
typedef TrendSeries = Map<MetricType, List<TrendPoint>>;

/// Lowest, average and highest of a series, and how many readings it covers.
typedef TrendStats = ({
  TrendPoint lowest,
  TrendPoint highest,
  double average,
  int readings,
});

TrendStats? statsOf(List<TrendPoint> points) {
  if (points.isEmpty) return null;
  var lowest = points.first, highest = points.first;
  var sum = 0.0;
  var count = 0;
  for (final p in points) {
    if (p.min < lowest.min) lowest = p;
    if (p.max > highest.max) highest = p;
    sum += p.avg * p.count;
    count += p.count;
  }
  return (
    lowest: lowest,
    highest: highest,
    average: count == 0 ? points.first.avg : sum / count,
    readings: count,
  );
}

/// Where trends come from.
abstract class TrendSource {
  Future<TrendSeries> load(
    Pond pond,
    DateTime start,
    DateTime end,
    TrendStep step,
  );
}

/// Grouped on the server (`pond_reading_trend`), so only one row per step and
/// metric is downloaded, however long the timeframe.
class SupabaseTrendSource implements TrendSource {
  static final _metricOf = {
    for (final e in SupabasePondReadingsSource.columns.entries) e.value: e.key,
    'free_ammonia': MetricType.freeAmmonia,
  };

  @override
  Future<TrendSeries> load(
    Pond pond,
    DateTime start,
    DateTime end,
    TrendStep step,
  ) async {
    final rows =
        await Supabase.instance.client.rpc(
              'pond_reading_trend',
              params: {
                'p_pond_id': pond.id,
                'p_start': start.toUtc().toIso8601String(),
                'p_end': end.toUtc().toIso8601String(),
                'p_step': step.rpcName,
              },
            )
            as List<dynamic>;
    final series = <MetricType, List<TrendPoint>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final type = _metricOf[row['metric']];
      if (type == null) continue;
      (series[type] ??= []).add(
        TrendPoint(
          time: DateTime.parse(row['bucket'] as String).toLocal(),
          avg: (row['avg_value'] as num).toDouble(),
          min: (row['min_value'] as num).toDouble(),
          max: (row['max_value'] as num).toDouble(),
          count: (row['readings'] as num).toInt(),
        ),
      );
    }
    return series;
  }
}

/// Groups readings already on hand (per metric, oldest first).
TrendSeries groupReadings(
  Map<MetricType, List<SensorReading>> history,
  DateTime start,
  DateTime end,
  TrendStep step,
) {
  final series = <MetricType, List<TrendPoint>>{};
  for (final entry in history.entries) {
    final byStep = <DateTime, List<double>>{};
    for (final r in entry.value) {
      if (r.timestamp.isBefore(start) || r.timestamp.isAfter(end)) continue;
      (byStep[step.floor(r.timestamp)] ??= []).add(r.value);
    }
    final steps = byStep.keys.toList()..sort();
    if (steps.isEmpty) continue;
    series[entry.key] = [
      for (final t in steps)
        if (byStep[t]! case final values)
          TrendPoint(
            time: t,
            avg: values.reduce((a, b) => a + b) / values.length,
            min: values.reduce((a, b) => a < b ? a : b),
            max: values.reduce((a, b) => a > b ? a : b),
            count: values.length,
          ),
    ];
  }
  return series;
}

/// The readings the app already holds for [pond] (the latest few hundred,
/// plus live USB readings): used when the server can't group them.
class LocalTrendSource implements TrendSource {
  @override
  Future<TrendSeries> load(
    Pond pond,
    DateTime start,
    DateTime end,
    TrendStep step,
  ) async {
    final history = PondSnapshotCache.compose(pond)?.history ?? const {};
    return groupReadings(history, start, end, step);
  }
}

/// One pond's trend for one [TrendSelection]: loads once, from the server
/// when it can, otherwise from the readings already on hand ([partial]).
class TrendController extends ChangeNotifier {
  TrendController(this.pond, this.selection, {TrendSource? source})
    : window = selection.window(),
      step = selection.step,
      _source = source ?? SupabaseTrendSource() {
    unawaited(_load());
  }

  final Pond pond;
  final TrendSelection selection;
  final DateTimeRange window;
  final TrendStep step;
  final TrendSource _source;

  TrendSeries? _series;
  bool _partial = false;
  bool _disposed = false;
  final _loaded = Completer<TrendSeries>();

  /// Completes with [series] once it's loaded.
  Future<TrendSeries> get loaded => _loaded.future;

  /// Null while loading.
  TrendSeries? get series => _series;
  bool get loading => _series == null;

  /// The server couldn't group the readings, so this only covers the latest
  /// readings the app had on hand.
  bool get partial => _partial;

  List<TrendPoint> pointsFor(MetricType type) => _series?[type] ?? const [];

  Future<void> _load() async {
    TrendSeries series;
    try {
      series = await _source.load(pond, window.start, window.end, step);
    } catch (e) {
      debugPrint('TrendController: falling back to local readings: $e');
      series = await LocalTrendSource().load(
        pond,
        window.start,
        window.end,
        step,
      );
      _partial = true;
    }
    _loaded.complete(series);
    if (_disposed) return;
    _series = series;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
