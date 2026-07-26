import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/fish_species_catalog.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/reading_grid.dart';
import '../widgets/species_recommendation_card.dart';
import '../widgets/staggered_entrance.dart';
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
            Row(
              children: [
                Expanded(
                  child: Text('Feeding schedule', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: () => _editPondSpecies(context, pond),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: pond.speciesNames.isEmpty ? 'Add species' : 'Edit species',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _FeedingScheduleSection(pond: pond),
            const SizedBox(height: AppSpacing.xl),
            Text('Water quality recommendations', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _AdvisoryList(
              icon: Icons.tips_and_updates_outlined,
              accentColor: Theme.of(context).colorScheme.primary,
              items: dashboard.waterQualityRecommendations,
              hasSpecies: pond.speciesNames.isNotEmpty,
              loading: dashboard.feedingLoading,
              error: dashboard.feedingError,
              emptyMessage: 'No specific recommendations right now — readings look healthy.',
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Possible risks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _AdvisoryList(
              icon: Icons.warning_amber_outlined,
              accentColor: context.statusColors.warning,
              items: dashboard.possibleRisks,
              hasSpecies: pond.speciesNames.isNotEmpty,
              loading: dashboard.feedingLoading,
              error: dashboard.feedingError,
              emptyMessage: 'No notable risks identified right now.',
            ),
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

/// Opens the species picker and saves the result, shared by the "Feeding
/// schedule" heading's edit action and its empty-state "Add" button.
/// Re-fetches feeding/water-quality advisories on success, since they're
/// keyed by [Pond.speciesNames].
Future<void> _editPondSpecies(BuildContext context, Pond pond) async {
  final species = await showSelectSpeciesDialog(context, initialSelection: pond.speciesNames);
  if (species == null || !context.mounted) return;

  final ok = await context.read<PondProvider>().setSpecies(pond.id, species);
  if (!context.mounted) return;
  if (ok) {
    context.read<DashboardProvider>().retryFeedingRecommendations();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't save changes. Check your connection and try again.")),
    );
  }
}

/// AI-generated feeding plan (time/frequency/amount) for whichever species
/// [pond] has been marked as holding (see [Pond.speciesNames]), sourced from
/// the Render-hosted `/feeding-recommendation` endpoint via
/// [DashboardProvider.feedingRecommendations] — distinct from the AI species
/// recommendation further down this screen, which suggests *which* species
/// suit the pond rather than how to feed ones already stocked.
class _FeedingScheduleSection extends StatelessWidget {
  const _FeedingScheduleSection({required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dashboard = context.watch<DashboardProvider>();

    if (pond.speciesNames.isEmpty) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: const Icon(Icons.set_meal_outlined, size: 18),
          ),
          title: const Text('No fish species added yet'),
          subtitle: const Text('Add species to see an AI-generated feeding plan.'),
          trailing: TextButton(onPressed: () => _editPondSpecies(context, pond), child: const Text('Add')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, name) in pond.speciesNames.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: name == pond.speciesNames.last ? 0 : AppSpacing.sm),
            child: StaggeredEntrance(
              index: index,
              child: _FeedingSpeciesCard(
                name: name,
                recommendation: dashboard.feedingRecommendations[name],
                loading: dashboard.feedingLoading && !dashboard.feedingRecommendations.containsKey(name),
                error: dashboard.feedingError,
              ),
            ),
          ),
      ],
    );
  }
}

/// One species' feeding plan card within [_FeedingScheduleSection]: a header
/// (species name + local name) over three detail tiles, or a loading/error
/// state while [DashboardProvider] fetches it.
class _FeedingSpeciesCard extends StatelessWidget {
  const _FeedingSpeciesCard({
    required this.name,
    required this.recommendation,
    required this.loading,
    required this.error,
  });

  final String name;
  final FeedingRecommendation? recommendation;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localName = FishSpeciesCatalog.byName(name)?.localName;
    final header = localName != null && localName != name ? '$name ($localName)' : name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.set_meal, size: 16),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(header, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (recommendation != null) ...[
              _FeedingDetailTile(icon: Icons.schedule, label: 'Feeding time', value: recommendation!.feedingTime),
              const SizedBox(height: AppSpacing.sm),
              _FeedingDetailTile(
                icon: Icons.repeat,
                label: 'Frequency',
                value: recommendation!.feedingFrequency,
              ),
              const SizedBox(height: AppSpacing.sm),
              _FeedingDetailTile(
                icon: Icons.scale_outlined,
                label: 'Amount',
                value: recommendation!.feedingAmount,
              ),
            ] else if (loading) ...[
              Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Asking the model for a feeding plan…', style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ] else if (error != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single labeled fact within a [_FeedingSpeciesCard] (feeding time,
/// frequency, or amount) — a tinted tile rather than a plain text line since
/// Gemini's values are full sentences, not short numbers.
class _FeedingDetailTile extends StatelessWidget {
  const _FeedingDetailTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared list for the "Water quality recommendations" and "Possible risks"
/// sections — both are strings sourced from
/// [DashboardProvider.feedingRecommendations] (bundled with the feeding plan
/// per species, since the Render endpoint requires a species to advise on).
/// Each item renders as its own [accentColor]-tinted tile rather than a
/// single enclosing card, so a long list of distinct tips/risks stays easy
/// to scan.
class _AdvisoryList extends StatelessWidget {
  const _AdvisoryList({
    required this.icon,
    required this.accentColor,
    required this.items,
    required this.hasSpecies,
    required this.loading,
    required this.error,
    required this.emptyMessage,
  });

  final IconData icon;
  final Color accentColor;
  final List<String> items;
  final bool hasSpecies;
  final bool loading;
  final String? error;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hasSpecies) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            child: const Icon(Icons.set_meal_outlined, size: 18),
          ),
          title: const Text('No fish species added yet'),
          subtitle: const Text('Add a species in "Feeding schedule" above to see this.'),
        ),
      );
    }

    if (loading && items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: AppSpacing.md),
              const Expanded(child: Text('Asking the model for guidance…')),
            ],
          ),
        ),
      );
    }

    if (error != null && items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error!, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => context.read<DashboardProvider>().retryFeedingRecommendations(),
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: item == items.last ? 0 : AppSpacing.sm),
            child: StaggeredEntrance(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: accentColor),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ),
      ],
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
