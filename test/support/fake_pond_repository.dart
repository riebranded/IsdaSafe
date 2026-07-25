import 'dart:async';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/pond_repository.dart';

/// In-memory [PondRepository] fake — lets [PondProvider] be exercised in
/// tests without a live Supabase project. Seeded with the same 3 mock ponds
/// (`pond-a`/`pond-b`/`pond-c`) [PondProvider] itself used to seed directly,
/// so existing widget tests that reference those ids keep working unchanged.
class FakePondRepository implements PondRepository {
  FakePondRepository({List<Pond>? seed, String? userId = 'test-user'})
      : _ponds = seed ?? defaultSeed(),
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
  }) async {
    _maybeFail();
    final pond = Pond(id: 'fake-${_nextId++}', name: name, latitude: latitude, longitude: longitude);
    _ponds.add(pond);
    return pond;
  }

  @override
  Future<void> updatePond(String id, Map<String, Object?> patch) async {
    _maybeFail();
  }

  @override
  Future<void> deletePond(String id) async {
    _maybeFail();
    _ponds.removeWhere((p) => p.id == id);
  }

  Future<void> dispose() => _userIdController.close();
}
