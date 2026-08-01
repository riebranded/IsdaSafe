import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/feeding_recommendation.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/species_recommendation.dart';
import '../services/feeding_recommendation_service.dart';
import '../services/mock_sensor_service.dart';
import '../services/recommendation_cache.dart';
import '../services/species_recommendation_service.dart';

/// Holds the latest snapshot, AI species recommendation, and per-species
/// feeding/water-quality advisories for one pond.
///
/// Scoped to a single dashboard visit (constructed per-pond) rather than
/// kept globally, so switching ponds never leaks stale state.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({
    required this._pond,
    MockSensorService? sensorService,
    SpeciesRecommendationService? recommendationService,
    FeedingRecommendationService? feedingService,
    RecommendationCache? cache,
  })  : _sensorService = sensorService ?? MockSensorService(),
        _recommendationService = recommendationService ?? HttpSpeciesRecommendationService(),
        _feedingService = feedingService ?? HttpFeedingRecommendationService(),
        _cache = cache ?? RecommendationCache.instance {
    // Show whatever's still fresh from a previous visit to this pond's
    // dashboard immediately, before refresh() decides whether it needs to
    // hit the server at all.
    _recommendation = _cache.species(_pond.id);
    for (final name in _pond.speciesNames) {
      final cached = _cache.feeding(_pond.id, name);
      if (cached != null) _feedingRecommendations[name] = cached;
    }
    refresh();
  }

  final Pond _pond;
  final MockSensorService _sensorService;
  final SpeciesRecommendationService _recommendationService;
  final FeedingRecommendationService _feedingService;
  final RecommendationCache _cache;

  PondSnapshot? _snapshot;
  SpeciesRecommendation? _recommendation;
  bool _recommendationLoading = false;
  String? _recommendationError;

  final Map<String, FeedingRecommendation> _feedingRecommendations = {};
  bool _feedingLoading = false;
  String? _feedingError;

  PondSnapshot? get snapshot => _snapshot;
  SpeciesRecommendation? get recommendation => _recommendation;
  bool get recommendationLoading => _recommendationLoading;
  String? get recommendationError => _recommendationError;

  /// Feeding/water-quality advisory per species name in [Pond.speciesNames].
  Map<String, FeedingRecommendation> get feedingRecommendations => _feedingRecommendations;
  bool get feedingLoading => _feedingLoading;
  String? get feedingError => _feedingError;

  /// Water-quality recommendations across every assigned species, deduped
  /// (species share one pond, so the same reading-driven advice often
  /// repeats across each species' call).
  List<String> get waterQualityRecommendations =>
      _feedingRecommendations.values.expand((r) => r.waterQualityRecommendations).toSet().toList();

  /// Possible risks across every assigned species, deduped like
  /// [waterQualityRecommendations].
  List<String> get possibleRisks =>
      _feedingRecommendations.values.expand((r) => r.possibleRisks).toSet().toList();

  void refresh() {
    final snapshot = _sensorService.generateSnapshot(_pond);
    _snapshot = snapshot;
    notifyListeners();

    unawaited(_fetchRecommendation(snapshot));
    unawaited(_fetchFeedingRecommendations(snapshot));
  }

  /// Re-requests a species recommendation for the current snapshot without
  /// re-rolling the mock sensor readings — used by the recommendation
  /// card's own retry action so a failed/slow prediction call can be
  /// retried on its own.
  void retryRecommendation() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    unawaited(_fetchRecommendation(snapshot));
  }

  /// Re-requests feeding/water-quality advisories for the current snapshot
  /// without re-rolling the mock sensor readings — used both by the
  /// feeding/advisory sections' own retry actions and after the pond's
  /// species selection changes.
  void retryFeedingRecommendations() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    unawaited(_fetchFeedingRecommendations(snapshot));
  }

  Future<void> _fetchRecommendation(PondSnapshot snapshot) async {
    final cached = _cache.species(_pond.id);
    if (cached != null) {
      // Still within the cache window — keep showing the cached
      // recommendation instead of asking the model again.
      _recommendation = cached;
      return;
    }

    _recommendationLoading = true;
    _recommendationError = null;
    notifyListeners();

    try {
      _recommendation = await _recommendationService.recommend(snapshot.readings);
      _cache.putSpecies(_pond.id, _recommendation!);
    } catch (e) {
      _recommendation = null;
      _cache.clearSpecies(_pond.id);
      _recommendationError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _recommendationLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchFeedingRecommendations(PondSnapshot snapshot) async {
    final speciesNames = _pond.speciesNames;

    // Drop cached data for species no longer assigned to the pond.
    _feedingRecommendations.removeWhere((name, _) => !speciesNames.contains(name));
    _cache.pruneFeeding(_pond.id, speciesNames);

    if (speciesNames.isEmpty) {
      _feedingError = null;
      _feedingLoading = false;
      notifyListeners();
      return;
    }

    // Only re-ask the model for species that are missing or whose cached
    // feeding schedule/water-quality advisory/risks have gone stale.
    final namesToFetch = speciesNames.where((name) => !_cache.isFeedingFresh(_pond.id, name)).toList();

    if (namesToFetch.isEmpty) {
      _feedingError = null;
      notifyListeners();
      return;
    }

    _feedingLoading = true;
    _feedingError = null;
    notifyListeners();

    String? error;
    for (final name in namesToFetch) {
      try {
        final recommendation = await _feedingService.recommend(species: name, readings: snapshot.readings);
        _feedingRecommendations[name] = recommendation;
        _cache.putFeeding(_pond.id, name, recommendation);
      } catch (e) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
    }

    // Only surface the error banner if nothing came back at all — a partial
    // result (some species failed, others didn't, or came from cache) still
    // has useful content.
    _feedingError = _feedingRecommendations.isEmpty ? error : null;
    _feedingLoading = false;
    notifyListeners();
  }
}
