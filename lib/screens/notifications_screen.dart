import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/status_badge.dart';

class _Alert {
  const _Alert({required this.pondName, required this.type, required this.value, required this.status});

  final String pondName;
  final MetricType type;
  final double value;
  final ReadingStatus status;
}

/// Derived list of current threshold breaches across every pond — no new
/// backend, just re-reads the same mock snapshots already used elsewhere
/// (`metricBands[type]!.statusFor(...)`), sorted worst-first.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  List<_Alert> _collectAlerts(List<Pond> ponds) {
    final alerts = <_Alert>[];
    for (final pond in ponds) {
      final snapshot = cache.snapshotFor(pond);
      for (final entry in snapshot.readings.entries) {
        final status = metricBands[entry.key]!.statusFor(entry.value.value);
        if (status == ReadingStatus.normal) continue;
        alerts.add(_Alert(pondName: pond.name, type: entry.key, value: entry.value.value, status: status));
      }
    }
    alerts.sort((a, b) => b.status.index.compareTo(a.status.index));
    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ponds = context.watch<PondProvider>().ponds;
    final alerts = _collectAlerts(ponds);

    if (alerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No alerts — all ponds are within healthy ranges.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return Card(
          child: ListTile(
            leading: Icon(alert.status.icon, color: alert.status.colorOf(context)),
            title: Text('${alert.pondName} — ${alert.type.label}'),
            subtitle: Text(alert.type.format(alert.value)),
            trailing: StatusBadge(status: alert.status),
          ),
        );
      },
    );
  }
}
