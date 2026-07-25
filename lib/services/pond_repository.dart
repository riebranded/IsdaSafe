import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pond.dart';

/// Everything [PondProvider] needs from a backing store, factored out so it
/// can be unit tested against a plain in-memory fake instead of a real
/// Supabase client (which needs a live project and can't be driven through
/// its fluent query builder without one).
abstract class PondRepository {
  /// The currently signed-in user's id, or null if signed out.
  String? get currentUserId;

  /// Emits whenever the signed-in user changes, including to/from null.
  Stream<String?> get userIdChanges;

  Future<List<Pond>> fetchPonds(String uid);

  Future<Pond> insertPond({
    required String uid,
    required String name,
    required double latitude,
    required double longitude,
  });

  Future<void> updatePond(String id, Map<String, Object?> patch);

  Future<void> deletePond(String id);
}

/// Backs [PondRepository] with the `ponds` table (RLS-scoped to
/// `auth.uid()`, so [fetchPonds] only ever needs filtering by [uid] as a
/// belt-and-suspenders match, not as the actual security boundary).
class SupabasePondRepository implements PondRepository {
  SupabasePondRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<List<Pond>> fetchPonds(String uid) async {
    final rows = await _client.from('ponds').select().eq('user_id', uid).order('created_at');
    return (rows as List).map((row) => _pondFromRow(row as Map<String, dynamic>)).toList();
  }

  @override
  Future<Pond> insertPond({
    required String uid,
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final row = await _client
        .from('ponds')
        .insert({'user_id': uid, 'name': name, 'latitude': latitude, 'longitude': longitude})
        .select()
        .single();
    return _pondFromRow(row);
  }

  @override
  Future<void> updatePond(String id, Map<String, Object?> patch) {
    return _client.from('ponds').update(patch).eq('id', id);
  }

  @override
  Future<void> deletePond(String id) {
    return _client.from('ponds').delete().eq('id', id);
  }

  Pond _pondFromRow(Map<String, dynamic> row) => Pond(
        id: row['id'] as String,
        name: row['name'] as String,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        speciesNames: ((row['species_names'] as List?) ?? const []).cast<String>(),
      );
}
