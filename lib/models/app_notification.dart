/// A server-created, in-app notification (row of `public.notifications`):
/// a pond verification outcome, a device transfer, or a water alert. Not to
/// be confused with the live water-quality alerts the Notifications screen
/// also works out from the current readings.
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

  /// `water_alert_warning`, `water_alert_danger` or `water_alert_cleared`:
  /// a pond's water reading entered warning or danger, or recovered —
  /// written by the `evaluate_water_alerts()` trigger when a reading arrives
  /// (which may also text the owner).
  bool get isWaterAlert => type.startsWith('water_alert_');

  /// `device_transfer_request` (to a device's owner) or
  /// `device_transfer_result` (to whoever asked) — written by
  /// `request_device_transfer()` / `respond_device_transfer()`.
  bool get isDeviceTransfer => type.startsWith('device_transfer_');

  /// The transfer was approved: the device is now this account's, without a
  /// pond yet.
  bool get isDeviceTransferredToUs =>
      type == 'device_transfer_result' && title == 'Device transferred to you';

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
