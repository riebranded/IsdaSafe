import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/species_recommendation.dart';
import '../services/mock_sensor_service.dart';
import '../services/species_recommendation_service.dart';

/// Holds the latest snapshot and AI species recommendation for one pond.
///
/// Scoped to a single dashboard visit (constructed per-pond) rather than
/// kept globally, so switching ponds never leaks stale state.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({
    required this._pond,
    MockSensorService? sensorService,
    SpeciesRecommendationService? recommendationService,
  })  : _sensorService = sensorService ?? MockSensorService(),
        _recommendationService = recommendationService ?? HttpSpeciesRecommendationService() {
    refresh();
  }

  final Pond _pond;
  final MockSensorService _sensorService;
  final SpeciesRecommendationService _recommendationService;

  PondSnapshot? _snapshot;
  SpeciesRecommendation? _recommendation;
  bool _recommendationLoading = false;
  String? _recommendationError;

  PondSnapshot? get snapshot => _snapshot;
  SpeciesRecommendation? get recommendation => _recommendation;
  bool get recommendationLoading => _recommendationLoading;
  String? get recommendationError => _recommendationError;

  void refresh() {
    final snapshot = _sensorService.generateSnapshot(_pond);
    _snapshot = snapshot;
    notifyListeners();

    unawaited(_fetchRecommendation(snapshot));
  }

  /// Re-requests a recommendation for the current snapshot without re-rolling
  /// the mock sensor readings — used by the recommendation card's own retry
  /// action so a failed/slow prediction call can be retried on its own.
  void retryRecommendation() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    unawaited(_fetchRecommendation(snapshot));
  }

  Future<void> _fetchRecommendation(PondSnapshot snapshot) async {
    _recommendationLoading = true;
    _recommendationError = null;
    notifyListeners();

    try {
      _recommendation = await _recommendationService.recommend(snapshot.readings);
    } catch (e) {
      _recommendation = null;
      _recommendationError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _recommendationLoading = false;
      notifyListeners();
    }
  }
}
