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
