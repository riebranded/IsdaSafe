import 'metric_type.dart';
import 'pond.dart';

class SensorReading {
  const SensorReading({
    required this.type,
    required this.value,
    required this.timestamp,
  });

  final MetricType type;
  final double value;
  final DateTime timestamp;
}

/// The latest readings a [Pond]'s device has sent. Only metrics the device
/// actually reported are present: a sensor that has never sent a value (e.g.
/// a disconnected probe) is missing from [readings] and [history].
class PondSnapshot {
  const PondSnapshot({
    required this.pond,
    required this.readings,
    required this.history,
  });

  final Pond pond;
  final Map<MetricType, SensorReading> readings;

  /// Recent trend per metric, oldest first, ending at the same reading
  /// returned by [reading]/[readings].
  final Map<MetricType, List<SensorReading>> history;

  SensorReading? reading(MetricType type) => readings[type];
  List<SensorReading> historyFor(MetricType type) => history[type] ?? const [];

  /// When the newest of [readings] was taken.
  DateTime? get latestAt => readings.values
      .map((r) => r.timestamp)
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  /// The metrics the AI advice needs (see `species_recommendation_service`).
  static const adviceMetrics = {
    MetricType.ammonia,
    MetricType.dissolvedOxygen,
    MetricType.ph,
    MetricType.temperature,
  };

  /// [adviceMetrics] the device hasn't reported yet.
  List<MetricType> get missingForAdvice => [
    for (final type in MetricType.values)
      if (adviceMetrics.contains(type) && !readings.containsKey(type)) type,
  ];
}
