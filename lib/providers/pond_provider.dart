import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pond.dart';
import '../services/pond_repository.dart';

/// Backed by [PondRepository] (Supabase's `ponds` table by default) rather
/// than an in-memory list. Constructed once at the app root — before
/// sign-in — so it can't eagerly load in its constructor; instead it listens
/// to [PondRepository.userIdChanges] and (re)loads whenever the signed-in
/// user changes, clearing out when signed out. Every mutation writes through
/// immediately (optimistic on the in-memory list, rolled back on failure) so
/// what's on screen never drifts from what's actually persisted.
class PondProvider extends ChangeNotifier {
  PondProvider({PondRepository? repository}) : _repository = repository ?? SupabasePondRepository() {
    _userIdSub = _repository.userIdChanges.listen(_handleUserIdChange);
    final uid = _repository.currentUserId;
    if (uid != null) _load(uid);
  }

  final PondRepository _repository;
  StreamSubscription<String?>? _userIdSub;

  List<Pond> _ponds = [];
  bool _isLoading = false;
  String? _loadedForUid;

  List<Pond> get ponds => List.unmodifiable(_ponds);

  /// True while the initial fetch for the current user is in flight — lets
  /// screens distinguish "still loading" from "genuinely has zero ponds".
  bool get isLoading => _isLoading;

  void _handleUserIdChange(String? uid) {
    if (uid == null) {
      _loadedForUid = null;
      if (_ponds.isNotEmpty || _isLoading) {
        _ponds = [];
        _isLoading = false;
        notifyListeners();
      }
      return;
    }
    // Token refreshes/other events for the same user fire on this stream
    // too — only a genuine sign-in (or switch to a different account) needs
    // a re-fetch.
    if (uid == _loadedForUid) return;
    _load(uid);
  }

  Future<void> _load(String uid) async {
    _loadedForUid = uid;
    _isLoading = true;
    notifyListeners();
    try {
      _ponds = await _repository.fetchPonds(uid);
    } catch (e) {
      debugPrint('PondProvider: load error $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns the created pond (so callers can immediately follow up with
  /// [setSpecies]), or null if [name] was blank, nobody's signed in, or the
  /// insert failed.
  Future<Pond?> addPond(String name, {required double latitude, required double longitude}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final uid = _repository.currentUserId;
    if (uid == null) return null;

    try {
      final pond = await _repository.insertPond(uid: uid, name: trimmed, latitude: latitude, longitude: longitude);
      _ponds = [..._ponds, pond];
      notifyListeners();
      return pond;
    } catch (e) {
      debugPrint('PondProvider: addPond error $e');
      return null;
    }
  }

  /// Sets which fish/shrimp species [id] holds — see [Pond.speciesNames].
  /// Returns whether the write succeeded.
  Future<bool> setSpecies(String id, List<String> speciesNames) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final previous = _ponds[index].speciesNames;
    _ponds[index].speciesNames = List.of(speciesNames);
    notifyListeners();
    try {
      await _repository.updatePond(id, {'species_names': speciesNames});
      return true;
    } catch (e) {
      _ponds[index].speciesNames = previous;
      notifyListeners();
      debugPrint('PondProvider: setSpecies error $e');
      return false;
    }
  }

  /// Returns whether the write succeeded.
  Future<bool> renamePond(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final previous = _ponds[index].name;
    _ponds[index].name = trimmed;
    notifyListeners();
    try {
      await _repository.updatePond(id, {'name': trimmed});
      return true;
    } catch (e) {
      _ponds[index].name = previous;
      notifyListeners();
      debugPrint('PondProvider: renamePond error $e');
      return false;
    }
  }

  /// Returns whether the write succeeded.
  Future<bool> setLocation(String id, {required double latitude, required double longitude}) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final previousLat = _ponds[index].latitude;
    final previousLng = _ponds[index].longitude;
    _ponds[index].latitude = latitude;
    _ponds[index].longitude = longitude;
    notifyListeners();
    try {
      await _repository.updatePond(id, {'latitude': latitude, 'longitude': longitude});
      return true;
    } catch (e) {
      _ponds[index].latitude = previousLat;
      _ponds[index].longitude = previousLng;
      notifyListeners();
      debugPrint('PondProvider: setLocation error $e');
      return false;
    }
  }

  /// Returns whether the delete succeeded.
  Future<bool> removePond(String id) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final removed = _ponds[index];
    _ponds = [..._ponds]..removeAt(index);
    notifyListeners();
    try {
      await _repository.deletePond(id);
      return true;
    } catch (e) {
      _ponds = [..._ponds]..insert(index, removed);
      notifyListeners();
      debugPrint('PondProvider: removePond error $e');
      return false;
    }
  }

  @override
  void dispose() {
    _userIdSub?.cancel();
    super.dispose();
  }
}
