import '../models/feeding_recommendation.dart';
import '../models/species_recommendation.dart';

/// App-lifetime cache for AI species/feeding recommendations, keyed by pond
/// (and by species for feeding advisories).
///
/// [DashboardProvider] is recreated every time a pond's dashboard is opened
/// (it's built inside a `ChangeNotifierProvider` under a pushed route or a
/// swapped-in detail pane), so caching inside it alone only avoids repeat
/// server calls within a single visit. This cache is owned above that —
/// provided once at the app root — so a recommendation fetched on one visit
/// is still considered fresh if the same pond's dashboard is reopened within
/// [ttl].
class RecommendationCache {
  /// Shared app-lifetime instance. [DashboardProvider] defaults to this so
  /// every dashboard visit shares the same cache without screens needing to
  /// thread an instance through; pass a fresh [RecommendationCache] in tests
  /// that need isolation instead.
  static final RecommendationCache instance = RecommendationCache();

  static const Duration ttl = Duration(minutes: 15);

  final Map<String, _Entry<SpeciesRecommendation>> _species = {};
  final Map<String, Map<String, _Entry<FeedingRecommendation>>> _feeding = {};

  /// The cached species recommendation for [pondId], or null if there isn't
  /// one or it's older than [ttl].
  SpeciesRecommendation? species(String pondId) {
    final entry = _species[pondId];
    if (entry == null || _isStale(entry.fetchedAt)) return null;
    return entry.value;
  }

  void putSpecies(String pondId, SpeciesRecommendation value) {
    _species[pondId] = _Entry(value, DateTime.now());
  }

  void clearSpecies(String pondId) => _species.remove(pondId);

  /// The cached feeding/water-quality advisory for [pondId] + [species], or
  /// null if there isn't one or it's older than [ttl].
  FeedingRecommendation? feeding(String pondId, String species) {
    final entry = _feeding[pondId]?[species];
    if (entry == null || _isStale(entry.fetchedAt)) return null;
    return entry.value;
  }

  void putFeeding(String pondId, String species, FeedingRecommendation value) {
    (_feeding[pondId] ??= {})[species] = _Entry(value, DateTime.now());
  }

  /// Drops cached feeding entries for species no longer assigned to the pond.
  void pruneFeeding(String pondId, Iterable<String> keepSpecies) {
    _feeding[pondId]?.removeWhere((name, _) => !keepSpecies.contains(name));
  }

  bool isFeedingFresh(String pondId, String species) {
    final entry = _feeding[pondId]?[species];
    return entry != null && !_isStale(entry.fetchedAt);
  }

  bool _isStale(DateTime fetchedAt) => DateTime.now().difference(fetchedAt) >= ttl;
}

class _Entry<T> {
  _Entry(this.value, this.fetchedAt);
  final T value;
  final DateTime fetchedAt;
}
