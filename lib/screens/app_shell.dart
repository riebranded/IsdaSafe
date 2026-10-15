import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../models/feeding_recommendation.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../providers/notification_provider.dart';
import '../providers/pond_chat_provider.dart';
import '../providers/pond_provider.dart';
import '../services/auth_service.dart';
import '../services/pond_snapshot_cache.dart';
import '../services/usb_sensor/device_claim.dart';
import '../services/usb_sensor/usb_sensor_hub.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../services/recommendation_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/add_pond_flow.dart';
import '../widgets/app_tour.dart';
import '../widgets/notification_toast.dart';
import '../widgets/pond_chat_sheet.dart';
import '../widgets/status_badge.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'notifications_screen.dart';
import 'pond_map_screen.dart';
import 'settings_screen.dart';
import '../l10n/tr.dart';

enum _Destination {
  dashboard(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  map(label: 'Map', icon: Icons.map_outlined, selectedIcon: Icons.map),
  analytics(
    label: 'Analytics',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),
  devices(
    label: 'Devices',
    icon: Icons.sensors_outlined,
    selectedIcon: Icons.sensors,
  ),
  notifications(
    label: 'Notifications',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  );

  const _Destination({
    required String label,
    required this.icon,
    required this.selectedIcon,
  }) : _label = label;

  final String _label;
  String get label => _label.tr;
  final IconData icon;
  final IconData selectedIcon;
}

/// Width of the side panel (custom nav + its branding header) on wide layouts.
const double _railWidth = 280;

/// Root screen: a 6-destination shell (Dashboard/Map/Analytics/Devices/
/// Notifications/Settings) — a custom side-panel nav beside the content on
/// wide/web viewports, a bottom [NavigationBar] under it on narrow/phone
/// widths. On wide layouts the Dashboard nav item expands into one
/// sub-button per pond; tapping a pond (there or on a Dashboard card) shows
/// that pond's dashboard in an inline detail pane, so the side panel always
/// stays visible instead of a full-screen push covering it. All 6
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
  StreamSubscription? _incomingSub;

  /// What the guided tour spotlights. Each key sits on whichever variant
  /// (side panel or bottom bar / top bar) the current layout shows.
  final _tourNavKeys = {
    for (final d in _Destination.values) d: GlobalKey(debugLabel: 'tour-$d'),
  };
  final _tourNavBarKey = GlobalKey(debugLabel: 'tour-nav');
  final _tourAddPondKey = GlobalKey(debugLabel: 'tour-add-pond');
  final _tourAskAiKey = GlobalKey(debugLabel: 'tour-ask-ai');
  final _tourBellKey = GlobalKey(debugLabel: 'tour-bell');
  final _tourAccountKey = GlobalKey(debugLabel: 'tour-account');
  final _tourBrandKey = GlobalKey(debugLabel: 'tour-brand');
  final _tourTutorialKey = GlobalKey(debugLabel: 'tour-tutorial');

