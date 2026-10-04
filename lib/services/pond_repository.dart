import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pond.dart';
import '../models/pond_verification.dart';

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
    PondVerification? verification,
  });

  Future<void> updatePond(String id, Map<String, Object?> patch);

  /// Asks the server to (re)start verifying [pondId] in the background. The
  /// result arrives later as a pond status change plus a notification.
  Future<void> requestVerification(String pondId, {List<String>? photoPaths});

  /// Uploads the photos requested for a `needs_photos` pond and returns their
  /// storage paths, to pass to [requestVerification].
  Future<List<String>> uploadEvidencePhotos({
    required String uid,
    required String pondId,
    required List<PondPhoto> photos,
  });

  Future<void> deletePond(String id);
}

/// Backs [PondRepository] with the `ponds` table (RLS-scoped to
/// `auth.uid()`, so [fetchPonds] only ever needs filtering by [uid] as a
/// belt-and-suspenders match, not as the actual security boundary).
class SupabasePondRepository implements PondRepository {
  SupabasePondRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<List<Pond>> fetchPonds(String uid) async {
    final rows = await _client
        .from('ponds')
        .select()
        .eq('user_id', uid)
        .order('created_at');
    return (rows as List)
        .map((row) => _pondFromRow(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Pond> insertPond({
    required String uid,
    required String name,
    required double latitude,
    required double longitude,
    PondVerification? verification,
  }) async {
    String? photoPath;
    final photo = verification?.photo;
    if (photo != null) {
      // Folder = uid so the storage policy can scope access to the owner.
      final ext = photo.mediaType == 'image/png'
          ? 'png'
          : photo.mediaType == 'image/webp'
          ? 'webp'
          : 'jpg';
      photoPath = '$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await _client.storage
          .from('pond-photos')
          .uploadBinary(
            photoPath,
            photo.bytes,
            fileOptions: FileOptions(contentType: photo.mediaType),
          );
    }

    final row = await _client
        .from('ponds')
        .insert({
          'user_id': uid,
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          if (verification != null) ...{
            'verification_method': verification.method.wireName,
            'photo_path': photoPath,
          },
        })
        .select()
        .single();
    return _pondFromRow(row);
  }

  @override
  Future<void> updatePond(String id, Map<String, Object?> patch) {
    return _client.from('ponds').update(patch).eq('id', id);
  }

  @override
  Future<void> requestVerification(
    String pondId, {
    List<String>? photoPaths,
  }) async {
    await _client.functions.invoke(
      'verify-pond',
      body: {'pond_id': pondId, 'photo_paths': ?photoPaths},
    );
  }

  @override
  Future<List<String>> uploadEvidencePhotos({
    required String uid,
    required String pondId,
    required List<PondPhoto> photos,
  }) async {
    // The folder is <uid>/<pondId>/ — the storage policy scopes access to the
    // owner's own folder, and verify-pond only accepts paths under it.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final paths = <String>[];
    for (final (i, photo) in photos.indexed) {
      final ext = switch (photo.mediaType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
      final path = '$uid/$pondId/evidence-$stamp-$i.$ext';
      await _client.storage
          .from('pond-photos')
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(contentType: photo.mediaType),
          );
      paths.add(path);
    }
    return paths;
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
    verificationMethod: VerificationMethod.fromWire(row['verification_method']),
    verificationStatus: VerificationStatus.fromWire(row['verification_status']),
    verificationMessage: row['verification_message'] as String?,
  );
}
