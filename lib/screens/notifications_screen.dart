import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/weather_context.dart';
import '../providers/notification_provider.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/add_pond_flow.dart';
import '../widgets/status_badge.dart';
import '../l10n/tr.dart';

class _Alert {
  const _Alert({
    required this.pondName,
    required this.type,
    required this.value,
    required this.status,
    this.reason,
  });

  final String pondName;
  final MetricType type;
  final double value;
  final ReadingStatus status;

  /// For a weather risk: what the weather is doing (e.g. "Oxygen may drop
  /// tonight"); null for a reading outside its range.
  final String? reason;
}

/// Current threshold breaches across every pond (from the same readings the
/// dashboard shows, worst first), then the server-sent notifications.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  List<_Alert> _collectAlerts(List<Pond> ponds) {
    final alerts = <_Alert>[];
    for (final pond in ponds) {
      final snapshot = cache.snapshotFor(pond);
      if (snapshot == null) continue; // No device paired yet.
      final alerted = <MetricType>{};
      for (final entry in snapshot.readings.entries) {
        // Only water readings alert; humidity and the companion readings
        // (air temperature, free ammonia) count through weather risks below.
        if (!MetricType.water.contains(entry.key)) continue;
        final status = metricBands[entry.key]!.statusFor(entry.value.value);
        if (status == ReadingStatus.normal) continue;
        alerted.add(entry.key);
        alerts.add(
          _Alert(
            pondName: pond.name,
            type: entry.key,
            value: entry.value.value,
            status: status,
          ),
        );
      }
      // Weather risks serious enough to raise the pond's status, unless that
      // reading already alerts on its own.
      for (final insight in weatherInsights(
        snapshot.readings,
        history: snapshot.history,
      )) {
        final reading = snapshot.reading(insight.affects);
        if (insight.severity == ReadingStatus.normal ||
            reading == null ||
            alerted.contains(insight.affects)) {
          continue;
        }
        alerts.add(
          _Alert(
            pondName: pond.name,
            type: insight.affects,
            value: reading.value,
            status: insight.severity,
            reason: insight.title,
          ),
        );
      }
    }
    alerts.sort((a, b) => b.status.index.compareTo(a.status.index));
    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ponds = context.watch<PondProvider>().ponds;
    final notificationProvider = context.watch<NotificationProvider>();
    final notifications = notificationProvider.notifications;
    final alerts = _collectAlerts(ponds);
    final waitingForPhotos = {
      for (final pond in context.watch<PondProvider>().needsPhotosPonds)
        pond.id,
    };

    if (alerts.isEmpty && notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No alerts — all ponds are within healthy ranges.'.tr,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // One feed: live water alerts (current threshold breaches, so they lead)
    // followed by the server-sent notifications, newest first.
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (notifications.isNotEmpty)
          _ReadAllHeader(
            unread: notificationProvider.unreadCount,
            onMarkAllRead: notificationProvider.markAllRead,
          ),
        for (final alert in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _AlertCard(alert: alert),
          ),
        for (final notification in notifications)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _NotificationCard(
              notification: notification,
              canAddPhotos:
                  notification.type == 'pond_needs_photos' &&
                  waitingForPhotos.contains(notification.pondId),
              onTap: () {
                notificationProvider.markRead(notification.id);
                // A "photos needed" notification opens the photo modal; a
                // "pond verified" one pairs a device with the pond.
                final pondId = notification.pondId;
                if (notification.type == 'pond_needs_photos' &&
                    pondId != null) {
                  openAddPhotosForPond(context, pondId);
                } else if (notification.type == 'pond_verified' &&
                    pondId != null) {
                  openPairDeviceForPond(context, pondId);
                } else if (notification.type == 'device_transfer_request') {
                  openTransferRequest(context, notification.body);
                } else if (notification.isDeviceTransferredToUs) {
                  openAssignTransferredDevice(context, notification.body);
                }
              },
            ),
          ),
      ],
    );
  }
}

/// How many notifications are unread, with a button to mark them all read.
class _ReadAllHeader extends StatelessWidget {
  const _ReadAllHeader({required this.unread, required this.onMarkAllRead});

  final int unread;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              unread == 0
                  ? 'All caught up'.tr
                  : unread == 1
                  ? '1 unread notification'.tr
                  : '{0} unread notifications'.trf([unread]),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: unread == 0 ? null : onMarkAllRead,
            icon: const Icon(Icons.done_all, size: 18),
            label: Text('Mark all as read'.tr),
          ),
        ],
      ),
    );
  }
}

/// A current threshold breach, styled like the other notification cards.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = alert.status.colorOf(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(alert.status.icon, color: color, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alert.pondName} — ${alert.type.label}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [alert.type.format(alert.value), ?alert.reason].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(status: alert.status),
          ],
        ),
      ),
    );
  }
}

/// Icon + accent colour for a notification, by what happened.
(IconData, Color) notificationVisual(
  BuildContext context,
  AppNotification notification,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (notification.type) {
    'water_alert_danger' => (Icons.error, scheme.error),
    'water_alert_warning' => (Icons.warning_rounded, scheme.tertiary),
    'water_alert_cleared' => (Icons.check_circle_outline, scheme.primary),
    'pond_verified' => (Icons.verified, scheme.primary),
    'pond_rejected' => (Icons.cancel_outlined, scheme.error),
    'pond_needs_photos' => (Icons.photo_camera_outlined, scheme.secondary),
    'device_transfer_request' => (Icons.swap_horiz, scheme.tertiary),
    'device_transfer_result' when notification.isDeviceTransferredToUs => (
      Icons.memory,
      scheme.primary,
    ),
    'device_transfer_result' => (
      Icons.do_not_disturb_on_outlined,
      scheme.error,
    ),
    final t when t.startsWith('account_') && t.endsWith('_failed') => (
      Icons.error_outline,
      scheme.error,
    ),
    final t when t.startsWith('account_') => (
      Icons.check_circle_outline,
      scheme.primary,
    ),
    _ => (Icons.error_outline, scheme.tertiary),
  };
}

/// "Just now", "5 min ago", "2 h ago", "3 d ago".
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now'.tr;
  if (diff.inMinutes < 60) return '{0} min ago'.trf([diff.inMinutes]);
  if (diff.inHours < 24) return '{0} h ago'.trf([diff.inHours]);
  return '{0} d ago'.trf([diff.inDays]);
}

/// One server-sent notification (currently pond verification results): a
/// tinted icon badge, the title and time on one line, the message beneath, and
/// a subtle highlight plus dot while unread.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    this.canAddPhotos = false,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  /// Shows an explicit "Add photos" button (the pond is still waiting).
  final bool canAddPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = notificationVisual(context, notification);
    final unread = !notification.isRead;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: unread ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title.tr,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          relativeTime(notification.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Icon(Icons.circle, size: 8, color: scheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      notification.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (canAddPhotos) ...[
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.tonalIcon(
                        onPressed: onTap,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text('Add photos'.tr),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
