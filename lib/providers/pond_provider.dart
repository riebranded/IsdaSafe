import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pond.dart';
import '../models/pond_verification.dart';
import '../services/pond_repository.dart';

/// Backed by [PondRepository] (Supabase's `ponds` table by default) rather
/// than an in-memory list. Constructed once at the app root — before
/// sign-in — so it can't eagerly load in its constructor; instead it listens
/// to [PondRepository.userIdChanges] and (re)loads whenever the signed-in
/// user changes, clearing out when signed out. Every mutation writes through
/// immediately (optimistic on the in-memory list, rolled back on failure) so
/// what's on screen never drifts from what's actually persisted.
class PondProvider extends ChangeNotifier {
  PondProvider({PondRepository? repository})
    : _repository = repository ?? SupabasePondRepository() {
    _userIdSub = _repository.userIdChanges.listen(_handleUserIdChange);
    final uid = _repository.currentUserId;
    if (uid != null) _load(uid);
  }

  final PondRepository _repository;
  StreamSubscription<String?>? _userIdSub;

  List<Pond> _ponds = [];
  bool _isLoading = false;
  String? _loadedForUid;

  /// Verified ponds only — what every screen (dashboard, map, analytics,
  /// side panel, alerts) shows. Ponds still being checked, rejected, or whose
  /// check failed are kept out until they're verified; see [pendingPonds] and
  /// [failedPonds] for the ones the dashboard banner reports on.
  List<Pond> get ponds => List.unmodifiable(_ponds.where((p) => p.isVerified));

  /// Ponds whose background verification hasn't finished yet.
  List<Pond> get pendingPonds => List.unmodifiable(
    _ponds.where((p) => p.verificationStatus == VerificationStatus.pending),
  );

  /// Ponds the satellite check couldn't confirm because buildings cover the
  /// pin: waiting for the owner's photos (see [submitEvidencePhotos]).
  List<Pond> get needsPhotosPonds => List.unmodifiable(
    _ponds.where((p) => p.verificationStatus == VerificationStatus.needsPhotos),
  );

  /// Ponds whose verification couldn't complete (technical problem) and can be
  /// retried. Rejected ponds aren't listed: the user is told why by
  /// notification and simply adds the pond again.
  List<Pond> get failedPonds => List.unmodifiable(
    _ponds.where((p) => p.verificationStatus == VerificationStatus.error),
  );

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
  Future<Pond?> addPond(
    String name, {
    required double latitude,
    required double longitude,
    PondVerification? verification,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final uid = _repository.currentUserId;
    if (uid == null) return null;

    try {
      final pond = await _repository.insertPond(
        uid: uid,
        name: trimmed,
        latitude: latitude,
        longitude: longitude,
        verification: verification,
      );
      _ponds = [..._ponds, pond];
      notifyListeners();
      // Verification runs on the server after this returns; if the request
      // can't be sent the pond just stays pending and can be retried.
      unawaited(_startVerification(pond, verification?.evidencePhotos ?? const []));
      return pond;
    } catch (e) {
      debugPrint('PondProvider: addPond error $e');
      return null;
    }
  }

  /// Kicks off verification of a just-added pond. If the owner added photos on
  /// the form they're uploaded first and sent along, so the server can compare
  /// them with the satellite image right away should buildings hide the pond;
  /// if that fails, plain verification still starts and asks for photos later.
  Future<void> _startVerification(Pond pond, List<PondPhoto> evidence) async {
    final uid = _repository.currentUserId;
    if (uid != null && evidence.length >= kMinEvidencePhotos) {
      try {
        final paths = await _repository.uploadEvidencePhotos(uid: uid, pondId: pond.id, photos: evidence);
        await _repository.requestVerification(pond.id, photoPaths: paths);
        return;
      } catch (e) {
        debugPrint('PondProvider: sending up-front photos failed, verifying without them: $e');
      }
    }
    await _requestVerification(pond);
  }

  Future<bool> _requestVerification(Pond pond) async {
    try {
      await _repository.requestVerification(pond.id);
      return true;
    } catch (e) {
      debugPrint('PondProvider: requestVerification error $e');
      return false;
    }
  }

  /// Re-runs verification for a pond stuck as pending or that errored.
  /// Returns whether the request was sent.
  Future<bool> retryVerification(String id) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final pond = _ponds[index];
    final ok = await _requestVerification(pond);
    if (ok) {
      pond.verificationStatus = VerificationStatus.pending;
      pond.verificationMessage = null;
      notifyListeners();
    }
    return ok;
  }

  /// Uploads the photos asked for by a `needs_photos` pond and restarts its
  /// verification, which compares them with the satellite image. Returns
  /// whether everything was sent.
  Future<bool> submitEvidencePhotos(String id, List<PondPhoto> photos) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    final uid = _repository.currentUserId;
    if (index == -1 || uid == null) return false;
    if (photos.length < kMinEvidencePhotos ||
        photos.length > kMaxEvidencePhotos) {
      return false;
    }

    try {
      final paths = await _repository.uploadEvidencePhotos(
        uid: uid,
        pondId: id,
        photos: photos,
      );
      await _repository.requestVerification(id, photoPaths: paths);
    } catch (e) {
      debugPrint('PondProvider: submitEvidencePhotos error $e');
      return false;
    }
    final pond = _ponds[index];
    pond.verificationStatus = VerificationStatus.pending;
    pond.verificationMessage = null;
    notifyListeners();
    return true;
  }

  /// Re-fetches ponds without the loading state — used when a verification
  /// result arrives so statuses update live.
  Future<void> refresh() async {
    final uid = _repository.currentUserId;
    if (uid == null) return;
    try {
      _ponds = await _repository.fetchPonds(uid);
      notifyListeners();
    } catch (e) {
      debugPrint('PondProvider: refresh error $e');
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
  Future<bool> setLocation(
    String id, {
    required double latitude,
    required double longitude,
  }) async {
    final index = _ponds.indexWhere((p) => p.id == id);
    if (index == -1) return false;

    final previousLat = _ponds[index].latitude;
    final previousLng = _ponds[index].longitude;
    _ponds[index].latitude = latitude;
    _ponds[index].longitude = longitude;
    notifyListeners();
    try {
      await _repository.updatePond(id, {
        'latitude': latitude,
        'longitude': longitude,
      });
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
