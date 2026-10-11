import 'dart:math' as math;

import 'metric_type.dart';

/// Molar masses: the sensor reports ammonia as nitrogen (TAN, NH3-N); free
/// ammonia is given as NH3, like the firmware's `FreeNH3`.
const double _nh3PerN = 17.031 / 14.007;

/// Free (un-ionised) ammonia in mg/L as NH3, from total ammonia nitrogen
/// [totalAmmonia] (mg/L), [ph] and water temperature [tempC] (°C). The
/// un-ionised fraction follows Emerson et al. (1975):
/// pKa = 0.09018 + 2729.92 / T(K), fraction = 1 / (10^(pKa − pH) + 1).
/// Matches the firmware's `FreeNH3` value.
double freeAmmonia({
  required double totalAmmonia,
  required double ph,
  required double tempC,
}) {
  final pKa = 0.09018 + 2729.92 / (tempC + 273.15);
  final fraction = 1 / (math.pow(10, pKa - ph) + 1);
  return totalAmmonia * fraction * _nh3PerN;
}

/// [values] (one reading's metrics) plus [MetricType.freeAmmonia] when it can
/// be worked out, i.e. ammonia, pH and water temperature were all read.
Map<MetricType, double> withFreeAmmonia(Map<MetricType, double> values) {
  final total = values[MetricType.ammonia];
  final ph = values[MetricType.ph];
  final temp = values[MetricType.temperature];
  if (total == null || ph == null || temp == null) return values;
  return {
    ...values,
    MetricType.freeAmmonia: freeAmmonia(
      totalAmmonia: total,
      ph: ph,
      tempC: temp,
    ),
  };
}