  @override
  void initState() {
    super.initState();
    // Announce results (e.g. pond verification) the moment they arrive, on
    // top of the unread badge and the Notifications list.
    _incomingSub = context.read<NotificationProvider>().incoming.listen(
      _showIncoming,
    );
    // Pond cards and status chips read the USB device's latest values
    // through [_cache]; redraw when a new reading arrives.
    UsbSensorHub.instance.addListener(_onLiveReading);
    PondReadingsStore.instance
      ..addListener(_onLiveReading)
      ..start();
    // A device's QR label scanned with the phone's camera opened the site:
    // offer to pair it now that the user is signed in.
    final claim = PendingClaimLink.take();
    if (claim != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openClaimLink(context, claim);
      });
    } else {
      // First sign-in on this device: walk the user through the app once.
      // It can be replayed any time from Settings.
      _autoStartTour();
    }
  }

  Future<void> _autoStartTour() async {
    if (!await AppTour.shouldAutoStart()) return;
    // Give the ponds a moment to load so the shell is in its final layout.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) _startTour();
  }

  void _goTo(_Destination d) {
    if (mounted) setState(() => _selectedIndex = d.index);
  }

  /// The guided tour of every destination and what can be done there.
  void _startTour() {
    if (AppTour.isShowing) return;
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    AppTour.start(context, [
      TourStep(
        target: _tourBrandKey,
        icon: Icons.waving_hand_outlined,
        title: 'Welcome to Isda Safe'.tr,
        body:
            'Isda Safe watches your fish ponds\' water around the clock with an IsdaSafe sensor device, warns you when something drifts out of range and tells you what to do about it. This short tour shows where everything is.'
                .tr,
        onEnter: () => _goTo(_Destination.dashboard),
      ),
      TourStep(
        target: _tourNavBarKey,
        icon: Icons.explore_outlined,
        title: 'Getting around'.tr,
        body: isWide
            ? 'This side panel takes you to every part of the app. Your ponds are listed under Dashboard with a colored status dot, and your account is at the bottom.'
                  .tr
            : 'The bar at the bottom takes you to every part of the app. Notifications and your profile are at the top.'
                  .tr,
      ),
      TourStep(
        target: _tourNavKeys[_Destination.dashboard],
        icon: Icons.dashboard_outlined,
        title: 'Dashboard'.tr,
        body:
            'All your ponds at a glance. Each card shows the latest readings and a Normal, Warning or Critical status.'
                .tr,
        points: [
          'Tap a pond to open its own dashboard: latest readings, trends, water quality recommendations and possible risks.'
              .tr,
          'Plan feeding with an AI feeding schedule for the fish species you raise, and see which species suit the pond.'
              .tr,
          'Use a pond\'s three-dot menu to rename it, edit its location or remove it.'
              .tr,
        ],
        onEnter: () => _goTo(_Destination.dashboard),
      ),
      TourStep(
        target: _tourAddPondKey,
        icon: Icons.add,
        title: 'Add a pond'.tr,
        body: 'Start here to register a new pond.'.tr,
        points: [
          'Name it and pin where it is on the map.'.tr,
          'We verify the pond from satellite imagery (or your photos for in-house tanks) and notify you.'
              .tr,
          'Once verified, pair an IsdaSafe device by scanning its QR label, then add your fish species.'
              .tr,
        ],
        onEnter: () => _goTo(_Destination.dashboard),
      ),
      TourStep(
        target: _tourAskAiKey,
        icon: Icons.auto_awesome,
        title: 'Ask AI'.tr,
        body:
            'Chat with the pond assistant about a pond. It reads the pond\'s latest readings and feeding plan, and answers in your chosen language.'
                .tr,
        onEnter: () => _goTo(_Destination.dashboard),
      ),
      TourStep(
        target: _tourNavKeys[_Destination.map],
        icon: Icons.map_outlined,
        title: 'Map'.tr,
        body:
            'Every pond pinned on one map, colored by its status. Tap a marker to see that pond\'s readings.'
                .tr,
        onEnter: () => _goTo(_Destination.map),
      ),
      TourStep(
        target: _tourNavKeys[_Destination.analytics],
        icon: Icons.analytics_outlined,
        title: 'Analytics'.tr,
        body: 'Dig into a pond\'s history.'.tr,
        points: [
          'Switch between ponds with the pond selector.'.tr,
          'Individual trends: a chart per metric over the timeframe you pick.'
              .tr,
          'Individual readings: every reading the device sent, in a table.'.tr,
        ],
        onEnter: () => _goTo(_Destination.analytics),
      ),
      TourStep(
        target: _tourNavKeys[_Destination.devices],
        icon: Icons.sensors_outlined,
        title: 'Devices'.tr,
        body: 'Your IsdaSafe sensor devices.'.tr,
        points: [
          'Choose a device to see where it is now and how much it has measured.'
              .tr,
          'Its map shows a numbered pin for every pond it has been in, with each visit\'s complete readings.'
              .tr,
          'Connect a device to WiFi and refresh to see its latest location.'.tr,
        ],
        onEnter: () => _goTo(_Destination.devices),
      ),
      TourStep(
        target: isWide
            ? _tourNavKeys[_Destination.notifications]
            : _tourBellKey,
        icon: Icons.notifications_outlined,
        title: 'Notifications'.tr,
        body: 'Alerts and updates about your ponds and devices.'.tr,
        points: [
          'Warnings when a reading drifts outside the healthy range.'.tr,
          'Pond verification results, photo requests and device transfer requests, with a button to act on them.'
              .tr,
          'The badge counts unread alerts; mark them all as read in one tap.'
              .tr,
        ],
        onEnter: () =>
            _goTo(isWide ? _Destination.notifications : _Destination.dashboard),
      ),
      TourStep(
        target: _tourNavKeys[_Destination.settings],
        icon: Icons.settings_outlined,
        title: 'Settings'.tr,
        body: 'Make the app yours.'.tr,
        points: [
          'Edit your name, phone number, email and password.'.tr,
          'Switch the language between English and Tagalog, and pick a light or dark look.'
              .tr,
          'Turn push notifications and SMS alerts on or off.'.tr,
          'Read the legal documents, sign out or delete your account.'.tr,
        ],
        onEnter: () => _goTo(_Destination.settings),
      ),
      TourStep(
        target: _tourAccountKey,
        icon: Icons.account_circle_outlined,
        title: 'Your account'.tr,
        body: isWide
            ? 'Your name and email. Tap here to sign out.'.tr
            : 'Tap your picture to open Settings.'.tr,
        onEnter: () => _goTo(_Destination.settings),
      ),
      TourStep(
        target: _tourTutorialKey,
        icon: Icons.celebration_outlined,
        title: 'You\'re all set!'.tr,
        body:
            'Start by adding your first pond. You can replay this tour any time from Settings → Help → Tutorial.'
                .tr,
        onEnter: () => _goTo(_Destination.settings),
      ),
    ], onFinish: () => _goTo(_Destination.dashboard));
  }

  void _onLiveReading() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UsbSensorHub.instance.removeListener(_onLiveReading);
    PondReadingsStore.instance
      ..removeListener(_onLiveReading)
      ..stop();
    _incomingSub?.cancel();
    super.dispose();
  }

  void _showIncoming(AppNotification notification) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final (icon, color) = notificationVisual(context, notification);
    final pondId = notification.pondId;
    // "Photos needed" goes straight to the photo modal, "pond verified" to
    // pairing a device; everything else opens the Notifications list.
    final wantsPhotos =
        notification.type == 'pond_needs_photos' && pondId != null;
    final wantsDevice = notification.type == 'pond_verified' && pondId != null;
    // Someone asked for one of our devices; or one was transferred to us.
    final wantsTransferAnswer = notification.type == 'device_transfer_request';
    final wantsPondForDevice = notification.isDeviceTransferredToUs;

    void open() {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (wantsPhotos) {
        openAddPhotosForPond(context, pondId);
      } else if (wantsDevice) {
        context.read<NotificationProvider>().markRead(notification.id);
        openPairDeviceForPond(context, pondId);
      } else if (wantsTransferAnswer) {
        context.read<NotificationProvider>().markRead(notification.id);
        openTransferRequest(context, notification.body);
      } else if (wantsPondForDevice) {
        context.read<NotificationProvider>().markRead(notification.id);
        openAssignTransferredDevice(context, notification.body);
      } else if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) {
        // The wide layout has a Notifications destination; mobile pushes it
        // from the bell.
        setState(() => _selectedIndex = _Destination.notifications.index);
      } else {
        _openNotifications(context);
      }
    }

    // The pop-up is the card itself (see NotificationToast), so the SnackBar
    // chrome is stripped away.
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        showCloseIcon: false,
        content: NotificationToast(
          icon: icon,
          color: color,
          title: notification.title.tr,
          message: notification.body,
          actionLabel: wantsPhotos
              ? 'Add photos'.tr
              : wantsDevice
              ? 'Pair a device'.tr
              : wantsTransferAnswer
              ? 'Answer'.tr
              : wantsPondForDevice
              ? 'Choose a pond'.tr
              : 'View'.tr,
          onAction: open,
          onClose: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }

  /// Bottom nav destinations on mobile — Notifications is intentionally
  /// excluded; it's reached via the greeting bar's bell icon instead.
  static const List<_Destination> _bottomDestinations = [
    _Destination.dashboard,
    _Destination.map,
    _Destination.analytics,
    _Destination.devices,
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

  Future<void> _addPond(BuildContext context) => runAddPondFlow(context);

  /// Opens the assistant for the pond being viewed, or — from the pond list —
  /// for the only pond, or the one the user picks.
  Future<void> _openChat(
    BuildContext context,
    List<Pond> ponds,
    String? selectedPondId,
  ) async {
    if (ponds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add a pond first to chat about it.'.tr)),
      );
      return;
    }
    Pond? pond = ponds.where((p) => p.id == selectedPondId).firstOrNull;
    pond ??= ponds.length == 1 ? ponds.first : await _pickPond(context, ponds);
    if (pond == null || !context.mounted) return;

    final target = pond;
    await showPondChat(
      context,
      pond: target,
      contextBuilder: () => buildPondChatContext(
        target,
        readings: _cache.snapshotFor(target)?.readings,
        feeding: {
          for (final name in target.speciesNames)
            if (RecommendationCache.instance.feeding(target.id, name)
                case final FeedingRecommendation r)
              name: r,
        },
      ),
    );
  }

  Future<Pond?> _pickPond(BuildContext context, List<Pond> ponds) {
    return showModalBottomSheet<Pond>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Which pond?'.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final pond in ponds)
              ListTile(
                key: ValueKey('chat-pond-${pond.id}'),
                leading: const Icon(Icons.water_drop_outlined),
                title: Text(pond.name),
                trailing: const Icon(Icons.auto_awesome, size: 18),
                onTap: () => Navigator.of(context).pop(pond),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens Notifications as its own page (from the mobile greeting bar's
  /// bell). On mobile it isn't a bottom-nav tab, so it's a pushed route with
  /// its own back button rather than an [IndexedStack] switch.
  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Notifications'.tr)),
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
    final selectedPondId = ponds.any((p) => p.id == _selectedPondId)
        ? _selectedPondId
        : null;

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
            DevicesScreen(active: _selectedIndex == _Destination.devices.index),
            NotificationsScreen(cache: _cache),
            SettingsScreen(
              onStartTour: _startTour,
              tutorialKey: _tourTutorialKey,
            ),
          ],
        );

        return Scaffold(
          // Wide/web: no top bar (the full-height side panel is the header).
          // Mobile: a greeting bar with the user's avatar (top-left) and a
          // notification bell (top-right) that opens the Notifications page.
          appBar: isWide
              ? null
              : _MobileTopBar(
                  key: _tourBrandKey,
                  addPondKey: _tourAddPondKey,
                  bellKey: _tourBellKey,
                  avatarKey: _tourAccountKey,
                  onOpenProfile: () => setState(
                    () => _selectedIndex = _Destination.settings.index,
                  ),
                  onOpenNotifications: () => _openNotifications(context),
                  onAddPond: _selectedIndex == 0
                      ? () => _addPond(context)
                      : null,
                ),
          floatingActionButton: _selectedIndex == 0
              ? FloatingActionButton.extended(
                  key: _tourAskAiKey,
                  onPressed: () => _openChat(context, ponds, selectedPondId),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text('Ask AI'.tr),
                  tooltip: 'Ask the pond assistant'.tr,
                )
              : null,
          body: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SidePanel(
                      key: _tourNavBarKey,
                      navKeys: _tourNavKeys,
                      brandKey: _tourBrandKey,
                      accountKey: _tourAccountKey,
                      ponds: ponds,
                      selectedIndex: _selectedIndex,
                      selectedPondId: selectedPondId,
                      statusFor: (pond) => switch (_cache.snapshotFor(pond)) {
                        final snapshot? => overallStatus(snapshot.readings),
                        null => null,
                      },
                      onSelectDestination: (index) => setState(() {
                        _selectedIndex = index;
                        // Tapping the Dashboard button itself returns to the
                        // pond overview list; pond sub-buttons pick a pond.
                        if (index == 0) _selectedPondId = null;
                      }),
                      onSelectPond: _selectPond,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_selectedIndex == 0)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.md,
                                AppSpacing.lg,
                                0,
                              ),
                              child: Row(
                                children: [
                                  if (selectedPondId == null &&
                                      ponds.isNotEmpty)
                                    PondsHeader(count: ponds.length),
                                  const Spacer(),
                                  FilledButton.icon(
                                    key: _tourAddPondKey,
                                    onPressed: () => _addPond(context),
                                    icon: const Icon(Icons.add),
                                    label: Text('Add pond'.tr),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(child: content),
                        ],
                      ),
                    ),
                  ],
                )
              : content,
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  key: _tourNavBarKey,
                  selectedIndex: _bottomNavIndex,
                  onDestinationSelected: (index) => setState(
                    () => _selectedIndex = _bottomDestinations[index].index,
                  ),
                  destinations: [
                    for (final d in _bottomDestinations)
                      KeyedSubtree(
                        key: _tourNavKeys[d],
                        child: NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                        ),
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
  const _MobileTopBar({
    super.key,
    required this.addPondKey,
    required this.bellKey,
    required this.avatarKey,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    this.onAddPond,
  });

  /// Spotlighted by the guided tour.
  final GlobalKey addPondKey;
  final GlobalKey bellKey;
  final GlobalKey avatarKey;

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;

  /// Shown as an "Add pond" button in the top right when non-null (Dashboard only).
  final VoidCallback? onAddPond;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<_MobileTopBar> createState() => _MobileTopBarState();
}

