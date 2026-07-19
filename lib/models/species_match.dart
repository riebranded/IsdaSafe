import 'fish_species.dart';
import 'metric_type.dart';

enum MatchVerdict { suitable, marginal, unsuitable }

extension MatchVerdictInfo on MatchVerdict {
  String get label {
    switch (this) {
      case MatchVerdict.suitable:
        return 'Suitable';
      case MatchVerdict.marginal:
        return 'Marginal';
      case MatchVerdict.unsuitable:
        return 'Unsuitable';
    }
  }
}

class MetricVerdict {
  const MetricVerdict({
    required this.type,
    required this.inRange,
    required this.note,
  });

  final MetricType type;
  final bool inRange;
  final String note;
}

class SpeciesMatchResult {
  const SpeciesMatchResult({
    required this.species,
    required this.verdict,
    required this.details,
  });

  final FishSpecies species;
  final MatchVerdict verdict;
  final List<MetricVerdict> details;
}
