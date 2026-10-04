import 'metric_type.dart';
import 'sensor_reading.dart';

class MetricRange {
  const MetricRange(this.min, this.max);

  final double min;
  final double max;

  bool contains(double value) => value >= min && value <= max;

  String get label => '$min–$max';
}

/// A mock fish species with the water-quality ranges it needs to thrives.
class FishSpecies {
  const FishSpecies({
    required this.name,
    required this.localName,
    required this.tempRange,
    required this.phRange,
    required this.doRange,
    required this.ammoniaRange,
    required this.feedingTimes,
    this.assignableToPond = true,
  });

  final String name;
  final String localName;
  final MetricRange tempRange;
  final MetricRange phRange;
  final MetricRange doRange;
  final MetricRange ammoniaRange;

  /// Suggested times of day to feed this species, e.g. `['6:00 AM', '5:00 PM']`.
  final List<String> feedingTimes;

  /// Whether this species is offered in [showSelectSpeciesDialog]'s
  /// checklist. Still fully present in [FishSpeciesCatalog.species] so its
  /// local name can be shown alongside the AI species recommendation either
  /// way — this only controls what a user can pick as "what my pond holds".
  final bool assignableToPond;
}

/// How well a pond's current water suits one species.
enum Suitability {
  suitable('Suitable'),
  partial('Partly suitable'),
  unsuitable('Not suitable');

  const Suitability(this.label);
  final String label;
}

/// A species' [Suitability] for a set of readings, plus which readings fall
/// outside its range (e.g. "Ammonia too high") so the verdict can be explained.
class SpeciesFit {
  const SpeciesFit(this.level, this.issues);

  final Suitability level;
  final List<String> issues;
}

extension SpeciesSuitability on FishSpecies {
  /// Compares each reading with this species' range: all inside is
  /// suitable, one outside is partly suitable, more is not suitable.
  SpeciesFit fitFor(Map<MetricType, SensorReading> readings) {
    final ranges = {
      MetricType.temperature: tempRange,
      MetricType.ph: phRange,
      MetricType.dissolvedOxygen: doRange,
      MetricType.ammonia: ammoniaRange,
    };
    final issues = <String>[];
    for (final entry in ranges.entries) {
      final reading = readings[entry.key];
      if (reading == null || entry.value.contains(reading.value)) continue;
      final tooLow = reading.value < entry.value.min;
      issues.add('${entry.key.label} too ${tooLow ? 'low' : 'high'}');
    }
    final level = issues.isEmpty
        ? Suitability.suitable
        : issues.length == 1
        ? Suitability.partial
        : Suitability.unsuitable;
    return SpeciesFit(level, issues);
  }
}
