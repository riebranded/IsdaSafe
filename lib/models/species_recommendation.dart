/// A fish species recommendation returned by the Render-hosted prediction
/// API for a pond's current sensor readings.
class SpeciesRecommendation {
  const SpeciesRecommendation({required this.species, this.confidence});

  final String species;

  /// Model confidence in [0, 1], if the backing model exposes probabilities.
  final double? confidence;
}
