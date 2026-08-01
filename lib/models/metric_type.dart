import 'package:flutter/material.dart';

enum MetricType { temperature, humidity, ammonia, dissolvedOxygen, ph }

extension MetricTypeInfo on MetricType {
  String get label {
    switch (this) {
      case MetricType.temperature:
        return 'Water Temperature';
      case MetricType.humidity:
        return 'Humidity';
      case MetricType.ammonia:
        return 'Ammonia';
      case MetricType.dissolvedOxygen:
        return 'Dissolved Oxygen';
      case MetricType.ph:
        return 'pH Level';
    }
  }

  String get unit {
    switch (this) {
      case MetricType.temperature:
        return '°C';
      case MetricType.humidity:
        return '%';
      case MetricType.ammonia:
        return 'mg/L';
      case MetricType.dissolvedOxygen:
        return 'mg/L';
      case MetricType.ph:
        return '';
    }
  }

  IconData get icon {
    switch (this) {
      case MetricType.temperature:
        return Icons.thermostat;
      case MetricType.humidity:
        return Icons.water_drop;
      case MetricType.ammonia:
        return Icons.science;
      case MetricType.dissolvedOxygen:
        return Icons.bubble_chart;
      case MetricType.ph:
        return Icons.opacity;
    }
  }

  /// Numeric-only rendering, e.g. "27.4" — no unit, for space-constrained UI
  /// like per-point chart labels. [format] is the full display form.
  String formatValue(double value) =>
      value.toStringAsFixed(this == MetricType.ammonia ? 2 : 1);

  /// Formats [value] the way it should be displayed, e.g. "27.4°C" or "6.8".
  String format(double value) {
    final formatted = formatValue(value);
    return unit.isEmpty ? formatted : '$formatted$unit';
  }
}
