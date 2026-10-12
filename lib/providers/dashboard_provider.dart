import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/tr.dart';

import '../l10n/language_provider.dart';
import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/species_recommendation.dart';
import '../services/feeding_recommendation_service.dart';
import '../services/feeding_schedule_store.dart';
import '../services/recommendation_cache.dart';
import '../services/species_recommendation_service.dart';
import '../services/pond_snapshot_cache.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../services/usb_sensor/usb_sensor_hub.dart';

/// Holds the latest snapshot, AI species recommendation, and per-species
/// feeding/water-quality advisories for one pond.
///
/// Scoped to a single dashboard visit (constructed per-pond) rather than
/// kept globally, so switching ponds never leaks stale state.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({
    required this._pond,
    SpeciesRecommendationService? recommendationService,
    FeedingRecommendationService? feedingService,
    FeedingScheduleStore? scheduleStore,
    RecommendationCache? cache,
  }) : _recommendationService =
           recommendationService ?? HttpSpeciesRecommendationService(),
       _feedingService =
           feedingService ?? SupabaseFeedingRecommendationService(),
       _scheduleStore = scheduleStore ?? SupabaseFeedingScheduleStore(),
       _cache = cache ?? RecommendationCache.instance {
    // Show whatever's still fresh from a previous visit to this pond's
    // dashboard immediately, before refresh() decides whether it needs to
    // hit the server at all.
    _recommendation = _cache.species(_pond.id);
    for (final name in _pond.speciesNames) {
      final cached = _cache.feeding(_pond.id, name);
      if (cached != null) _feedingRecommendations[name] = cached;
    }
    LanguageProvider.revision.addListener(_onLanguageChanged);
    UsbSensorHub.instance.addListener(_onReadingsChanged);
    PondReadingsStore.instance.addListener(_onReadingsChanged);
    refresh();
  }

  final Pond _pond;
  final SpeciesRecommendationService _recommendationService;
  final FeedingRecommendationService _feedingService;
  final FeedingScheduleStore _scheduleStore;
  final RecommendationCache _cache;

  PondSnapshot? _snapshot;
  SpeciesRecommendation? _recommendation;
  bool _recommendationLoading = false;
  String? _recommendationError;

  final Map<String, FeedingRecommendation> _feedingRecommendations = {};
  bool _feedingLoading = false;
  String? _feedingError;

  /// Null until the pond has readings: see [dataState] for why.
  PondSnapshot? get snapshot => _snapshot;

  /// Whether this pond has a paired device and readings yet.
  PondDataState get dataState {
    final state = PondReadingsStore.instance.stateFor(_pond.id);
    // Live USB readings count even before the first upload lands.
    if (state == PondDataState.waiting && _snapshot != null) {
      return PondDataState.ready;
    }
    return state;
  }

  SpeciesRecommendation? get recommendation => _recommendation;
  bool get recommendationLoading => _recommendationLoading;
  String? get recommendationError => _recommendationError;

  /// Feeding/water-quality advisory per species name in [Pond.speciesNames].
  Map<String, FeedingRecommendation> get feedingRecommendations =>
      _feedingRecommendations;
  bool get feedingLoading => _feedingLoading;
  String? get feedingError => _feedingError;

  /// Water-quality recommendations across every assigned species, deduped
  /// (species share one pond, so the same reading-driven advice often
  /// repeats across each species' call).
  List<String> get waterQualityRecommendations => _feedingRecommendations.values
      .expand((r) => r.waterQualityRecommendations)
      .toSet()
      .toList();

  /// Possible risks across every assigned species, deduped like
  /// [waterQualityRecommendations].
  List<String> get possibleRisks => _feedingRecommendations.values
      .expand((r) => r.possibleRisks)
      .toSet()
      .toList();

  /// The advice text is in the old language — drop it and ask again.
  void _onLanguageChanged() {
    _feedingRecommendations.clear();
    for (final name in _pond.speciesNames) {
      final cached = _cache.feeding(_pond.id, name);
      if (cached != null) _feedingRecommendations[name] = cached;
    }
    notifyListeners();
    retryFeedingRecommendations();
  }

  /// New readings (a USB reading, an upload, or the device being paired or
  /// removed): show them straight away. The AI advice is only re-requested
  /// once the pond first has every reading it needs, not every ~25 s.
  void _onReadingsChanged() {
    final hadAdviceReadings = _canAdvise(_snapshot);
    _snapshot = PondSnapshotCache.compose(_pond);
    notifyListeners();
    final snapshot = _snapshot;
    if (!hadAdviceReadings && snapshot != null) _fetchAdvice(snapshot);
  }

  static bool _canAdvise(PondSnapshot? snapshot) =>
      snapshot != null && snapshot.missingForAdvice.isEmpty;

  @override
  void dispose() {
    LanguageProvider.revision.removeListener(_onLanguageChanged);
    UsbSensorHub.instance.removeListener(_onReadingsChanged);
    PondReadingsStore.instance.removeListener(_onReadingsChanged);
    super.dispose();
  }

  void refresh() {
    final snapshot = _snapshot = PondSnapshotCache.compose(_pond);
    notifyListeners();
    unawaited(PondReadingsStore.instance.refresh());
    // No readings, no advice: there's nothing to base it on yet.
    if (snapshot != null) _fetchAdvice(snapshot);
  }

  void _fetchAdvice(PondSnapshot snapshot) {
    if (!_waitForAdviceReadings(snapshot)) return;
    unawaited(_fetchRecommendation(snapshot));
    unawaited(_fetchFeedingRecommendations(snapshot));
  }

  /// The AI needs every one of [PondSnapshot.adviceMetrics]; with some still
  /// missing (e.g. the pH/ammonia probe isn't sending), says which instead of
  /// asking it with made-up values. Returns whether advice can be fetched.
  bool _waitForAdviceReadings(PondSnapshot snapshot) {
    final missing = snapshot.missingForAdvice;
    if (missing.isEmpty) return true;
    final message = 'Waiting for these readings from the device: {0}'.trf([
      missing.map((t) => t.label).join(', '),
    ]);
    _recommendation = null;
    _recommendationLoading = false;
    _recommendationError = message;
    _feedingRecommendations.clear();
    _feedingLoading = false;
    _feedingError = message;
    notifyListeners();
    return false;
  }

  /// Re-requests a species recommendation for the current snapshot — used
  /// by the recommendation card's own retry action so a failed/slow
  /// prediction call can be retried on its own.
  void retryRecommendation() {
    final snapshot = _snapshot;
    if (snapshot == null || !_waitForAdviceReadings(snapshot)) return;
    unawaited(_fetchRecommendation(snapshot));
  }

  /// The pond's species or their biomass just changed: the cached advice was
  /// made for the old ones, so drop it and ask again.
  void onSpeciesChanged() {
    _cache.clearFeeding(_pond.id);
    _feedingRecommendations.clear();
    notifyListeners();
    retryFeedingRecommendations();
  }

  /// Re-requests feeding/water-quality advisories for the current snapshot —
  /// used both by the
  /// feeding/advisory sections' own retry actions and after the pond's
  /// species selection changes.
  void retryFeedingRecommendations() {
    final snapshot = _snapshot;
    if (snapshot == null || !_waitForAdviceReadings(snapshot)) return;
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
      _recommendation = await _recommendationService.recommend(
        snapshot.readings,
      );
      _cache.putSpecies(_pond.id, _recommendation!);
    } catch (e) {
      _recommendation = null;
      _cache.clearSpecies(_pond.id);
      _recommendationError = e.toString().replaceFirst('Exception: ', '').tr;
    } finally {
      _recommendationLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchFeedingRecommendations(PondSnapshot snapshot) async {
    final speciesNames = _pond.speciesNames;

    // Drop cached data for species no longer assigned to the pond.
    _feedingRecommendations.removeWhere(
      (name, _) => !speciesNames.contains(name),
    );
    _cache.pruneFeeding(_pond.id, speciesNames);

    if (speciesNames.isEmpty) {
      _feedingError = null;
      _feedingLoading = false;
      notifyListeners();
      return;
    }

    // Only re-ask the model for species that are missing or whose cached
    // feeding schedule/water-quality advisory/risks have gone stale.
    final namesToFetch = speciesNames
        .where((name) => !_cache.isFeedingFresh(_pond.id, name))
        .toList();

    if (namesToFetch.isEmpty) {
      _feedingError = null;
      notifyListeners();
      return;
    }

    _feedingLoading = true;
    _feedingError = null;
    notifyListeners();

    String? error;
    // The feeding schedule is saved on the pond and regenerated once a day;
    // the water-quality advice and risks every 15 minutes. Reuse whichever is
    // still valid and only ask the model (with the current sensor readings)
    // when something has expired.
    final saved = await _scheduleStore.load(_pond.id);
    var changed = false;
    for (final name in namesToFetch) {
      try {
        final biomassKg = _pond.speciesBiomassKg[name];
        final schedule = saved.scheduleFor(name, biomassKg: biomassKg);
        final advice = saved.adviceFor(name);
        FeedingRecommendation recommendation;
        if (schedule != null && advice != null) {
          recommendation = FeedingRecommendation(
            species: name,
            feedingTime: schedule.time,
            feedingFrequency: schedule.frequency,
            feedingAmount: schedule.amount,
            waterQualityRecommendations: advice.recommendations,
            possibleRisks: advice.risks,
          );
        } else {
          final fresh = await _feedingService.recommend(
            species: name,
            readings: snapshot.readings,
            biomassKg: biomassKg,
          );
          // Keep today's schedule if there is one: only the advice expired.
          recommendation = schedule == null
              ? fresh
              : FeedingRecommendation(
                  species: name,
                  feedingTime: schedule.time,
                  feedingFrequency: schedule.frequency,
                  feedingAmount: schedule.amount,
                  waterQualityRecommendations:
                      fresh.waterQualityRecommendations,
                  possibleRisks: fresh.possibleRisks,
                );
          saved.put(
            name,
            fresh,
            snapshot.readings,
            replaceSchedule: schedule == null,
            biomassKg: biomassKg,
          );
          changed = true;
        }
        _feedingRecommendations[name] = recommendation;
        _cache.putFeeding(_pond.id, name, recommendation);
      } catch (e) {
        error = e.toString().replaceFirst('Exception: ', '').tr;
      }
    }
    if (changed) unawaited(_scheduleStore.save(_pond.id, saved));

    // Only surface the error banner if nothing came back at all — a partial
    // result (some species failed, others didn't, or came from cache) still
    // has useful content.
    _feedingError = _feedingRecommendations.isEmpty ? error : null;
    _feedingLoading = false;
    notifyListeners();
  }
}
