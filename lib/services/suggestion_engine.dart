import '../models/fish_species.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/species_match.dart';

/// Rule-based matcher that suggests which fish species suit a pond's
/// current readings.
///
/// Only temperature, pH, dissolved oxygen and ammonia gate suitability.
/// Humidity is a real sensor reading (ambient/air humidity) but is not a
/// driver of aquatic fish suitability, so it is displayed on the dashboard
/// like any other metric but deliberately excluded here.
class SuggestionEngine {
  static const List<MetricType> _gatingMetrics = [
    MetricType.temperature,
    MetricType.ph,
    MetricType.dissolvedOxygen,
    MetricType.ammonia,
  ];

  List<SpeciesMatchResult> evaluate(
    Map<MetricType, SensorReading> readings,
    List<FishSpecies> catalog,
  ) {
    final results = catalog.map((species) => _evaluateSpecies(species, readings)).toList();

    results.sort((a, b) => a.verdict.index.compareTo(b.verdict.index));
    return results;
  }

  SpeciesMatchResult _evaluateSpecies(
    FishSpecies species,
    Map<MetricType, SensorReading> readings,
  ) {
    final details = _gatingMetrics.map((type) {
      final reading = readings[type]!;
      final range = _rangeFor(species, type);
      final inRange = range.contains(reading.value);
      final note = inRange
          ? '${type.label} ${type.format(reading.value)} is within '
              '${species.name}\'s optimal range (${range.label}${type.unit}).'
          : '${type.label} ${type.format(reading.value)} is outside '
              '${species.name}\'s optimal range (${range.label}${type.unit}).';

      return MetricVerdict(type: type, inRange: inRange, note: note);
    }).toList();

    final outOfRangeCount = details.where((d) => !d.inRange).length;
    final verdict = switch (outOfRangeCount) {
      0 => MatchVerdict.suitable,
      1 => MatchVerdict.marginal,
      _ => MatchVerdict.unsuitable,
    };

    return SpeciesMatchResult(species: species, verdict: verdict, details: details);
  }

  MetricRange _rangeFor(FishSpecies species, MetricType type) {
    switch (type) {
      case MetricType.temperature:
        return species.tempRange;
      case MetricType.ph:
        return species.phRange;
      case MetricType.dissolvedOxygen:
        return species.doRange;
      case MetricType.ammonia:
        return species.ammoniaRange;
      case MetricType.humidity:
        throw ArgumentError('Humidity is not a gating metric for fish suitability.');
    }
  }
}
