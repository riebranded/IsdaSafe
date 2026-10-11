import 'package:flutter/material.dart';
import '../l10n/tr.dart';

enum MetricType {
  temperature,
  humidity,
  ammonia,
  dissolvedOxygen,
  ph,

  /// Air temperature around the device (the firmware's `AirT`). Shown with
  /// [humidity]; not one of the pond's [primary] water metrics.
  airTemperature,

  /// Un-ionised (free) ammonia, NH3: the toxic part of [ammonia], worked out
  /// from it, pH and water temperature (see `free_ammonia.dart`). Shown with
  /// [ammonia]; not one of the [primary] metrics, but it's the ammonia that
  /// counts in [water].
  freeAmmonia;

  /// The pond's five main readings: the reading cards and trend charts. The
  /// others are shown alongside one of these (see
  /// [MetricTypeInfo.companions]).
  static const primary = [temperature, humidity, ammonia, dissolvedOxygen, ph];

  /// The water readings: these alone decide the pond's status and alerts.
  /// Ammonia counts as [freeAmmonia], the part that's toxic to fish, not the
  /// total [ammonia]. [humidity] and [airTemperature] describe the weather,
  /// which only matters through what it does to these (see
  /// `weather_context.dart`).
  static const water = [temperature, freeAmmonia, dissolvedOxygen, ph];
}

extension MetricTypeInfo on MetricType {
  String get label => switch (this) {
    MetricType.temperature => 'Water Temperature'.tr,
    MetricType.humidity => 'Humidity'.tr,
    MetricType.ammonia => 'Ammonia'.tr,
    MetricType.dissolvedOxygen => 'Dissolved Oxygen'.tr,
    MetricType.ph => 'pH Level'.tr,
    MetricType.airTemperature => 'Air Temperature'.tr,
    MetricType.freeAmmonia => 'Free Ammonia'.tr,
  };

  String get unit => switch (this) {
    MetricType.temperature || MetricType.airTemperature => '°C',
    MetricType.humidity => '%',
    MetricType.ammonia ||
    MetricType.dissolvedOxygen ||
    MetricType.freeAmmonia => 'mg/L',
    MetricType.ph => '',
  };

  IconData get icon => switch (this) {
    MetricType.temperature => Icons.thermostat,
    MetricType.humidity => Icons.water_drop,
    MetricType.ammonia => Icons.science,
    MetricType.dissolvedOxygen => Icons.bubble_chart,
    MetricType.ph => Icons.opacity,
    MetricType.airTemperature => Icons.air,
    MetricType.freeAmmonia => Icons.warning_amber_rounded,
  };

  /// What the reading is and why it matters to the fish, for the metric's
  /// detail view.
  String get description => switch (this) {
    MetricType.temperature =>
      'How warm the pond water is. Fish are cold-blooded, so it sets how fast they eat, grow and use oxygen. Warm water holds less oxygen and makes ammonia more toxic.'
          .tr,
    MetricType.humidity =>
      "How much moisture is in the air around the device. It doesn't affect the fish directly, so it never changes the pond's status on its own. IsdaSafe reads it with the air and water temperature to warn about weather that changes the water: muggy nights that lower oxygen, air that keeps the pond warm, dry heat that evaporates it, and rain that lowers the pH."
          .tr,
    MetricType.ammonia =>
      'Total ammonia nitrogen dissolved in the water, from fish waste and uneaten feed. It rises when the pond is overstocked or overfed and builds up when water isn\'t exchanged.'
          .tr,
    MetricType.dissolvedOxygen =>
      'How much oxygen is dissolved in the water for the fish to breathe. It drops at night, in hot weather and after overfeeding; low levels stress fish and can kill them.'
          .tr,
    MetricType.ph =>
      'How acidic or alkaline the water is. Most pond fish do best near neutral. pH swings during the day with algae, and a high pH makes ammonia far more toxic.'
          .tr,
    MetricType.airTemperature =>
      'How warm the air is around the device. It drives the water temperature: hot air warms the pond within hours.'
          .tr,
    MetricType.freeAmmonia =>
      'The toxic part of the ammonia (un-ionised NH3), calculated from the total ammonia, pH and water temperature. Even small amounts damage the gills; it rises sharply when the water is warm or the pH is high.'
          .tr,
  };

  /// Readings shown together with this one in its detail view.
  List<MetricType> get companions => switch (this) {
    MetricType.humidity => const [MetricType.airTemperature],
    MetricType.ammonia => const [MetricType.freeAmmonia],
    _ => const [],
  };

  /// Numeric-only rendering, e.g. "27.4" — no unit, for space-constrained UI
  /// like per-point chart labels. [format] is the full display form.
  String formatValue(double value) => value.toStringAsFixed(switch (this) {
    MetricType.freeAmmonia => 3,
    MetricType.ammonia => 2,
    _ => 1,
  });

  /// Formats [value] the way it should be displayed, e.g. "27.4°C" or "6.8".
  String format(double value) {
    final formatted = formatValue(value);
    return unit.isEmpty ? formatted : '$formatted$unit';
  }
}
