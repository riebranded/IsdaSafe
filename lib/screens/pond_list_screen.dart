import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/pond_provider.dart';
import '../services/auth_service.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/pond_list_tile.dart';
import '../widgets/staggered_entrance.dart';
import 'pond_dashboard_screen.dart';

class PondListScreen extends StatefulWidget {
  const PondListScreen({super.key});

  @override
  State<PondListScreen> createState() => _PondListScreenState();
}

class _PondListScreenState extends State<PondListScreen> {
  final _cache = PondSnapshotCache();

  Future<void> _refreshAll(List<Pond> ponds) async {
    setState(() => _cache.refreshAll(ponds));
  }

  Future<void> _addPond(BuildContext context) async {
    final draft = await showAddPondDialog(context);
    if (draft != null && context.mounted) {
      context.read<PondProvider>().addPond(draft.name, latitude: draft.latitude, longitude: draft.longitude);
    }
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      _cache.discard(pond.id);
      context.read<PondProvider>().removePond(pond.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ponds = context.watch<PondProvider>().ponds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ponds'),
        actions: [
          IconButton(
            onPressed: () => _refreshAll(ponds),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all ponds',
          ),
          IconButton(
            onPressed: AuthService.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPond(context),
        icon: const Icon(Icons.add),
        label: const Text('Add pond'),
      ),
      body: ponds.isEmpty
          ? _EmptyPondList(onAddPond: () => _addPond(context))
          : RefreshIndicator(
              onRefresh: () => _refreshAll(ponds),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xxl + AppSpacing.xl,
                ),
                itemCount: ponds.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final pond = ponds[index];
                  final status = overallStatus(_cache.snapshotFor(pond).readings);
                  return StaggeredEntrance(
                    index: index,
                    child: PondListTile(
                      pond: pond,
                      status: status,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PondDashboardScreen(pond: pond)),
                      ),
                      onRename: () => _renamePond(context, pond),
                      onEditLocation: () => _editLocation(context, pond),
                      onRemove: () => _removePond(context, pond),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyPondList extends StatelessWidget {
  const _EmptyPondList({required this.onAddPond});

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
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
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
            FilledButton.icon(
              onPressed: onAddPond,
              icon: const Icon(Icons.add),
              label: const Text('Add your first pond'),
            ),
          ],
        ),
      ),
    );
  }
}
