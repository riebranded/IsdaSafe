import 'dart:math';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';

class _Band {
  const _Band(this.min, this.max);
  final double min;
  final double max;
}

/// Generates plausible mock sensor readings for a [Pond].
///
/// Baselines are derived from the pond's stable seed (so a given pond keeps
/// trending the same way across refreshes), then jittered slightly on every
/// call so each refresh still feels like a live reading.
class MockSensorService {
  // Deliberately wider than any single fish species' optimal range so that
  // some ponds legitimately mismatch some species.
  static const Map<MetricType, _Band> _bands = {
    MetricType.temperature: _Band(20, 34),
    MetricType.humidity: _Band(50, 95),
    MetricType.ammonia: _Band(0, 0.3),
    MetricType.dissolvedOxygen: _Band(1, 9),
    MetricType.ph: _Band(5.5, 9.5),
  };

  static const Map<MetricType, double> _jitter = {
    MetricType.temperature: 0.6,
    MetricType.humidity: 2,
    MetricType.ammonia: 0.01,
    MetricType.dissolvedOxygen: 0.3,
    MetricType.ph: 0.15,
  };

  static const int _historyPoints = 12;
  static const Duration _historyInterval = Duration(minutes: 30);

  PondSnapshot generateSnapshot(Pond pond) {
    final baselineRandom = Random(pond.seed);
    final jitterRandom = Random();
    final now = DateTime.now();

    final readings = <MetricType, SensorReading>{};
    final history = <MetricType, List<SensorReading>>{};
    for (final type in MetricType.values) {
      final band = _bands[type]!;
      final baseline =
          band.min + baselineRandom.nextDouble() * (band.max - band.min);
      final jitter = _jitter[type]!;
      var value = baseline + (jitterRandom.nextDouble() - 0.5) * 2 * jitter;
      value = value.clamp(band.min, band.max);

      readings[type] = SensorReading(type: type, value: value, timestamp: now);
      history[type] = _generateHistory(pond, type, band, jitter, value, now);
    }

    return PondSnapshot(pond: pond, readings: readings, history: history);
  }

  /// Synthesizes a short walk ending at [currentValue] — stands in for a
  /// real sensor's logged history until one exists. Seeded on `pond.seed`
  /// plus the metric, so the shape stays stable across refreshes; only the
  /// final point (the live, jittered current reading) moves.
  List<SensorReading> _generateHistory(
    Pond pond,
    MetricType type,
    _Band band,
    double jitter,
    double currentValue,
    DateTime now,
  ) {
    final walkRandom = Random(pond.seed ^ type.index);
    final step = jitter * 2;
    var value = band.min + walkRandom.nextDouble() * (band.max - band.min);

    final points = <SensorReading>[];
    for (var i = 0; i < _historyPoints - 1; i++) {
      final timestamp = now.subtract(
        _historyInterval * (_historyPoints - 1 - i),
      );
      points.add(SensorReading(type: type, value: value, timestamp: timestamp));
      value = (value + (walkRandom.nextDouble() - 0.5) * 2 * step).clamp(
        band.min,
        band.max,
      );
    }
    points.add(SensorReading(type: type, value: currentValue, timestamp: now));
    return points;
  }

  /// A self-contained synthetic series for the Analytics screen's day/week/
  /// month/year filter — independent of [generateSnapshot]'s fixed recent
  /// window. Seeded on the pond, metric, *and* range, so flipping between
  /// ranges and back doesn't reshuffle a range's shape.
  List<SensorReading> historyForRange(
    Pond pond,
    MetricType type,
    TrendRange range,
  ) {
    final band = _bands[type]!;
    final jitter = _jitter[type]!;
    final walkRandom = Random(pond.seed ^ type.index ^ (range.index << 8));
    final step = jitter * 2;
    var value = band.min + walkRandom.nextDouble() * (band.max - band.min);

    final now = DateTime.now();
    final pointCount = range.pointCount;
    final interval = range.interval;

    final points = <SensorReading>[];
    for (var i = 0; i < pointCount; i++) {
      final timestamp = now.subtract(interval * (pointCount - 1 - i));
      points.add(SensorReading(type: type, value: value, timestamp: timestamp));
      value = (value + (walkRandom.nextDouble() - 0.5) * 2 * step).clamp(
        band.min,
        band.max,
      );
    }
    return points;
  }
}