class _MobileTopBarState extends State<_MobileTopBar> {
  late Future<({String fullName, String email, String? photoUrl})?>
  _profileFuture = AuthService.fetchCurrentProfile();
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    // Refetches on every auth event, including the `userUpdated` fired by
    // Settings' "Edit name" — this widget stays mounted for the app's whole
    // lifetime (behind an IndexedStack), so it'd otherwise never see a
    // rename made elsewhere until the app restarts.
    _authSub = AuthService.onAuthStateChange.listen((_) {
      setState(() {
        _profileFuture = AuthService.fetchCurrentProfile();
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning'.tr;
    if (hour < 18) return 'Good afternoon'.tr;
    return 'Good evening'.tr;
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
        final email = (profile?.email.isNotEmpty ?? false)
            ? profile!.email
            : (currentUser?.email ?? '');
        final photoUrl = profile?.photoUrl;
        // First name for the greeting; fall back to the email, then a neutral word.
        final displayName = fullName.isNotEmpty
            ? fullName.split(' ').first
            : (email.isNotEmpty ? email : 'there');
        final initialSource = fullName.isNotEmpty ? fullName : email;
        final initial = initialSource.isNotEmpty
            ? initialSource[0].toUpperCase()
            : '?';

        return AppBar(
          toolbarHeight: 72,
          titleSpacing: AppSpacing.md,
          leadingWidth: 60,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: GestureDetector(
              key: widget.avatarKey,
              onTap: widget.onOpenProfile,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primary,
                backgroundImage: photoUrl != null
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null
                    ? Text(
                        initial,
                        style: TextStyle(color: theme.colorScheme.onPrimary),
                      )
                    : null,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _greeting,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (widget.onAddPond != null)
              IconButton.filledTonal(
                key: widget.addPondKey,
                onPressed: widget.onAddPond,
                icon: const Icon(Icons.add),
                tooltip: 'Add pond'.tr,
              ),
            IconButton(
              key: widget.bellKey,
              onPressed: widget.onOpenNotifications,
              icon: _UnreadBadge(
                count: context.watch<NotificationProvider>().unreadCount,
                child: const Icon(Icons.notifications_outlined),
              ),
              tooltip: 'Notifications'.tr,
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
    super.key,
    required this.navKeys,
    required this.brandKey,
    required this.accountKey,
    required this.ponds,
    required this.selectedIndex,
    required this.selectedPondId,
    required this.statusFor,
    required this.onSelectDestination,
    required this.onSelectPond,
  });

  /// Spotlighted by the guided tour.
  final Map<_Destination, GlobalKey> navKeys;
  final GlobalKey brandKey;
  final GlobalKey accountKey;

  final List<Pond> ponds;
  final int selectedIndex;
  final String? selectedPondId;

  /// Null for ponds without readings (no device paired yet).
  final ReadingStatus? Function(Pond) statusFor;
  final ValueChanged<int> onSelectDestination;
  final ValueChanged<Pond> onSelectPond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadNotifications = context
        .watch<NotificationProvider>()
        .unreadCount;

    return SizedBox(
      width: _railWidth,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: brandKey,
              // The inner padding keeps the branding where it was while
              // giving the tap target some room around it.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl - AppSpacing.xs,
                AppSpacing.lg - AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm - AppSpacing.xs,
              ),
              // Tapping the logo or name goes home to the pond overview.
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  key: const ValueKey('brand-home'),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => onSelectDestination(0),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Image.asset(
                            'assets/branding/logo.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Isda Safe'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, d) in _Destination.values.indexed) ...[
                      KeyedSubtree(
                        key: navKeys[d],
                        child: _NavItem(
                          key: ValueKey('nav-${d.name}'),
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: d.label,
                          badgeCount: d == _Destination.notifications
                              ? unreadNotifications
                              : 0,
                          selected: selectedIndex == index,
                          onTap: () => onSelectDestination(index),
                        ),
                      ),
                      // Pond sub-buttons only appear while Dashboard is the
                      // active destination.
                      if (d == _Destination.dashboard && selectedIndex == 0)
                        for (final pond in ponds)
                          _PondSubButton(
                            key: ValueKey('pond-nav-${pond.id}'),
                            pond: pond,
                            status: statusFor(pond),
                            selected:
                                selectedIndex == 0 && selectedPondId == pond.id,
                            onTap: () => onSelectPond(pond),
                          ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            KeyedSubtree(key: accountKey, child: const _AccountSection()),
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
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                _UnreadBadge(
                  count: badgeCount,
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 24,
                    color: fg,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Tagalog labels ("Mga Notification") and large system fonts don't
                // fit the fixed-width rail on one line.
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurface,
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

  /// Null for a pond without readings (no device paired): grey dot.
  final ReadingStatus? status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSelectedColor = theme.colorScheme.onSecondaryContainer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 1, AppSpacing.md, 1),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color:
                      status?.colorOf(context) ??
                      Theme.of(context).colorScheme.outline,
                ),
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
  late Future<({String fullName, String email, String? photoUrl})?>
  _profileFuture = AuthService.fetchCurrentProfile();
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    // See _MobileTopBarState's identical subscription for why.
    _authSub = AuthService.onAuthStateChange.listen((_) {
      setState(() {
        _profileFuture = AuthService.fetchCurrentProfile();
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

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
        final fallbackName =
            (currentUser?.userMetadata?['full_name'] as String?) ?? '';
        final fallbackEmail = currentUser?.email ?? '';
        final fullName = (profile?.fullName.isNotEmpty ?? false)
            ? profile!.fullName
            : fallbackName;
        final email = (profile?.email.isNotEmpty ?? false)
            ? profile!.email
            : fallbackEmail;
        final photoUrl = profile?.photoUrl;
        final displayName = fullName.isNotEmpty ? fullName : email;
        final initial = displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : '?';

        return PopupMenuButton<String>(
          tooltip: 'Account'.tr,
          offset: const Offset(0, -8),
          onSelected: (value) {
            if (value == 'signOut') AuthService.signOut();
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'signOut', child: Text('Sign out'.tr)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary,
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null
                      ? Text(
                          initial,
                          style: TextStyle(color: theme.colorScheme.onPrimary),
                        )
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (email.isNotEmpty && email != displayName)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.more_vert,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wraps [child] with a small count badge when [count] is above zero.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 9 ? '9+' : '$count'),
      child: child,
    );
  }
}
