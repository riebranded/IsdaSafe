import 'metric_type.dart';
import 'reading_status.dart';
import 'sensor_reading.dart';
import 'weather_context.dart';

/// Per-metric pond-health bands — independent from, and wider than, any
/// single fish species' optimal range. These answer "is this pond healthy
/// overall", while the AI species recommendation answers "which fish fit it".
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
    if ((warnLo != null && value < warnLo) ||
        (warnHi != null && value > warnHi)) {
      return ReadingStatus.warning;
    }
    return ReadingStatus.normal;
  }

  /// Value's position within [displayMin]..[displayMax], clamped to 0..1.
  double positionOf(double value) {
    return ((value - displayMin) / (displayMax - displayMin)).clamp(0.0, 1.0);
  }

  /// 0 = safely inside the normal band, 1 = at/beyond the critical
  /// threshold, on either side — direction-agnostic so "rising" always
  /// means "toward trouble," unlike [positionOf] (which just reflects
  /// display-range position and reads backwards for metrics where high is
  /// good, e.g. dissolved oxygen). Used to put every metric on one shared,
  /// comparable axis for cross-metric status logic (e.g. [overallStatus]).
  double riskOf(double value) {
    final safeLo = warningLow ?? displayMin;
    final safeHi = warningHigh ?? displayMax;

    if (value < safeLo) {
      final critLo = criticalLow ?? displayMin;
      if (safeLo == critLo) return 1.0;
      return ((safeLo - value) / (safeLo - critLo)).clamp(0.0, 1.0);
    }
    if (value > safeHi) {
      final critHi = criticalHigh ?? displayMax;
      if (safeHi == critHi) return 1.0;
      return ((value - safeHi) / (critHi - safeHi)).clamp(0.0, 1.0);
    }
    return 0.0;
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
  // Weather, not water: no limits of its own (tropical air is often 85%+).
  // It matters through `weatherInsights`, which judge it together with the
  // water readings.
  MetricType.humidity: MetricBands(displayMin: 30, displayMax: 100),
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
  // Air around the device; comfortable for tropical ponds in between.
  MetricType.airTemperature: MetricBands(
    criticalLow: 18,
    warningLow: 22,
    warningHigh: 33,
    criticalHigh: 37,
    displayMin: 15,
    displayMax: 42,
  ),
  // Un-ionised NH3: harmful to most farmed fish above ~0.05 mg/L.
  MetricType.freeAmmonia: MetricBands(
    warningHigh: 0.02,
    criticalHigh: 0.05,
    displayMin: 0,
    displayMax: 0.1,
  ),
};

/// Worst status across the pond's [MetricType.water] readings in
/// [readings], and the weather risks to them (see [weatherInsights], e.g.
/// borderline oxygen on a muggy evening) — used for pond-level at-a-glance
/// health (list screen chip, dashboard summary banner). Ammonia counts as
/// free ammonia; humidity, air temperature and total ammonia only count
/// through those weather risks.
ReadingStatus overallStatus(Map<MetricType, SensorReading> readings) {
  var worst = worstSeverity(weatherInsights(readings));
  for (final entry in readings.entries) {
    if (!MetricType.water.contains(entry.key)) continue;
    final status = metricBands[entry.key]!.statusFor(entry.value.value);
    if (status.index > worst.index) worst = status;
  }
  return worst;
}
