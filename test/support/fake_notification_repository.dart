import 'dart:async';

import 'package:isdasafev2/models/app_notification.dart';
import 'package:isdasafev2/services/notification_repository.dart';

/// In-memory [NotificationRepository] — lets [NotificationProvider] (and the
/// screens that read it) run in tests without a live Supabase project.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    String? userId = 'test-user',
    List<AppNotification>? seed,
    // Named parameters can't be private, so _userId can't be an initializing formal.
    // ignore: prefer_initializing_formals
  }) : _userId = userId,
       _notifications = seed ?? [];

  String? _userId;
  List<AppNotification> _notifications;
  final _userIdController = StreamController<String?>.broadcast();
  final _listController = StreamController<List<AppNotification>>.broadcast();

  /// Ids passed to [markRead].
  final markedRead = <String>[];

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> get userIdChanges => _userIdController.stream;

  void setUserId(String? uid) {
    _userId = uid;
    _userIdController.add(uid);
  }

  @override
  Stream<List<AppNotification>> watch(String uid) async* {
    yield List.of(_notifications);
    yield* _listController.stream;
  }

  /// Simulates the server inserting a notification (newest first).
  void push(AppNotification notification) {
    _notifications = [notification, ..._notifications];
    _listController.add(List.of(_notifications));
  }

  @override
  Future<void> markRead(Iterable<String> ids) async {
    markedRead.addAll(ids);
  }

  Future<void> dispose() async {
    await _userIdController.close();
    await _listController.close();
  }
}

AppNotification fakeNotification(
  String id, {
  String type = 'pond_verified',
  String title = 'Pond verified',
  String body = 'Your pond was verified.',
  DateTime? readAt,
}) => AppNotification(
  id: id,
  type: type,
  title: title,
  body: body,
  createdAt: DateTime.now(),
  readAt: readAt,
);

extension FakeNotificationPond on AppNotification {
  /// Same notification, announcing [pondId].
  AppNotification copyWithPond(String pondId) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    pondId: pondId,
    readAt: readAt,
  );
}
