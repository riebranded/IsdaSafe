import '../l10n/tr.dart';
import 'metric_type.dart';
import 'reading_bands.dart';

/// What to do about [value] of [type] when it's outside the healthy band, or
/// null when it's fine. Short, practical steps a farmer can act on now.
String? guidanceFor(MetricType type, double value) {
  final bands = metricBands[type]!;
  final low = bands.warningLow != null && value < bands.warningLow!;
  final high = bands.warningHigh != null && value > bands.warningHigh!;
  if (!low && !high) return null;

  return switch ((type, high)) {
    (MetricType.temperature, true) =>
      'The water is too warm. Shade the pond or add cooler water, run aeration (warm water holds less oxygen), and feed less until it cools down.'
          .tr,
    (MetricType.temperature, false) =>
      'The water is too cold, so fish eat and grow slowly. Feed less, and avoid large water changes with cold water.'
          .tr,
    // Humidity has no limits of its own; its advice comes from
    // `weatherInsights`, together with the water readings.
    (MetricType.humidity, _) => null,
    (MetricType.ammonia, _) =>
      'Ammonia is building up. Stop or cut back feeding, change part of the water, and remove uneaten feed and dead fish.'
          .tr,
    (MetricType.dissolvedOxygen, _) =>
      'Oxygen is low. Turn on aerators or add fresh water now, stop feeding until it recovers, and check again at dawn, when it is lowest.'
          .tr,
    (MetricType.ph, false) =>
      'The water is too acidic. Apply agricultural lime and check the pH again after a few hours.'
          .tr,
    (MetricType.ph, true) =>
      'The water is too alkaline, which makes ammonia more toxic. Change part of the water and don\'t add lime.'
          .tr,
    (MetricType.airTemperature, true) =>
      'Hot air will warm the pond. Shade it and keep an eye on the water temperature and oxygen.'
          .tr,
    (MetricType.airTemperature, false) =>
      'Cool air will chill the pond. Feed less until it warms up.'.tr,
    (MetricType.freeAmmonia, _) =>
      'Toxic ammonia is high. Stop feeding, change part of the water and aerate. Bringing the pH and water temperature down also lowers it.'
          .tr,
  };
}
