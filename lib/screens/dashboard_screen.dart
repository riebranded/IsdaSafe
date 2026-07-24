import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/reading_grid.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/status_badge.dart';
import 'pond_dashboard_screen.dart';

/// Every pond as one list item that already shows *all* its sensor
/// readings (via [ReadingGrid], not just a status dot). On narrow layouts,
/// tapping a card pushes [PondDashboardScreen]. On wide layouts
/// ([showDetailPane]) it instead selects the pond (via [onSelectPond]) and
/// the content area shows that pond's full dashboard in place of the list —
/// so the app's side panel stays visible rather than being covered by a
/// full-screen push. [onClearPond] returns to the list.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.cache,
    this.showDetailPane = false,
    this.selectedPondId,
    this.onSelectPond,
    this.onClearPond,
  });

  final PondSnapshotCache cache;

  /// Wide layout: when a pond is selected, replace the list with that pond's
  /// dashboard (side panel stays visible) instead of a full-screen push.
  final bool showDetailPane;

  /// Which pond to show (null → the pond list). Owned by [AppShell] so the
  /// side-panel sub-buttons and the cards stay in sync.
  final String? selectedPondId;

  /// Called when a card is tapped in [showDetailPane] mode.
  final ValueChanged<Pond>? onSelectPond;

  /// Called by the detail view's back action to return to the list.
  final VoidCallback? onClearPond;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<void> _refreshAll(List<Pond> ponds) async {
    setState(() => widget.cache.refreshAll(ponds));
  }

  Future<void> _renamePond(BuildContext context, Pond pond) async {
    final name = await showPondNameDialog(context, initialValue: pond.name);
    if (name != null && context.mounted) {
      context.read<PondProvider>().renamePond(pond.id, name);
    }
  }

  Future<void> _editLocation(BuildContext context, Pond pond) async {
    final location = await showEditLocationDialog(
      context,
      initialLatitude: pond.latitude ?? kDefaultMapCenter.latitude,
      initialLongitude: pond.longitude ?? kDefaultMapCenter.longitude,
    );
    if (location != null && context.mounted) {
      context.read<PondProvider>().setLocation(
            pond.id,
            latitude: location.latitude,
            longitude: location.longitude,
          );
    }
  }

  Future<void> _removePond(BuildContext context, Pond pond) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove pond'),
        content: Text('Remove "${pond.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      widget.cache.discard(pond.id);
      context.read<PondProvider>().removePond(pond.id);
    }
  }

  void _openPond(BuildContext context, Pond pond) {
    // Wide layout: select the pond so the inline detail pane shows it (the
    // side panel stays visible). Narrow layout: push the full-screen view.
    if (widget.showDetailPane && widget.onSelectPond != null) {
      widget.onSelectPond!(pond);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PondDashboardScreen(pond: pond)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ponds = context.watch<PondProvider>().ponds;

    if (ponds.isEmpty) {
      return _EmptyDashboard(onAddPond: () async {
        final draft = await showAddPondDialog(context);
        if (draft != null && context.mounted) {
          context.read<PondProvider>().addPond(draft.name, latitude: draft.latitude, longitude: draft.longitude);
        }
      });
    }

    // Wide layout: a selected pond takes over the content area (side panel
    // stays visible); otherwise the full-grid overview list. Narrow/mobile
    // gets the compact summary + one-row-readings design.
    if (widget.showDetailPane) {
      final selected = _selectedPond(ponds);
      if (selected != null) {
        return _PondDetailView(pond: selected, onBack: widget.onClearPond);
      }
      return _pondList(ponds);
    }

    return _mobileList(ponds);
  }

  Widget _mobileList(List<Pond> ponds) {
    var normal = 0;
    var warning = 0;
    var critical = 0;
    for (final pond in ponds) {
      switch (overallStatus(widget.cache.snapshotFor(pond).readings)) {
        case ReadingStatus.normal:
          normal++;
        case ReadingStatus.warning:
          warning++;
        case ReadingStatus.critical:
          critical++;
      }
    }

    return RefreshIndicator(
      onRefresh: () => _refreshAll(ponds),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl + AppSpacing.xl,
        ),
        children: [
          _StatusSummary(normal: normal, warning: warning, critical: critical),
          const SizedBox(height: AppSpacing.lg),
          for (final (index, pond) in ponds.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            StaggeredEntrance(
              index: index,
              child: _MobilePondCard(
                pond: pond,
                status: overallStatus(widget.cache.snapshotFor(pond).readings),
                readings: widget.cache.snapshotFor(pond).readings,
                onTap: () => _openPond(context, pond),
                onRename: () => _renamePond(context, pond),
                onEditLocation: () => _editLocation(context, pond),
                onRemove: () => _removePond(context, pond),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Pond? _selectedPond(List<Pond> ponds) {
    for (final pond in ponds) {
      if (pond.id == widget.selectedPondId) return pond;
    }
    return null;
  }

  Widget _pondList(List<Pond> ponds) {
    return RefreshIndicator(
      onRefresh: () => _refreshAll(ponds),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl + AppSpacing.xl,
        ),
        itemCount: ponds.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final pond = ponds[index];
          final snapshot = widget.cache.snapshotFor(pond);
          return StaggeredEntrance(
            index: index,
            child: _PondSummaryCard(
              pond: pond,
              status: overallStatus(snapshot.readings),
              readings: snapshot.readings,
              history: snapshot.history,
              onTap: () => _openPond(context, pond),
              onRename: () => _renamePond(context, pond),
              onEditLocation: () => _editLocation(context, pond),
              onRemove: () => _removePond(context, pond),
            ),
          );
        },
      ),
    );
  }
}

/// The selected pond's full dashboard, shown in place of the list on wide
/// layouts (the side panel stays visible). A back action returns to the list.
class _PondDetailView extends StatelessWidget {
  const _PondDetailView({required this.pond, required this.onBack});

  final Pond pond;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, 0),
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('All ponds'),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ChangeNotifierProvider<DashboardProvider>(
                key: ValueKey(pond.id),
                create: (_) => DashboardProvider(pond: pond),
                child: PondDashboardBody(pond: pond, showHeader: true),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
/// Mobile overview header: how many ponds are Normal / Warning / Critical.
class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.normal, required this.warning, required this.critical});

  final int normal;
  final int warning;
  final int critical;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SummaryTile(count: normal, label: 'Normal', status: ReadingStatus.normal)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _SummaryTile(count: warning, label: 'Warning', status: ReadingStatus.warning)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _SummaryTile(count: critical, label: 'Critical', status: ReadingStatus.critical)),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.count, required this.label, required this.status});

  final int count;
  final String label;
  final ReadingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.colorOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$count',
                style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Compact pond card for the mobile dashboard: name with location beneath it,
