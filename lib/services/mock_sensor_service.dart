import 'dart:math';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';

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

  PondSnapshot generateSnapshot(Pond pond) {
    final baselineRandom = Random(pond.seed);
    final jitterRandom = Random();
    final now = DateTime.now();

    final readings = <MetricType, SensorReading>{};
    for (final type in MetricType.values) {
      final band = _bands[type]!;
      final baseline = band.min + baselineRandom.nextDouble() * (band.max - band.min);
      final jitter = _jitter[type]!;
      var value = baseline + (jitterRandom.nextDouble() - 0.5) * 2 * jitter;
      value = value.clamp(band.min, band.max);

      readings[type] = SensorReading(type: type, value: value, timestamp: now);
    }

    return PondSnapshot(pond: pond, readings: readings);
  }
}
