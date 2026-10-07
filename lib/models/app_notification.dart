/// A server-created, in-app notification (row of `public.notifications`) —
/// currently the outcome of a pond verification. Not to be confused with the
/// derived water-quality alerts the Notifications screen also lists.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.pondId,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? pondId;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// `pond_verified`, `pond_rejected` or `pond_error` — written by the
  /// `verify-pond` edge function.
  bool get isPondVerification => type.startsWith('pond_');

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
    id: row['id'] as String,
    type: row['type'] as String,
    title: row['title'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    pondId: row['pond_id'] as String?,
    readAt: row['read_at'] == null
        ? null
        : DateTime.parse(row['read_at'] as String),
  );

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    pondId: pondId,
    readAt: readAt ?? this.readAt,
  );
}