/// a status badge pinned top-right, and all readings condensed into one row.
class _MobilePondCard extends StatelessWidget {
  const _MobilePondCard({
    required this.pond,
    required this.status,
    required this.readings,
    required this.onTap,
    required this.onRename,
    required this.onEditLocation,
    required this.onRemove,
  });

  final Pond pond;
  final ReadingStatus status;
  final Map<MetricType, SensorReading> readings;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditLocation;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pond.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _PondLocationLine(pond: pond),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(status: status),
                  PopupMenuButton<String>(
                    tooltip: 'Pond options',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'location') onEditLocation();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'location', child: Text('Edit location')),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final type in MetricType.values)
                    Expanded(child: _ReadingChip(type: type, value: readings[type]!.value)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One metric condensed to an icon + value, sized to share a row equally.
class _ReadingChip extends StatelessWidget {
  const _ReadingChip({required this.type, required this.value});

  final MetricType type;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(type.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            type.format(value),
            maxLines: 1,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pond coordinates (or "No location set"), shown beneath the pond name.
class _PondLocationLine extends StatelessWidget {
  const _PondLocationLine({required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = pond.hasLocation
        ? '${pond.latitude!.toStringAsFixed(4)}, ${pond.longitude!.toStringAsFixed(4)}'
        : 'No location set';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}



class _PondSummaryCard extends StatelessWidget {
  const _PondSummaryCard({
    required this.pond,
    required this.status,
    required this.readings,
    required this.history,
    required this.onTap,
    required this.onRename,
    required this.onEditLocation,
    required this.onRemove,
  });

  final Pond pond;
  final ReadingStatus status;
  final Map<MetricType, SensorReading> readings;
  final Map<MetricType, List<SensorReading>> history;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditLocation;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pond.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(status: status),
                  PopupMenuButton<String>(
                    tooltip: 'Pond options',
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'location') onEditLocation();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'location', child: Text('Edit location')),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ReadingGrid(readings: readings, history: history),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.onAddPond});

  final VoidCallback onAddPond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.water_drop_outlined, size: 44, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No ponds yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add a pond to start tracking its water quality and\nsee which fish species it can support.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(onPressed: onAddPond, icon: const Icon(Icons.add), label: const Text('Add your first pond')),
          ],
        ),
      ),
    );
  }
}
