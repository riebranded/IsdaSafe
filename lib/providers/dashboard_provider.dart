import 'package:flutter/foundation.dart';

import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/species_match.dart';
import '../services/fish_species_catalog.dart';
import '../services/mock_sensor_service.dart';
import '../services/suggestion_engine.dart';

/// Holds the latest snapshot and fish-species suggestions for one pond.
///
/// Scoped to a single dashboard visit (constructed per-pond) rather than
/// kept globally, so switching ponds never leaks stale state.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({
    required this._pond,
    MockSensorService? sensorService,
    SuggestionEngine? suggestionEngine,
  })  : _sensorService = sensorService ?? MockSensorService(),
        _suggestionEngine = suggestionEngine ?? SuggestionEngine() {
    refresh();
  }

  final Pond _pond;
  final MockSensorService _sensorService;
  final SuggestionEngine _suggestionEngine;

  PondSnapshot? _snapshot;
  List<SpeciesMatchResult> _matches = const [];

  PondSnapshot? get snapshot => _snapshot;
  List<SpeciesMatchResult> get matches => _matches;

  void refresh() {
    final snapshot = _sensorService.generateSnapshot(_pond);
    _snapshot = snapshot;
    _matches = _suggestionEngine.evaluate(snapshot.readings, FishSpeciesCatalog.species);
    notifyListeners();
  }
}
