import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fish_species.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/fish_species_catalog.dart';
import '../theme/app_spacing.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/reading_grid.dart';
import '../widgets/species_recommendation_card.dart';
import '../widgets/status_badge.dart';

/// Full-screen mobile route: pushed from `DashboardScreen` or `PondMapScreen`,
/// owns its own [AppBar] with the pond name + refresh action.
class PondDashboardScreen extends StatelessWidget {
  const PondDashboardScreen({super.key, required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardProvider(pond: pond),
      child: _MobileDashboardScaffold(pond: pond),
    );
  }
}

class _MobileDashboardScaffold extends StatelessWidget {
  const _MobileDashboardScaffold({required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pond.name),
        actions: [
          IconButton(
            onPressed: () => context.read<DashboardProvider>().refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh readings',
          ),
        ],
      ),
      body: PondDashboardBody(pond: pond, showHeader: false),
    );
  }
}

/// The pond dashboard's actual content — status banner, latest readings,
/// species suggestions. Reused both as a full mobile screen's body (above,
/// [showHeader] false since the [AppBar] already shows the pond name) and
/// embedded in the wide/web sidebar layout ([showHeader] true, since there
/// the pond name has no [AppBar] to live in). Must be built as a descendant
/// of a `ChangeNotifierProvider<DashboardProvider>`.
class PondDashboardBody extends StatelessWidget {
  const PondDashboardBody({super.key, required this.pond, required this.showHeader});

  final Pond pond;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final snapshot = dashboard.snapshot;
    // Subscribed purely so editing this pond's species (below) rebuilds
    // immediately — `pond` itself is a shared, in-place-mutated instance, so
    // this widget just needs telling when to re-read it, not a new value.
    context.watch<PondProvider>();

    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async => context.read<DashboardProvider>().refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      pond.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.read<DashboardProvider>().refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh readings',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (pond.hasLocation) ...[
              _PondLocationLine(latitude: pond.latitude!, longitude: pond.longitude!),
              const SizedBox(height: AppSpacing.md),
            ],
            _PondStatusBanner(status: overallStatus(snapshot.readings)),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text('Latest readings', style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: AppSpacing.sm),
                _LastUpdated(timestamp: snapshot.reading(snapshot.readings.keys.first).timestamp),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ReadingGrid(readings: snapshot.readings, history: snapshot.history),
            const SizedBox(height: AppSpacing.xl),
            Text('Feeding schedule', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _FeedingScheduleSection(pond: pond),
            const SizedBox(height: AppSpacing.xl),
            Text('Individual trends', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            for (final type in MetricType.values) ...[
              IndividualTrendChart(type: type, history: snapshot.history[type]!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('AI Recommended Species', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SpeciesRecommendationCard(
              recommendation: dashboard.recommendation,
              loading: dashboard.recommendationLoading,
              error: dashboard.recommendationError,
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggested feeding times for whichever species [pond] has been marked as
/// holding (see [Pond.speciesNames]) — distinct from the water-quality-based
/// "Suitable fish species" suggestions further down this screen. Offers an
/// "Add"/"Edit species" action either way, since [showSelectSpeciesDialog]
/// is otherwise only ever shown once, right after a pond is created.
class _FeedingScheduleSection extends StatelessWidget {
  const _FeedingScheduleSection({required this.pond});

  final Pond pond;

  Future<void> _editSpecies(BuildContext context) async {
    final species = await showSelectSpeciesDialog(context, initialSelection: pond.speciesNames);
    if (species == null || !context.mounted) return;

    final ok = await context.read<PondProvider>().setSpecies(pond.id, species);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save changes. Check your connection and try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final species = pond.speciesNames.map(FishSpeciesCatalog.byName).whereType<FishSpecies>().toList();

    if (species.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.set_meal_outlined),
          title: const Text('No fish species added yet'),
          subtitle: const Text('Add species to see suggested feeding times.'),
          trailing: TextButton(onPressed: () => _editSpecies(context), child: const Text('Add')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final fish in species) ...[
              Text(
                '${fish.name} (${fish.localName})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final time in fish.feedingTimes)
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(time),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (fish != species.last) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editSpecies(context),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit species'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PondLocationLine extends StatelessWidget {
  const _PondLocationLine({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// At-a-glance overall pond health, computed as the worst status across
/// every reading — answers "do I need to look closer?" before the reader
/// scans all 5 metric cards individually.
class _PondStatusBanner extends StatelessWidget {
  const _PondStatusBanner({required this.status});

  final ReadingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.colorOf(context);
    final message = switch (status) {
      ReadingStatus.normal => 'All readings are within a healthy range.',
      ReadingStatus.warning => 'One or more readings are drifting outside the healthy range.',
      ReadingStatus.critical => 'One or more readings need attention now.',
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(status.icon, color: color, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pond status: ${status.label}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: color),
                ),
                const SizedBox(height: 2),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastUpdated extends StatelessWidget {
  const _LastUpdated({required this.timestamp});

  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Updated ${_relativeTime(timestamp)}',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
