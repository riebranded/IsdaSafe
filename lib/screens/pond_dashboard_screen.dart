import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/trend_range.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/fish_species_catalog.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../services/pond_snapshot_cache.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/metric_detail_view.dart';
import '../widgets/pond_chat_sheet.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/reading_grid.dart';
import '../widgets/species_recommendation_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/status_badge.dart';
import '../l10n/tr.dart';

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
            tooltip: 'Refresh readings'.tr,
          ),
        ],
      ),
      body: PondDashboardBody(pond: pond, showHeader: false),
      floatingActionButton: PondChatFab(pond: pond),
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
  const PondDashboardBody({
    super.key,
    required this.pond,
    required this.showHeader,
  });

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
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          showHeader ? AppSpacing.lg : 88,
        ),
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
                    onPressed: () =>
                        context.read<DashboardProvider>().refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh readings'.tr,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (pond.hasLocation) ...[
              _PondLocationLine(
                latitude: pond.latitude!,
                longitude: pond.longitude!,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _PondStatusBanner(status: overallStatus(snapshot.readings)),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(
              icon: Icons.sensors,
              title: 'Latest readings'.tr,
              trailing: _LastUpdated(
                timestamp: snapshot
                    .reading(snapshot.readings.keys.first)
                    .timestamp,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ReadingGrid(readings: snapshot.readings, history: snapshot.history),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              icon: Icons.set_meal_outlined,
              title: 'Feeding schedule'.tr,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AskAiButton(pond: pond, topic: ChatTopic.feeding),
                  IconButton(
                    onPressed: () => _editPondSpecies(context, pond),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: pond.speciesNames.isEmpty
                        ? 'Add species'.tr
                        : 'Edit species'.tr,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _FeedingScheduleSection(pond: pond),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              icon: Icons.tips_and_updates_outlined,
              title: 'Water quality recommendations'.tr,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CountPill(
                    count: _advisories(
                      dashboard,
                      (r) => r.waterQualityRecommendations,
                    ).length,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AskAiButton(pond: pond, topic: ChatTopic.waterQuality),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _AdvisoryList(
              icon: Icons.tips_and_updates_outlined,
              accentColor: Theme.of(context).colorScheme.primary,
              items: _advisories(
                dashboard,
                (r) => r.waterQualityRecommendations,
              ),
              hasSpecies: pond.speciesNames.isNotEmpty,
              loading: dashboard.feedingLoading,
              error: dashboard.feedingError,
              emptyMessage:
                  'No specific recommendations right now — readings look healthy.'.tr,
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(
              icon: Icons.warning_amber_outlined,
              title: 'Possible risks'.tr,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CountPill(
                    count: _advisories(
                      dashboard,
                      (r) => r.possibleRisks,
                    ).length,
                    color: context.statusColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AskAiButton(pond: pond, topic: ChatTopic.risks),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _AdvisoryList(
              icon: Icons.warning_amber_outlined,
              accentColor: context.statusColors.warning,
              items: _advisories(dashboard, (r) => r.possibleRisks),
              hasSpecies: pond.speciesNames.isNotEmpty,
              loading: dashboard.feedingLoading,
              error: dashboard.feedingError,
              emptyMessage: 'No notable risks identified right now.'.tr,
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(icon: Icons.show_chart, title: 'Individual trends'.tr),
            const SizedBox(height: AppSpacing.md),
            for (final type in MetricType.values) ...[
              IndividualTrendChart(
                type: type,
                history: snapshot.history[type]!,
                range: TrendRange.hourly,
                onTap: () => showMetricDetail(
                  context,
                  pond: pond,
                  type: type,
                  // History is seeded per pond, so a standalone cache yields
                  // the same series the dashboard card shows.
                  cache: PondSnapshotCache(),
                  initialRange: TrendRange.hourly,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _SectionHeader(
              icon: Icons.auto_awesome_outlined,
              title: 'AI Recommended Species'.tr,
            ),
            const SizedBox(height: AppSpacing.md),
            SpeciesRecommendationCard(
              recommendation: dashboard.recommendation,
              readings: snapshot.readings,
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
  final species = await showSelectSpeciesDialog(
    context,
    initialSelection: pond.speciesNames,
  );
  if (species == null || !context.mounted) return;

  final ok = await context.read<PondProvider>().setSpecies(pond.id, species);
  if (!context.mounted) return;
  if (ok) {
    context.read<DashboardProvider>().retryFeedingRecommendations();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Couldn\'t save changes. Check your connection and try again.'.tr,
        ),
      ),
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
          title: Text('No fish species added yet'.tr),
          subtitle: Text(
            'Add species to see an AI-generated feeding plan.'.tr,
          ),
          trailing: TextButton(
            onPressed: () => _editPondSpecies(context, pond),
            child: Text('Add'.tr),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, name) in pond.speciesNames.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: name == pond.speciesNames.last ? 0 : AppSpacing.sm,
            ),
            child: StaggeredEntrance(
              index: index,
              child: _FeedingSpeciesCard(
                name: name,
                recommendation: dashboard.feedingRecommendations[name],
                loading:
                    dashboard.feedingLoading &&
                    !dashboard.feedingRecommendations.containsKey(name),
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
    final header = localName != null && localName != name
        ? '$name ($localName)'
        : name;

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
                  child: Text(
                    header,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (recommendation != null) ...[
              _FeedingDetailTile(
                icon: Icons.schedule,
                label: 'Feeding time'.tr,
                value: recommendation!.feedingTime,
              ),
              const SizedBox(height: AppSpacing.sm),
              _FeedingDetailTile(
                icon: Icons.repeat,
                label: 'Frequency'.tr,
                value: recommendation!.feedingFrequency,
              ),
              const SizedBox(height: AppSpacing.sm),
              _FeedingDetailTile(
                icon: Icons.scale_outlined,
                label: 'Amount'.tr,
                value: recommendation!.feedingAmount,
              ),
            ] else if (loading) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Asking the model for a feeding plan…'.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ] else if (error != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
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
  const _FeedingDetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

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
/// One tip or risk, with the species (of this pond's) it applies to.
typedef _Advisory = ({String text, List<String> species});

/// Merges the per-species advice picked by [pick] into one list: identical
/// advice shared by several species appears once, tagged with all of them.
List<_Advisory> _advisories(
  DashboardProvider dashboard,
  List<String> Function(FeedingRecommendation) pick,
) {
  final bySpecies = <String, List<String>>{};
  for (final entry in dashboard.feedingRecommendations.entries) {
    for (final text in pick(entry.value)) {
      bySpecies.putIfAbsent(text, () => []).add(entry.key);
    }
  }
  return [
    for (final entry in bySpecies.entries)
      (text: entry.key, species: entry.value),
  ];
}

/// How many items a section lists before collapsing the rest behind
/// "Show more".
const _advisoryPreviewCount = 3;

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: c,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdvisoryList extends StatefulWidget {
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
  final List<_Advisory> items;
  final bool hasSpecies;
  final bool loading;
  final String? error;
  final String emptyMessage;

  @override
  State<_AdvisoryList> createState() => _AdvisoryListState();
}

class _AdvisoryListState extends State<_AdvisoryList> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = widget.icon;
    final accentColor = widget.accentColor;
    final items = widget.items;
    final hasSpecies = widget.hasSpecies;
    final loading = widget.loading;
    final error = widget.error;
    final emptyMessage = widget.emptyMessage;

    if (!hasSpecies) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            child: const Icon(Icons.set_meal_outlined, size: 18),
          ),
          title: Text('No fish species added yet'.tr),
          subtitle: Text(
            'Add a species in "Feeding schedule" above to see this.'.tr,
          ),
        ),
      );
    }

    if (loading && items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Asking the model for guidance…'.tr)),
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
                    Text(error, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => context
                            .read<DashboardProvider>()
                            .retryFeedingRecommendations(),
                        child: Text('Retry'.tr),
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.statusColors.good.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: context.statusColors.good,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(emptyMessage)),
            ],
          ),
        ),
      );
    }

    final collapsible = items.length > _advisoryPreviewCount;
    final shown = collapsible && !_expanded
        ? items.take(_advisoryPreviewCount).toList()
        : items;
    // Species tags only help when more than one species could be meant.
    final showSpecies = hasSpecies && items.any((i) => i.species.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in shown.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == shown.length - 1 ? 0 : AppSpacing.sm,
            ),
            child: StaggeredEntrance(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(icon, size: 18, color: accentColor),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.text, style: theme.textTheme.bodyMedium),
                          if (showSpecies && item.species.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                for (final name in item.species)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.pill,
                                      ),
                                    ),
                                    child: Text(
                                      name,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (collapsible)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _expanded
                    ? 'Show less'.tr
                    : 'Show {0} more'.trf([items.length - _advisoryPreviewCount]),
              ),
            ),
          ),
      ],
    );
  }
}

/// Heading shared by every section of the pond page: a tinted icon tile, the
/// title, and an optional trailing widget (a timestamp, an edit button).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
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
        Icon(
          Icons.location_on,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
      ReadingStatus.normal => 'All readings are within a healthy range.'.tr,
      ReadingStatus.warning =>
        'One or more readings are drifting outside the healthy range.'.tr,
      ReadingStatus.critical => 'One or more readings need attention now.'.tr,
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(status.icon, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pond status: {0}'.trf([status.label]),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
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
      'Updated {0}'.trf([_relativeTime(timestamp)]),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'just now'.tr;
    if (diff.inMinutes < 60) return '{0}m ago'.trf([diff.inMinutes]);
    if (diff.inHours < 24) return '{0}h ago'.trf([diff.inHours]);
    return '{0}d ago'.trf([diff.inDays]);
  }
}
