import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../providers/dashboard_provider.dart';
import '../models/app_notification.dart';
import '../providers/notification_provider.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/add_pond_flow.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/reading_grid.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/status_badge.dart';
import 'pond_dashboard_screen.dart';
import '../l10n/tr.dart';

/// Shown whenever a Supabase write (rename/move/remove/species/create) fails
/// — the in-memory list has already rolled back to match, so this is purely
/// informational.
void _showSaveError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Couldn\'t save changes. Check your connection and try again.'.tr,
      ),
    ),
  );
}

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
    if (name == null || !context.mounted) return;

    final ok = await context.read<PondProvider>().renamePond(pond.id, name);
    if (!ok && context.mounted) _showSaveError(context);
  }

  Future<void> _editLocation(BuildContext context, Pond pond) async {
    final location = await showEditLocationDialog(
      context,
      initialLatitude: pond.latitude ?? kDefaultMapCenter.latitude,
      initialLongitude: pond.longitude ?? kDefaultMapCenter.longitude,
    );
    if (location == null || !context.mounted) return;

    final ok = await context.read<PondProvider>().setLocation(
      pond.id,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    if (!ok && context.mounted) _showSaveError(context);
  }

  Future<void> _removePond(BuildContext context, Pond pond) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove pond'.tr),
        content: Text('Remove "{0}"? This cannot be undone.'.trf([pond.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await context.read<PondProvider>().removePond(pond.id);
    if (ok) {
      widget.cache.discard(pond.id);
    } else if (context.mounted) {
      _showSaveError(context);
    }
  }

  /// A just-verified pond with no species yet, paired with the unread
  /// notification that announced it — that notification is what makes the
  /// prompt appear (and dismissing the prompt marks it read), so ponds that
  /// were verified long ago and never got species aren't nagged about.
  (Pond, AppNotification)? _speciesPrompt(
    List<Pond> ponds,
    List<AppNotification> notifications,
  ) {
    for (final n in notifications) {
      if (n.isRead || n.type != 'pond_verified' || n.pondId == null) continue;
      for (final pond in ponds) {
        if (pond.id == n.pondId && pond.speciesNames.isEmpty) return (pond, n);
      }
    }
    return null;
  }

  Future<void> _addSpecies(
    BuildContext context,
    Pond pond,
    AppNotification notification,
  ) async {
    final provider = context.read<PondProvider>();
    final notifications = context.read<NotificationProvider>();
    final species = await showSelectSpeciesDialog(context);
    // Dismissed without choosing: keep the prompt so they can come back to it.
    if (species == null || !context.mounted) return;
    final ok = await provider.setSpecies(pond.id, species);
    if (!context.mounted) return;
    if (!ok) {
      _showSaveError(context);
      return;
    }
    notifications.markRead(notification.id);
  }

  Future<void> _retryVerification(
    BuildContext context,
    List<Pond> ponds,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<PondProvider>();
    var allSent = true;
    for (final pond in ponds) {
      allSent = await provider.retryVerification(pond.id) && allSent;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          allSent
              ? 'Verification restarted. We\'ll notify you when it\'s done.'.tr
              : 'Couldn\'t restart verification. Check your connection and try again.'.tr,
        ),
      ),
    );
  }

  void _openPond(BuildContext context, Pond pond) {
    // Wide layout: select the pond so the inline detail pane shows it (the
    // side panel stays visible). Narrow layout: push the full-screen view.
    if (widget.showDetailPane && widget.onSelectPond != null) {
      widget.onSelectPond!(pond);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PondDashboardScreen(pond: pond)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pondProvider = context.watch<PondProvider>();
    final ponds = pondProvider.ponds;

    if (ponds.isEmpty && pondProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final needsPhotos = pondProvider.needsPhotosPonds;
    final retryable = [
      ...pondProvider.pendingPonds,
      ...pondProvider.failedPonds,
    ];
    // Everything not on the dashboard yet but on its way (or awaiting photos).
    final unverified = [...retryable, ...needsPhotos];
    final notifications = context.watch<NotificationProvider>().notifications;
    final prompt = _speciesPrompt(ponds, notifications);
    final banners = <Widget>[
      if (prompt != null)
        _SpeciesPromptBanner(
          pond: prompt.$1,
          onAdd: () => _addSpecies(context, prompt.$1, prompt.$2),
          onLater: () =>
              context.read<NotificationProvider>().markRead(prompt.$2.id),
        ),
      if (retryable.isNotEmpty)
        _VerificationBanner(
          pending: pondProvider.pendingPonds,
          failed: pondProvider.failedPonds,
          onRetry: () => _retryVerification(context, retryable),
        ),
    ];
    final banner = banners.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, b) in banners.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                b,
              ],
            ],
          );

    if (ponds.isEmpty) {
      return _EmptyDashboard(
        banner: banner,
        waitingForVerification: unverified.isNotEmpty,
        onAddPond: () => runAddPondFlow(context),
      );
    }

    // Wide layout: a selected pond takes over the content area (side panel
    // stays visible); otherwise the full-grid overview list. Narrow/mobile
    // gets the compact summary + one-row-readings design.
    if (widget.showDetailPane) {
      final selected = _selectedPond(ponds);
      if (selected != null) {
        return _PondDetailView(pond: selected, onBack: widget.onClearPond);
      }
      if (banner == null) return _pondList(ponds);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: banner,
          ),
          Expanded(child: _pondList(ponds)),
        ],
      );
    }

    return _mobileList(ponds, banner: banner);
  }

  Widget _mobileList(List<Pond> ponds, {Widget? banner}) {
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
          if (banner != null) ...[
            banner,
            const SizedBox(height: AppSpacing.lg),
          ],
          _StatusSummary(normal: normal, warning: warning, critical: critical),
          const SizedBox(height: AppSpacing.xl),
          PondsHeader(count: ponds.length),
          const SizedBox(height: AppSpacing.md),
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text('All ponds'.tr),
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

/// "Ponds" title with a count, heading the list of pond cards.
class PondsHeader extends StatelessWidget {
  const PondsHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Ponds'.tr,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile overview header: how many ponds are Normal / Warning / Critical.
class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.normal,
    required this.warning,
    required this.critical,
  });

  final int normal;
  final int warning;
  final int critical;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            count: normal,
            label: 'Normal'.tr,
            status: ReadingStatus.normal,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _SummaryTile(
            count: warning,
            label: 'Warning'.tr,
            status: ReadingStatus.warning,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _SummaryTile(
            count: critical,
            label: 'Critical'.tr,
            status: ReadingStatus.critical,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.count,
    required this.label,
    required this.status,
  });

  final int count;
  final String label;
  final ReadingStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.colorOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
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
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
                    tooltip: 'Pond options'.tr,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'location') onEditLocation();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'.tr),
                      ),
                      PopupMenuItem(
                        value: 'location',
                        child: Text('Edit location'.tr),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'.tr),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final type in MetricType.values)
                    Expanded(
                      child: _ReadingChip(
                        type: type,
                        value: readings[type]!.value,
                      ),
                    ),
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
        : 'No location set'.tr;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                    tooltip: 'Pond options'.tr,
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'location') onEditLocation();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'.tr),
                      ),
                      PopupMenuItem(
                        value: 'location',
                        child: Text('Edit location'.tr),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'.tr),
                      ),
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

