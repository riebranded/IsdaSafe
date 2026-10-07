import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// What [NotificationProvider] needs from a backing store — factored out like
/// [PondRepository] so it can be tested against an in-memory fake.
abstract class NotificationRepository {
  String? get currentUserId;

  /// Emits whenever the signed-in user changes, including to/from null.
  Stream<String?> get userIdChanges;

  /// Live list of [uid]'s notifications, newest first. Emits the current rows
  /// first, then again on every change.
  Stream<List<AppNotification>> watch(String uid);

  Future<void> markRead(Iterable<String> ids);
}

/// Backs [NotificationRepository] with the `notifications` table (RLS-scoped
/// to `auth.uid()`) using Supabase Realtime, so a verification result shows
/// up the moment the edge function writes it.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Stream<List<AppNotification>> watch(String uid) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AppNotification.fromRow).toList());
  }

  @override
  Future<void> markRead(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', list);
  }
}
