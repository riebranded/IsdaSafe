import 'dart:async';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/pond_verification.dart';
import 'package:isdasafev2/services/pond_repository.dart';

/// In-memory [PondRepository] fake — lets [PondProvider] be exercised in
/// tests without a live Supabase project. Seeded with the same 3 mock ponds
/// (`pond-a`/`pond-b`/`pond-c`) [PondProvider] itself used to seed directly,
/// so existing widget tests that reference those ids keep working unchanged.
class FakePondRepository implements PondRepository {
  FakePondRepository({List<Pond>? seed, String? userId = 'test-user'})
    : _ponds = seed ?? defaultSeed(),
      // ignore: prefer_initializing_formals
      _userId = userId;

  static List<Pond> defaultSeed() => [
    Pond(id: 'pond-a', name: 'Pond A', latitude: 14.3500, longitude: 121.2500),
    Pond(id: 'pond-b', name: 'Pond B', latitude: 14.8100, longitude: 120.7500),
    Pond(id: 'pond-c', name: 'Pond C', latitude: 14.9500, longitude: 120.7000),
  ];

  final List<Pond> _ponds;
  String? _userId;
  var _nextId = 0;

  /// Set true to make the next write (insert/update/delete) throw, to
  /// exercise [PondProvider]'s rollback-on-failure paths. Resets itself
  /// after firing once.
  bool failNextWrite = false;

  final _userIdController = StreamController<String?>.broadcast();

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> get userIdChanges => _userIdController.stream;

  /// Simulates a sign-in/sign-out/account-switch.
  void setUserId(String? uid) {
    _userId = uid;
    _userIdController.add(uid);
  }

  void _maybeFail() {
    if (!failNextWrite) return;
    failNextWrite = false;
    throw Exception('fake repository failure');
  }

  @override
  Future<List<Pond>> fetchPonds(String uid) async => List.of(_ponds);

  @override
  Future<Pond> insertPond({
    required String uid,
    required String name,
    required double latitude,
    required double longitude,
    PondVerification? verification,
  }) async {
    _maybeFail();
    final pond = Pond(
      id: 'fake-${_nextId++}',
      name: name,
      latitude: latitude,
      longitude: longitude,
      verificationMethod: verification?.method,
      verificationStatus: VerificationStatus.pending,
    );
    _ponds.add(pond);
    return pond;
  }

  @override
  Future<void> updatePond(String id, Map<String, Object?> patch) async {
    _maybeFail();
  }

  /// Ids passed to [requestVerification], in order.
  final verificationRequests = <String>[];

  /// Set true to make the next [requestVerification] throw.
  bool failNextVerificationRequest = false;

  /// Photo paths passed to [requestVerification], by pond id.
  final evidenceRequests = <String, List<String>>{};

  /// Set true to make the next [uploadEvidencePhotos] throw.
  bool failNextEvidenceUpload = false;

  @override
  Future<List<String>> uploadEvidencePhotos({
    required String uid,
    required String pondId,
    required List<PondPhoto> photos,
  }) async {
    if (failNextEvidenceUpload) {
      failNextEvidenceUpload = false;
      throw Exception('fake upload failure');
    }
    return [
      for (final (i, _) in photos.indexed) '$uid/$pondId/evidence-$i.jpg',
    ];
  }

  @override
  Future<void> requestVerification(
    String pondId, {
    List<String>? photoPaths,
  }) async {
    if (photoPaths != null) {
      evidenceRequests[pondId] = photoPaths;
      return;
    }
    if (failNextVerificationRequest) {
      failNextVerificationRequest = false;
      throw Exception('fake verification request failure');
    }
    verificationRequests.add(pondId);
  }

  @override
  Future<void> deletePond(String id) async {
    _maybeFail();
    _ponds.removeWhere((p) => p.id == id);
  }

  Future<void> dispose() => _userIdController.close();
}
