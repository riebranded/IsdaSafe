/// AI-generated feeding plan and water-quality advisory for one species
/// under a pond's current readings, from the Render-hosted
/// `/feeding-recommendation` endpoint (Gemini-backed).
class FeedingRecommendation {
  const FeedingRecommendation({
    required this.species,
    required this.feedingTime,
    required this.feedingFrequency,
    required this.feedingAmount,
    required this.waterQualityRecommendations,
    required this.possibleRisks,
  });

  final String species;
  final String feedingTime;
  final String feedingFrequency;
  final String feedingAmount;
  final List<String> waterQualityRecommendations;
  final List<String> possibleRisks;
}
