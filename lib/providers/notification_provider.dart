import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../services/notification_repository.dart';

/// The signed-in user's in-app notifications, kept live via the repository's
/// stream. Like [PondProvider] it's constructed once before sign-in, so it
/// follows [NotificationRepository.userIdChanges] to (re)subscribe or clear.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider({
    NotificationRepository? repository,
    this.onNewNotification,
  }) : _repository = repository ?? SupabaseNotificationRepository() {
    _userIdSub = _repository.userIdChanges.listen(_handleUserIdChange);
    _subscribe(_repository.currentUserId);
  }

  final NotificationRepository _repository;

  /// Called for each notification that arrives while the app is running (not
  /// for the ones already there at sign-in) — used to refresh pond statuses.
  final void Function(AppNotification notification)? onNewNotification;

  final _incoming = StreamController<AppNotification>.broadcast();
  StreamSubscription<String?>? _userIdSub;
  StreamSubscription<List<AppNotification>>? _notificationsSub;

  String? _subscribedUid;
  List<AppNotification> _notifications = [];
  Set<String> _knownIds = {};

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// New notifications as they arrive, for transient in-app alerts (snackbars).
  Stream<AppNotification> get incoming => _incoming.stream;

  void _handleUserIdChange(String? uid) => _subscribe(uid);

  void _subscribe(String? uid) {
    // Token refreshes re-emit the same user; only a real change resubscribes.
    if (uid == _subscribedUid) return;
    _subscribedUid = uid;
    _notificationsSub?.cancel();
    _notificationsSub = null;
    _notifications = [];
    _knownIds = {};
    notifyListeners();
    if (uid == null) return;

    var first = true;
    _notificationsSub = _repository.watch(uid).listen(
      (list) {
        final fresh = first
            ? const <AppNotification>[]
            : list.where((n) => !_knownIds.contains(n.id)).toList();
        first = false;
        _notifications = list;
        _knownIds = {for (final n in list) n.id};
        notifyListeners();
        // Oldest first so a burst is announced in order.
        for (final n in fresh.reversed) {
          _incoming.add(n);
          onNewNotification?.call(n);
        }
      },
      onError: (Object e) =>
          debugPrint('NotificationProvider: stream error $e'),
    );
  }

  Future<void> markRead(String id) => _markRead([id]);

  Future<void> markAllRead() =>
      _markRead(_notifications.where((n) => !n.isRead).map((n) => n.id));

  Future<void> _markRead(Iterable<String> ids) async {
    final toMark = ids.toSet();
    if (toMark.isEmpty) return;
    final now = DateTime.now();
    // Optimistic: the realtime echo of the update will confirm it.
    _notifications = [
      for (final n in _notifications)
        toMark.contains(n.id) ? n.copyWith(readAt: now) : n,
    ];
    notifyListeners();
    try {
      await _repository.markRead(toMark);
    } catch (e) {
      debugPrint('NotificationProvider: markRead error $e');
    }
  }

  @override
  void dispose() {
    _userIdSub?.cancel();
    _notificationsSub?.cancel();
    _incoming.close();
    super.dispose();
  }
}
