import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/auth_service.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/status_badge.dart';
import 'pond_dashboard_screen.dart';
import 'pond_list_screen.dart';

/// Screens ≥1024px wide (Material's documented desktop/web threshold) get
/// a persistent sidebar + detail-pane layout instead of the mobile
/// list -> full-screen-dashboard push flow.
const double kWideLayoutBreakpoint = 1024;

/// Root screen: picks the mobile push-navigation flow or the wide
/// sidebar/detail-pane shell based on available width.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _cache = PondSnapshotCache();
  Pond? _selectedPond;

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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      _cache.discard(pond.id);
      context.read<PondProvider>().removePond(pond.id);
      if (_selectedPond?.id == pond.id) {
        setState(() => _selectedPond = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ponds = context.watch<PondProvider>().ponds;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kWideLayoutBreakpoint) {
          return const PondListScreen();
        }

        var selected = _selectedPond;
        if (selected != null && !ponds.any((p) => p.id == selected!.id)) {
          selected = null;
        }
        selected ??= ponds.isEmpty ? null : ponds.first;

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PondSidebar(
                ponds: ponds,
                selectedId: selected?.id,
                statusFor: (pond) => overallStatus(_cache.snapshotFor(pond).readings),
                onSelect: (pond) => setState(() => _selectedPond = pond),
                onAdd: () => _addPond(context),
                onRename: (pond) => _renamePond(context, pond),
                onEditLocation: (pond) => _editLocation(context, pond),
                onRemove: (pond) => _removePond(context, pond),
                onRefreshAll: () => setState(() => _cache.refreshAll(ponds)),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? const _NoPondSelected()
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: ChangeNotifierProvider<DashboardProvider>(
                            key: ValueKey(selected.id),
                            create: (_) => DashboardProvider(pond: selected!),
                            child: PondDashboardBody(pond: selected, showHeader: true),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PondSidebar extends StatelessWidget {
  const _PondSidebar({
    required this.ponds,
    required this.selectedId,
    required this.statusFor,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onEditLocation,
    required this.onRemove,
    required this.onRefreshAll,
  });

  final List<Pond> ponds;
  final String? selectedId;
  final ReadingStatus Function(Pond) statusFor;
  final ValueChanged<Pond> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<Pond> onRename;
  final ValueChanged<Pond> onEditLocation;
  final ValueChanged<Pond> onRemove;
  final VoidCallback onRefreshAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 280,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.sm, AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.water_drop, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('IsdaSafe', style: theme.textTheme.titleLarge)),
                  IconButton(
                    onPressed: onRefreshAll,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh all ponds',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add pond'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            Expanded(
              child: ponds.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No ponds yet. Add one to get started.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: ponds.length,
                      itemBuilder: (context, index) {
                        final pond = ponds[index];
                        return StaggeredEntrance(
                          index: index,
                          child: _SidebarPondTile(
                            pond: pond,
                            selected: pond.id == selectedId,
                            status: statusFor(pond),
                            onTap: () => onSelect(pond),
                            onRename: () => onRename(pond),
                            onEditLocation: () => onEditLocation(pond),
                            onRemove: () => onRemove(pond),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            const _AccountSection(),
          ],
        ),
      ),
    );
  }
}

/// Persistent account row at the bottom of the sidebar — avatar (Google
/// photo when available, else an initial-letter placeholder), name, and
/// email, tapping opens a menu with Sign out. Replaces the old bare logout
/// icon that used to sit in the header.
class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  late final _profileFuture = AuthService.fetchCurrentProfile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = AuthService.currentUser;

    return FutureBuilder<({String fullName, String email, String? photoUrl})?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        // Falls back to the synchronously-available session data while the
        // `profiles` fetch (needed for photo_url) is still in flight, so the
        // row shows a name/email immediately instead of flashing empty.
        final fallbackName = (currentUser?.userMetadata?['full_name'] as String?) ?? '';
        final fallbackEmail = currentUser?.email ?? '';
        final fullName = (profile?.fullName.isNotEmpty ?? false) ? profile!.fullName : fallbackName;
        final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : fallbackEmail;
        final photoUrl = profile?.photoUrl;
        final displayName = fullName.isNotEmpty ? fullName : email;
        final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

        return PopupMenuButton<String>(
          tooltip: 'Account',
          offset: const Offset(0, -8),
          onSelected: (value) {
            if (value == 'signOut') AuthService.signOut();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'signOut', child: Text('Sign out')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary,
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                  child: photoUrl == null
                      ? Text(initial, style: TextStyle(color: theme.colorScheme.onPrimary))
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (email.isNotEmpty && email != displayName)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.more_vert, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarPondTile extends StatelessWidget {
  const _SidebarPondTile({
    required this.pond,
    required this.selected,
    required this.status,
    required this.onTap,
    required this.onRename,
    required this.onEditLocation,
    required this.onRemove,
  });

  final Pond pond;
  final bool selected;
  final ReadingStatus status;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditLocation;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = status.colorOf(context);
    final onSelectedColor = theme.colorScheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: dotColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    pond.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? onSelectedColor : null,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Pond options',
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: selected ? onSelectedColor : theme.colorScheme.onSurfaceVariant,
                  ),
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
          ),
        ),
      ),
    );
  }
}

class _NoPondSelected extends StatelessWidget {
  const _NoPondSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.water_drop_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: AppSpacing.md),
          Text('Select a pond to view its dashboard', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
