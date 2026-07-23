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
  });

  final String name;
  final String localName;
  final MetricRange tempRange;
  final MetricRange phRange;
  final MetricRange doRange;
  final MetricRange ammoniaRange;
}
