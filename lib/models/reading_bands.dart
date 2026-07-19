import 'metric_type.dart';
import 'reading_status.dart';
import 'sensor_reading.dart';

/// Per-metric pond-health bands — independent from, and wider than, any
/// single fish species' optimal range. These answer "is this pond healthy
/// overall", while `SuggestionEngine` answers "which fish fit it".
class MetricBands {
  const MetricBands({
    this.criticalLow,
    this.warningLow,
    this.warningHigh,
    this.criticalHigh,
    required this.displayMin,
    required this.displayMax,
  });

  /// Null when this metric has no meaningful lower/upper bound (e.g.
  /// ammonia is only ever a problem when too *high*).
  final double? criticalLow;
  final double? warningLow;
  final double? warningHigh;
  final double? criticalHigh;

  /// Range used by [positionOf] to place a marker on a range bar — wider
  /// than the critical bounds so the marker never sits flush at the edge.
  final double displayMin;
  final double displayMax;

  ReadingStatus statusFor(double value) {
    final lo = criticalLow, hi = criticalHigh;
    if ((lo != null && value < lo) || (hi != null && value > hi)) {
      return ReadingStatus.critical;
    }
    final warnLo = warningLow, warnHi = warningHigh;
    if ((warnLo != null && value < warnLo) || (warnHi != null && value > warnHi)) {
      return ReadingStatus.warning;
    }
    return ReadingStatus.normal;
  }

  /// Value's position within [displayMin]..[displayMax], clamped to 0..1.
  double positionOf(double value) {
    return ((value - displayMin) / (displayMax - displayMin)).clamp(0.0, 1.0);
  }
}

const Map<MetricType, MetricBands> metricBands = {
  MetricType.temperature: MetricBands(
    criticalLow: 22,
    warningLow: 25,
    warningHigh: 29,
    criticalHigh: 32,
    displayMin: 18,
    displayMax: 36,
  ),
  MetricType.humidity: MetricBands(
    criticalLow: 55,
    warningLow: 65,
    warningHigh: 80,
    criticalHigh: 90,
    displayMin: 45,
    displayMax: 100,
  ),
  MetricType.ammonia: MetricBands(
    warningHigh: 0.05,
    criticalHigh: 0.15,
    displayMin: 0,
    displayMax: 0.3,
  ),
  MetricType.dissolvedOxygen: MetricBands(
    warningLow: 4,
    criticalLow: 2,
    displayMin: 0,
    displayMax: 9,
  ),
  MetricType.ph: MetricBands(
    criticalLow: 6.0,
    warningLow: 6.5,
    warningHigh: 8.5,
    criticalHigh: 9.0,
    displayMin: 4.5,
    displayMax: 10.5,
  ),
};

/// Worst status across every metric in [readings] — used for pond-level
/// at-a-glance health (list screen chip, dashboard summary banner).
ReadingStatus overallStatus(Map<MetricType, SensorReading> readings) {
  var worst = ReadingStatus.normal;
  for (final entry in readings.entries) {
    final status = metricBands[entry.key]!.statusFor(entry.value.value);
    if (status.index > worst.index) worst = status;
  }
  return worst;
}
