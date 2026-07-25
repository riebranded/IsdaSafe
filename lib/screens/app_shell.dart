import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/pond_provider.dart';
import '../services/auth_service.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/pond_dialogs.dart';
import '../widgets/status_badge.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'notifications_screen.dart';
import 'pond_map_screen.dart';
import 'settings_screen.dart';

enum _Destination {
  dashboard(label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  map(label: 'Map', icon: Icons.map_outlined, selectedIcon: Icons.map),
  analytics(label: 'Analytics', icon: Icons.analytics_outlined, selectedIcon: Icons.analytics),
  notifications(
    label: 'Notifications',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications,
  ),
  settings(label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings);

  const _Destination({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Width of the side panel (custom nav + its branding header) on wide layouts.
const double _railWidth = 280;

/// Root screen: a 5-destination shell (Dashboard/Map/Analytics/
/// Notifications/Settings) — a custom side-panel nav beside the content on
/// wide/web viewports, a bottom [NavigationBar] under it on narrow/phone
/// widths. On wide layouts the Dashboard nav item expands into one
/// sub-button per pond; tapping a pond (there or on a Dashboard card) shows
/// that pond's dashboard in an inline detail pane, so the side panel always
/// stays visible instead of a full-screen push covering it. All 5
/// destinations stay mounted via [IndexedStack] so switching never loses a
/// destination's own scroll position or in-progress selection.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _cache = PondSnapshotCache();
  var _selectedIndex = 0;

  /// Bottom nav destinations on mobile — Notifications is intentionally
  /// excluded; it's reached via the greeting bar's bell icon instead.
  static const List<_Destination> _bottomDestinations = [
    _Destination.dashboard,
    _Destination.map,
    _Destination.analytics,
    _Destination.settings,
  ];

  /// Selected index expressed as a position within [_bottomDestinations]
  /// (falls back to Dashboard for any destination not in the bottom bar).
  int get _bottomNavIndex {
    final i = _bottomDestinations.indexOf(_Destination.values[_selectedIndex]);
    return i < 0 ? 0 : i;
  }

  /// The pond whose dashboard is shown in the wide-layout detail pane, chosen
  /// via a Dashboard sub-button or a Dashboard card. Null until one is picked.
  String? _selectedPondId;

  Future<void> _addPond(BuildContext context) async {
    final draft = await showAddPondDialog(context);
    if (draft != null && context.mounted) {
      context.read<PondProvider>().addPond(draft.name, latitude: draft.latitude, longitude: draft.longitude);
    }
  }

  /// Opens Notifications as its own page (from the mobile greeting bar's
  /// bell). On mobile it isn't a bottom-nav tab, so it's a pushed route with
  /// its own back button rather than an [IndexedStack] switch.
  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: NotificationsScreen(cache: _cache),
        ),
      ),
    );
  }

  /// Jumps to the Dashboard destination and shows [pond] in its detail pane.
  void _selectPond(Pond pond) {
    setState(() {
      _selectedIndex = 0;
      _selectedPondId = pond.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ponds = context.watch<PondProvider>().ponds;
    // Drop a stale selection if the pond was removed.
    final selectedPondId = ponds.any((p) => p.id == _selectedPondId) ? _selectedPondId : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint;

        final content = IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardScreen(
              cache: _cache,
              showDetailPane: isWide,
              selectedPondId: selectedPondId,
              onSelectPond: _selectPond,
              onClearPond: () => setState(() => _selectedPondId = null),
            ),
            PondMapScreen(cache: _cache),
            AnalyticsScreen(cache: _cache),
            NotificationsScreen(cache: _cache),
            const SettingsScreen(),
          ],
        );

        return Scaffold(
          // Wide/web: no top bar (the full-height side panel is the header).
          // Mobile: a greeting bar with the user's avatar (top-left) and a
          // notification bell (top-right) that opens the Notifications page.
          appBar: isWide
              ? null
              : _MobileTopBar(
                  onOpenProfile: () => setState(() => _selectedIndex = _Destination.settings.index),
                  onOpenNotifications: () => _openNotifications(context),
                ),
          floatingActionButton: _selectedIndex == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _addPond(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add pond'),
                )
              : null,
          body: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SidePanel(
                      ponds: ponds,
                      selectedIndex: _selectedIndex,
                      selectedPondId: selectedPondId,
                      statusFor: (pond) => overallStatus(_cache.snapshotFor(pond).readings),
                      onSelectDestination: (index) => setState(() {
                        _selectedIndex = index;
                        // Tapping the Dashboard button itself returns to the
                        // pond overview list; pond sub-buttons pick a pond.
                        if (index == 0) _selectedPondId = null;
                      }),
                      onSelectPond: _selectPond,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _bottomNavIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = _bottomDestinations[index].index),
                  destinations: [
                    for (final d in _bottomDestinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Mobile top bar: a greeting with the user's avatar (top-left) and a
/// notification bell (top-right). Replaces the plain per-screen AppBar title.
class _MobileTopBar extends StatefulWidget implements PreferredSizeWidget {
  const _MobileTopBar({required this.onOpenProfile, required this.onOpenNotifications});

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<_MobileTopBar> createState() => _MobileTopBarState();
}

class _MobileTopBarState extends State<_MobileTopBar> {
  late final _profileFuture = AuthService.fetchCurrentProfile();

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<({String fullName, String email, String? photoUrl})?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final currentUser = AuthService.currentUser;
        final fullName = (profile?.fullName.isNotEmpty ?? false)
            ? profile!.fullName
            : (currentUser?.userMetadata?['full_name'] as String?) ?? '';
        final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : (currentUser?.email ?? '');
        final photoUrl = profile?.photoUrl;
        // First name for the greeting; fall back to the email, then a neutral word.
        final displayName = fullName.isNotEmpty
            ? fullName.split(' ').first
            : (email.isNotEmpty ? email : 'there');
        final initialSource = fullName.isNotEmpty ? fullName : email;
        final initial = initialSource.isNotEmpty ? initialSource[0].toUpperCase() : '?';

        return AppBar(
          toolbarHeight: 72,
          titleSpacing: AppSpacing.md,
          leadingWidth: 60,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: GestureDetector(
              onTap: widget.onOpenProfile,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primary,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Text(initial, style: TextStyle(color: theme.colorScheme.onPrimary))
                    : null,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_greeting, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(
                displayName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: widget.onOpenNotifications,
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        );
      },
    );
  }
}

/// The wide-layout left side panel: branding, the destination nav (with pond
/// sub-buttons nested under Dashboard), and the account row pinned at the
/// bottom.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.ponds,
    required this.selectedIndex,
    required this.selectedPondId,
    required this.statusFor,
    required this.onSelectDestination,
    required this.onSelectPond,
  });

  final List<Pond> ponds;
  final int selectedIndex;
  final String? selectedPondId;
  final ReadingStatus Function(Pond) statusFor;
  final ValueChanged<int> onSelectDestination;
  final ValueChanged<Pond> onSelectPond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: _railWidth,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.water_drop, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Text('IsdaSafe', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, d) in _Destination.values.indexed) ...[
                      _NavItem(
                        key: ValueKey('nav-${d.name}'),
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: d.label,
                        selected: selectedIndex == index,
                        onTap: () => onSelectDestination(index),
                      ),
                      // Pond sub-buttons only appear while Dashboard is the
                      // active destination.
                      if (d == _Destination.dashboard && selectedIndex == 0)
                        for (final pond in ponds)
                          _PondSubButton(
                            key: ValueKey('pond-nav-${pond.id}'),
                            pond: pond,
                            status: statusFor(pond),
                            selected: selectedIndex == 0 && selectedPondId == pond.id,
                            onTap: () => onSelectPond(pond),
                          ),
                    ],
                  ],
                ),
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

/// A top-level destination button styled like an extended NavigationRail item.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
      child: Material(
        color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(selected ? selectedIcon : icon, size: 24, color: fg),
                const SizedBox(width: AppSpacing.md),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pond, shown indented beneath the Dashboard nav item, with a status dot.
class _PondSubButton extends StatelessWidget {
  const _PondSubButton({
    super.key,
    required this.pond,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final Pond pond;
  final ReadingStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSelectedColor = theme.colorScheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 1, AppSpacing.md, 1),
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
                Icon(Icons.circle, size: 10, color: status.colorOf(context)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Persistent account row pinned to the bottom of the wide-layout side
/// panel — avatar (Google photo when available, else an initial-letter
/// placeholder), name, and email; tapping opens a menu with Sign out.
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
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
