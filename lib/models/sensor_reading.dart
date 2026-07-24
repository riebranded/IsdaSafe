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

/// A bundle of the latest readings for every [MetricType] on a [Pond].
class PondSnapshot {
  const PondSnapshot({required this.pond, required this.readings, required this.history});

  final Pond pond;
  final Map<MetricType, SensorReading> readings;

  /// Recent trend per metric, oldest first, ending at the same reading
  /// returned by [reading]/[readings] — see `MockSensorService` for how
  /// this is currently synthesized.
  final Map<MetricType, List<SensorReading>> history;

  SensorReading reading(MetricType type) => readings[type]!;
  List<SensorReading> historyFor(MetricType type) => history[type]!;
}
