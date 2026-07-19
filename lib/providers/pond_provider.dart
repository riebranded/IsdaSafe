import 'package:flutter/foundation.dart';

import '../models/pond.dart';

class PondProvider extends ChangeNotifier {
  PondProvider()
      : _ponds = [
          // Seeded with real coordinates in well-known Philippine
          // aquaculture regions, so every pond in the app has a location
          // from first launch.
          Pond(id: 'pond-a', name: 'Pond A', latitude: 14.3500, longitude: 121.2500), // Laguna de Bay
          Pond(id: 'pond-b', name: 'Pond B', latitude: 14.8100, longitude: 120.7500), // Hagonoy, Bulacan
          Pond(id: 'pond-c', name: 'Pond C', latitude: 14.9500, longitude: 120.7000), // Macabebe, Pampanga
        ];

  final List<Pond> _ponds;
  int _nextId = 0;

  List<Pond> get ponds => List.unmodifiable(_ponds);

  void addPond(String name, {required double latitude, required double longitude}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    _ponds.add(Pond(id: 'pond-new-${_nextId++}', name: trimmed, latitude: latitude, longitude: longitude));
    notifyListeners();
  }

  void renamePond(String id, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final pond = _ponds.firstWhere((p) => p.id == id);
    pond.name = trimmed;
    notifyListeners();
  }

  void setLocation(String id, {required double latitude, required double longitude}) {
    final pond = _ponds.firstWhere((p) => p.id == id);
    pond.latitude = latitude;
    pond.longitude = longitude;
    notifyListeners();
  }

  void removePond(String id) {
    _ponds.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
