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
  const PondSnapshot({required this.pond, required this.readings});

  final Pond pond;
  final Map<MetricType, SensorReading> readings;

  SensorReading reading(MetricType type) => readings[type]!;
}