/// Shown right after a pond is verified: the moment to ask which fish it holds
/// (used for feeding-time suggestions), rather than before it's even confirmed.
class _SpeciesPromptBanner extends StatelessWidget {
  const _SpeciesPromptBanner({
    required this.pond,
    required this.onAdd,
    required this.onLater,
  });

  final Pond pond;
  final VoidCallback onAdd;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified, color: scheme.onPrimaryContainer),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“{0}” is verified'.trf([pond.name]),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tell us which fish or shrimp it holds to get feeding-time suggestions.'.tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  TextButton(onPressed: onLater, child: Text('Later'.tr)),
                  FilledButton(
                    onPressed: onAdd,
                    child: Text('Add species'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tells the owner their not-yet-verified ponds aren't on the dashboard yet:
/// still being checked (with a retry in case it's stuck), or the check itself
/// failed. Rejected ponds aren't mentioned here — the notification explains.
class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({
    required this.pending,
    required this.failed,
    required this.onRetry,
  });

  final List<Pond> pending;
  final List<Pond> failed;
  final VoidCallback onRetry;

  String _names(List<Pond> ponds) =>
      ponds.length == 1 ? '“${ponds.first.name}”' : '{0} ponds'.trf([ponds.length]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFailed = failed.isNotEmpty;

    final title = hasFailed
        ? 'We couldn\'t finish verifying {0}'.trf([_names(failed)])
        : 'Verifying {0}…'.trf([_names(pending)]);
    final body = hasFailed
        ? 'A technical problem stopped the check. Retry to try again.'.tr
        : 'It will appear here once it\'s verified. We\'ll send you a notification when it is.'.tr;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasFailed ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hasFailed
                ? Icon(Icons.error_outline, color: scheme.onTertiaryContainer)
                : SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: hasFailed
                          ? scheme.onTertiaryContainer
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasFailed
                          ? scheme.onTertiaryContainer
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(hasFailed ? 'Retry'.tr : 'Taking long? Retry'.tr),
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
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({
    required this.onAddPond,
    this.banner,
    this.waitingForVerification = false,
  });

  final VoidCallback onAddPond;

  /// Shown above the empty state while ponds await verification.
  final Widget? banner;

  /// Swaps "No ponds yet" for wording that says a pond is on its way.
  final bool waitingForVerification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (banner != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: banner,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.water_drop_outlined,
                size: 44,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              waitingForVerification
                  ? 'Your pond is on its way'.tr
                  : 'No ponds yet'.tr,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              waitingForVerification
                  ? 'Verified ponds show up here with their live water quality.'.tr
                  : 'Add a pond to start tracking its water quality and\nsee which fish species it can support.'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAddPond,
              icon: const Icon(Icons.add),
              label: Text(
                waitingForVerification
                    ? 'Add another pond'.tr
                    : 'Add your first pond'.tr,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
