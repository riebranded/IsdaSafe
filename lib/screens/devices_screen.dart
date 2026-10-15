import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/tr.dart';
import '../models/trend_range.dart';
import '../services/device_location_history.dart';
import '../services/reading_days.dart';
import '../services/readings_pager.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/reading_history_table.dart';
import '../widgets/timeframe_picker.dart';

/// The Devices tab. It opens on a device chooser: one card per device the
/// account has (or had) with where it is now and how much it measured. Once
/// a device is chosen it's laid out like the Map tab — the map on the left
/// with a numbered pin per spot, and on the right a panel listing the ponds
/// it was in (each with all its visits). Tapping a pin pops up a card about
/// that spot; picking a pond (in the list or from that card) shows its
/// visits and complete readings under the map.
///
/// It stays mounted in the app shell, so it reloads whenever it becomes
/// [active] (a device may have been paired or moved meanwhile), and on
/// pull-to-refresh or the refresh button.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.active = true});

  /// Whether the tab is the one on screen.
  final bool active;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

/// A device and the ponds it was in.
class _Device {
  const _Device(this.id, this.places);

  final String id;

  /// Newest visit first.
  final List<_Place> places;

  _Place? get current => places.where((p) => p.isCurrent).firstOrNull;
  int get readingCount => places.fold(0, (sum, p) => sum + p.readingCount);
}

class _DevicesScreenState extends State<DevicesScreen> {
  Future<List<_Device>>? _devices;

  /// The chosen device; null shows the chooser.
  String? _deviceId;

  /// On a phone the map can be folded away to leave the room to the ponds.
  var _mapShown = true;

  /// The pond whose readings are shown under the map.
  String? _selectedKey;
  final _map = GlobalKey<_HistoryMapState>();

  @override
  void initState() {
    super.initState();
    if (widget.active) _reload();
  }

  @override
  void didUpdateWidget(DevicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  /// Reloads every device's history, staying on the chosen device and pond
  /// while they're still there.
  Future<void> _reload() {
    final devices = _loadDevices();
    setState(() {
      _devices = devices;
    });
    return devices.then((_) {}, onError: (_) {});
  }

  Future<List<_Device>> _loadDevices() async {
    final history = DeviceLocationHistory.instance;
    final ids = await history.devices();
    final devices = await Future.wait([
      for (final id in ids)
        history.stays(id).then((stays) => _Device(id, _Place.group(stays))),
    ]);
    if (mounted) {
      final chosen = devices.where((d) => d.id == _deviceId).firstOrNull;
      if (chosen == null) _deviceId = null;
      if (chosen == null || !chosen.places.any((p) => p.key == _selectedKey)) {
        _selectedKey = null;
      }
    }
    return devices;
  }

  void _chooseDevice(String? deviceId) => setState(() {
    _deviceId = deviceId;
    _selectedKey = null;
  });

  void _openPlace(_Place place) {
    _map.currentState?.focus(place);
    setState(() => _selectedKey = place.key);
  }

  void _closePlace() => setState(() => _selectedKey = null);

  @override
  Widget build(BuildContext context) {
    // Not opened yet: nothing to show (and no spinner animating off screen).
    if (_devices == null) return const SizedBox.shrink();
    return FutureBuilder<List<_Device>>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        // Scrollable so pull-to-refresh works on these too.
        Widget message(String text) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [_Message(text)],
          ),
        );
        if (snapshot.hasError) {
          return message(
            "Couldn't load the device history. Check your connection and try again."
                .tr,
          );
        }
        final devices = snapshot.data!;
        if (devices.isEmpty) {
          return message(
            'No device history yet. Locations appear here once a device sends a complete reading (every sensor) from a pond.'
                .tr,
          );
        }
        final device = devices.where((d) => d.id == _deviceId).firstOrNull;
        if (device == null) {
          return _DeviceChooser(
            devices: devices,
            onRefresh: _reload,
            onChoose: _chooseDevice,
          );
        }
        return _deviceView(device);
      },
    );
  }

  /// The chosen device: map, pond list, and the chosen pond's readings.
  Widget _deviceView(_Device device) {
    final places = device.places;
    final selected = places.where((p) => p.key == _selectedKey).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint;

        Widget detail(_Place place) => _PlaceDetail(
          key: ValueKey(place.key),
          place: place,
          onClose: _closePlace,
        );
        Widget panel({required bool showSelected, bool mapToggle = false}) =>
            _Panel(
              deviceId: device.id,
              onBack: () => _chooseDevice(null),
              onRefresh: _reload,
              mapShown: mapToggle ? _mapShown : null,
              onToggleMap: mapToggle
                  ? () => setState(() => _mapShown = !_mapShown)
                  : null,
              child: showSelected && selected != null
                  ? detail(selected)
                  : _PlaceList(
                      places: places,
                      selectedKey: selected?.key,
                      onRefresh: _reload,
                      onOpen: _openPlace,
                    ),
            );

        final located = [
          for (final p in places)
            if (p.hasLocation) p,
        ];
        // No map to show: the list, or the chosen pond's readings.
        if (!isMapViewSupported || located.isEmpty) {
          return panel(showSelected: true);
        }
        final map = _HistoryMap(
          key: _map,
          // A new map (and camera fit) per device.
          mapKey: ValueKey(device.id),
          places: located,
          selectedKey: selected?.key,
          onOpen: _openPlace,
        );

        // Wide: map on the left with the chosen pond's readings under it,
        // the pond list on the right (like the Map tab).
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: map),
                    if (selected != null) ...[
                      const Divider(height: 1),
                      SizedBox(
                        height: constraints.maxHeight * 0.5,
                        child: detail(selected),
                      ),
                    ],
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: 360, child: panel(showSelected: false)),
            ],
          );
        }
        // Narrow: map on top; under it the list, or the chosen pond's
        // readings.
        // A short map (that can be folded away) so the ponds below get most
        // of the screen.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_mapShown) ...[
              SizedBox(
                height: (constraints.maxHeight * 0.3).clamp(150.0, 240.0),
                child: map,
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: selected != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MapToggleBar(
                          shown: _mapShown,
                          onToggle: () =>
                              setState(() => _mapShown = !_mapShown),
                        ),
                        Expanded(child: detail(selected)),
                      ],
                    )
                  : panel(showSelected: false, mapToggle: true),
            ),
          ],
        );
      },
    );
  }
}

/// The first thing the tab shows: a card per device to choose from.
class _DeviceChooser extends StatelessWidget {
  const _DeviceChooser({
    required this.devices,
    required this.onRefresh,
    required this.onChoose,
  });

  final List<_Device> devices;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Choose a device'.tr,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh'.tr,
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Text(
                    'See every pond it has been in and the readings it took there.'
                        .tr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final device in devices)
                    _DeviceCard(
                      device: device,
                      onTap: () => onChoose(device.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final _Device device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final current = device.current;
    final latest = device.places.first;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.sensors, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device {0}'.trf([device.id]),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          current == null
                              ? Icons.location_off_outlined
                              : Icons.location_on,
                          size: 16,
                          color: current == null
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            current == null
                                ? 'Last in {0}'.trf([latest.label])
                                : 'Now in {0}'.trf([current.label]),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.places.length == 1 ? '1 pond'.tr : '{0} ponds'.trf([device.places.length])}'
                      ' · ${_readingsLabel(device.readingCount)}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pond (at one spot) the device was in, with every visit there — so a
/// pond the device came back to is one entry, not one per visit. [number]
/// is its order of first visit (1 = the first place the device went), used
/// to order the map's path; it isn't shown.
class _Place {
  _Place({required this.key, required this.stays, required this.number});

  final String key;

  /// Newest first.
  final List<DeviceStay> stays;
  final int number;

  DeviceStay get latest => stays.first;
  String get label => _pondLabel(latest);
  bool get isCurrent => latest.isCurrent;
  bool get hasLocation => latest.hasLocation;
  LatLng get position => LatLng(latest.latitude!, latest.longitude!);
  int get readingCount => stays.fold(0, (sum, s) => sum + s.readingCount);

  /// [stays] (newest first) grouped by pond and spot, newest visit first,
  /// numbered by first visit.
  static List<_Place> group(List<DeviceStay> stays) {
    final byKey = <String, List<DeviceStay>>{};
    for (final s in stays) {
      final key = s.pondId == null
          ? 'stay-${s.id}'
          : '${s.pondId}@${s.latitude?.toStringAsFixed(5)},${s.longitude?.toStringAsFixed(5)}';
      (byKey[key] ??= []).add(s);
    }
    final firstVisits = byKey.keys.toList()
      ..sort(
        (a, b) => byKey[a]!.last.startedAt.compareTo(byKey[b]!.last.startedAt),
      );
    return [
      for (final e in byKey.entries)
        _Place(
          key: e.key,
          stays: e.value,
          number: firstVisits.indexOf(e.key) + 1,
        ),
    ];
  }
}

/// The map: one numbered pin per spot (ponds within a few meters of each
/// other share a pin), joined in the order the device moved between them.
/// Tapping a pin pops up a [_SpotCard] about it; tapping the map closes it.
class _HistoryMap extends StatefulWidget {
  const _HistoryMap({
    super.key,
    required this.mapKey,
    required this.places,
    required this.selectedKey,
    required this.onOpen,
  });

  final Key mapKey;

  /// Each with a location.
  final List<_Place> places;
  final String? selectedKey;
  final ValueChanged<_Place> onOpen;

  @override
  State<_HistoryMap> createState() => _HistoryMapState();
}

class _HistoryMapState extends State<_HistoryMap> {
  GoogleMapController? _controller;

  /// A pond at the spot whose pop-up card is open.
  String? _popupKey;

  /// Moves the camera to [place].
  void focus(_Place place) {
    if (!place.hasLocation) return;
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(place.position, kFocusedMapZoom),
    );
  }

  /// Places within about 15 m of each other, together.
  List<List<_Place>> _spots() {
    const near = 0.00015;
    final spots = <List<_Place>>[];
    for (final place in [
      ...widget.places,
    ]..sort((a, b) => a.number.compareTo(b.number))) {
      final spot = spots.where((s) {
        final p = s.first.position;
        return (p.latitude - place.position.latitude).abs() < near &&
            (p.longitude - place.position.longitude).abs() < near;
      }).firstOrNull;
      spot == null ? spots.add([place]) : spot.add(place);
    }
    return spots;
  }

  void _fit(GoogleMapController controller, List<LatLng> points) {
    if (points.length < 2) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    if (north - south < 1e-6 && east - west < 1e-6) return;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots();
    final spotOf = {
      for (final spot in spots)
        for (final place in spot) place.key: spot,
    };

    // The device's path: every visit in order, by spot, without repeating a
    // spot it stayed at.
    final visits = [
      for (final place in widget.places)
        for (final stay in place.stays) (stay.startedAt, spotOf[place.key]!),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final path = <LatLng>[];
    for (final (_, spot) in visits) {
      final p = spot.first.position;
      if (path.isEmpty || path.last != p) path.add(p);
    }

    // The pop-up's spot, refreshed so it follows reloads.
    final popup = _popupKey == null
        ? null
        : spots.where((s) => s.any((p) => p.key == _popupKey)).firstOrNull;

    return Stack(
      children: [
        GoogleMap(
          key: widget.mapKey,
          initialCameraPosition: CameraPosition(
            target: path.isEmpty ? kDefaultMapCenter : path.last,
            zoom: kFocusedMapZoom,
          ),
          myLocationButtonEnabled: false,
          onMapCreated: (controller) {
            _controller = controller;
            _fit(controller, [for (final s in spots) s.first.position]);
          },
          // Tapping the map itself closes the pop-up.
          onTap: (_) {
            if (_popupKey != null) setState(() => _popupKey = null);
          },
          markers: {
            for (final spot in spots)
              Marker(
                markerId: MarkerId(spot.first.key),
                position: spot.first.position,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  spot.any((p) => p.key == widget.selectedKey)
                      ? BitmapDescriptor.hueRed
                      : spot.any((p) => p.isCurrent)
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueAzure,
                ),
                onTap: () => setState(() => _popupKey = spot.first.key),
              ),
          },
          polylines: {
            if (path.length > 1)
              Polyline(
                polylineId: const PolylineId('path'),
                points: path,
                width: 3,
                color: Theme.of(context).colorScheme.primary,
                patterns: [PatternItem.dash(16), PatternItem.gap(8)],
              ),
          },
        ),
        if (popup != null)
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _SpotCard(
                  key: ValueKey(popup.first.key),
                  spot: popup,
                  selectedKey: widget.selectedKey,
                  onClose: () => setState(() => _popupKey = null),
                  onOpen: (place) {
                    setState(() => _popupKey = null);
                    widget.onOpen(place);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card that pops up over the map when a pin is tapped: every pond at
/// that spot with its tags, visits, dates and complete readings, and
/// a button to show its readings under the map.
class _SpotCard extends StatelessWidget {
  const _SpotCard({
    super.key,
    required this.spot,
    required this.selectedKey,
    required this.onClose,
    required this.onOpen,
  });

  /// Oldest first.
  final List<_Place> spot;
  final String? selectedKey;
  final VoidCallback onClose;
  final ValueChanged<_Place> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Material(
      elevation: 6,
      color: scheme.surface,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                Icon(Icons.place_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    spot.length == 1
                        ? 'Pond'.tr
                        : '{0} ponds at the same spot'.trf([spot.length]),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close'.tr,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          for (final (i, place) in spot.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _PondIcon(place: place),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          place.label,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  _Tags(place: place),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoLine(
                    icon: Icons.event_outlined,
                    text: _rangeLabel(place.latest),
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.repeat,
                    text: _visitsLabel(place),
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.table_rows_outlined,
                    text: _readingsLabel(place.readingCount),
                    style: muted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: place.key == selectedKey
                        ? OutlinedButton.icon(
                            onPressed: () => onOpen(place),
                            icon: const Icon(Icons.check, size: 18),
                            label: Text('Showing readings below'.tr),
                          )
                        : FilledButton.icon(
                            onPressed: () => onOpen(place),
                            icon: const Icon(
                              Icons.table_chart_outlined,
                              size: 18,
                            ),
                            label: Text('View readings'.tr),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: style)),
      ],
    ),
  );
}

/// The right-hand panel (under the map on narrow layouts): the chosen
/// device, a way back to the device chooser, and a refresh button above
/// [child].
class _Panel extends StatelessWidget {
  const _Panel({
    required this.deviceId,
    required this.onBack,
    required this.onRefresh,
    required this.child,
    this.mapShown,
    this.onToggleMap,
  });

  final String deviceId;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final Widget child;

  /// Whether the map is showing, and a way to fold it away (phones only).
  final bool? mapShown;
  final VoidCallback? onToggleMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'All devices'.tr,
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Device {0}'.trf([deviceId]),
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onToggleMap != null)
                IconButton(
                  tooltip: mapShown == true ? 'Hide map'.tr : 'Show map'.tr,
                  isSelected: mapShown == true,
                  onPressed: onToggleMap,
                  icon: const Icon(Icons.map_outlined),
                  selectedIcon: const Icon(Icons.map),
                ),
              IconButton(
                tooltip: 'Refresh'.tr,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Above the readings of a chosen pond on a phone: folds the map away or
/// brings it back.
class _MapToggleBar extends StatelessWidget {
  const _MapToggleBar({required this.shown, required this.onToggle});

  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: onToggle,
      icon: Icon(shown ? Icons.expand_less : Icons.map_outlined, size: 18),
      label: Text(shown ? 'Hide map'.tr : 'Show map'.tr),
    ),
  );
}

class _PlaceList extends StatelessWidget {
  const _PlaceList({
    required this.places,
    required this.selectedKey,
    required this.onRefresh,
    required this.onOpen,
  });

  /// Newest visit first.
  final List<_Place> places;
  final String? selectedKey;
  final Future<void> Function() onRefresh;
  final ValueChanged<_Place> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(
            places.length == 1
                ? '1 pond · tap it to see the complete readings taken there'.tr
                : '{0} ponds · tap one to see the complete readings taken there'
                      .trf([places.length]),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final place in places)
            _PlaceCard(
              place: place,
              selected: place.key == selectedKey,
              onTap: () => onOpen(place),
            ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final _Place place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PondIcon(place: place),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.label, style: theme.textTheme.titleSmall),
                    _Tags(place: place),
                    const SizedBox(height: 2),
                    Text(_visitsLabel(place), style: muted),
                    Text(_rangeLabel(place.latest), style: muted),
                    Text(_readingsLabel(place.readingCount), style: muted),
                    if (!place.hasLocation)
                      Text('No location recorded'.tr, style: muted),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pond's visits and, for the chosen visit, the complete readings the
/// device took there. Shown under the map; [onClose] goes back to just the
/// map (wide) or the pond list (narrow).
class _PlaceDetail extends StatefulWidget {
  const _PlaceDetail({super.key, required this.place, required this.onClose});

  final _Place place;
  final VoidCallback onClose;

  @override
  State<_PlaceDetail> createState() => _PlaceDetailState();
}

class _PlaceDetailState extends State<_PlaceDetail> {
  /// The readings' timeframe: every visit at first, one visit when its card
  /// is tapped, or a preset / custom dates from the picker.
  late TrendSelection _selection = _allVisits;

  /// Where clearing a custom timeframe goes back to.
  var _lastPreset = TrendRange.daily;
  late ReadingsPager _pager = _pagerFor(_selection);

  /// The days from [start] to [end] (or today while still there).
  static TrendSelection _days(DateTime start, DateTime? end) =>
      TrendSelection.dates(
        DateTimeRange(
          start: DateUtils.dateOnly(start),
          end: DateUtils.dateOnly(end ?? DateTime.now()),
        ),
      );

  TrendSelection get _allVisits =>
      _days(widget.place.stays.last.startedAt, widget.place.latest.endedAt);

  TrendSelection _visitDays(DeviceStay stay) =>
      _days(stay.startedAt, stay.endedAt);

  ReadingsPager _pagerFor(TrendSelection selection) {
    final window = selection.window();
    // Every row is the average of its 15 minutes, hour, day, week, month or
    // year; the first view (all visits, as days) averages per day too.
    final step = selection.single ? null : selection.step;
    return ReadingsPager(
      pondId: widget.place.latest.pondId ?? '',
      start: window.start,
      end: window.end,
      step: step,
      withDates: selection.single,
      source: DevicePondReadingsPageSource(
        widget.place.latest.deviceId,
        averageBy: step,
      ),
    );
  }

  void _select(TrendSelection selection) {
    if (selection == _selection) return;
    setState(() {
      _pager.dispose();
      _selection = selection;
      if (selection.range case final range?) _lastPreset = range;
      _pager = _pagerFor(selection);
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = widget.place;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    // Visits are numbered oldest first; [place.stays] is newest first.
    int visitNumber(DeviceStay stay) =>
        place.stays.length - place.stays.indexOf(stay);
    final timeThere = place.stays.fold(
      Duration.zero,
      (sum, s) => sum + (s.endedAt ?? DateTime.now()).difference(s.startedAt),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        // Header: icon, name with its tags, coordinates; close.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _PondIcon(place: place),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(place.label, style: theme.textTheme.titleLarge),
                      ..._tagPills(place),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        place.hasLocation
                            ? Icons.place_outlined
                            : Icons.location_off_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          place.hasLocation
                              ? '${place.latest.latitude!.toStringAsFixed(5)}, ${place.latest.longitude!.toStringAsFixed(5)}'
                              : 'No location recorded'.tr,
                          style: muted?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close'.tr,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              // At a glance.
              Row(
                children: [
                  _Stat(
                    icon: Icons.repeat,
                    value: '${place.stays.length}',
                    label: place.stays.length == 1 ? 'Visit'.tr : 'Visits'.tr,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Stat(
                    icon: Icons.table_rows_outlined,
                    value: groupThousands(place.readingCount),
                    label: 'Complete readings'.tr,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Stat(
                    icon: Icons.schedule,
                    value: _durationLabel(timeThere),
                    label: 'Time here'.tr,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visits'.tr, style: theme.textTheme.titleSmall),
                        Text(
                          'Tap a visit to see just its readings.'.tr,
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  if (place.stays.length > 1 && _selection != _allVisits)
                    TextButton(
                      onPressed: () => _select(_allVisits),
                      child: Text('Show all visits'.tr),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        // One card per visit, newest first, scrolling sideways.
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: place.stays.length,
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final stay = place.stays[i];
              return _VisitCard(
                stay: stay,
                number: visitNumber(stay),
                latest: i == 0,
                selected: _selection == _visitDays(stay),
                onTap: () => _select(_visitDays(stay)),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Complete readings'.tr, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              TimeframePicker(
                selection: _selection,
                lastPreset: _lastPreset,
                onChanged: _select,
                singleLabel: 'Whole visit'.tr,
                readingDays: widget.place.latest.pondId == null
                    ? null
                    : () => ReadingDays.load(
                        widget.place.latest.pondId!,
                        deviceId: widget.place.latest.deviceId,
                        completeOnly: true,
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              ReadingHistoryTable(key: ValueKey(_selection), pager: _pager),
            ],
          ),
        ),
      ],
    );
  }
}

/// One figure in the at-a-glance row.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One visit to a pond: its number, dates, how long it lasted and how many
/// complete readings it has. Tapping shows its readings.
class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.stay,
    required this.number,
    required this.latest,
    required this.selected,
    required this.onTap,
  });

  final DeviceStay stay;
  final int number;
  final bool latest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final duration = (stay.endedAt ?? DateTime.now()).difference(
      stay.startedAt,
    );
    return SizedBox(
      width: 240,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Visit {0}'.trf([number]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: fg),
                      ),
                    ),
                    if (stay.isCurrent || latest) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Pill(
                        label: stay.isCurrent ? 'Current'.tr : 'Latest'.tr,
                        color: scheme.primary,
                      ),
                    ],
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _compactRange(stay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
                const Spacer(),
                Text(
                  '${_durationLabel(duration)} · ${_readingsLabel(stay.readingCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small rounded label.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pond's "Current" pill, when it applies.
List<Widget> _tagPills(_Place place) => [
  if (place.isCurrent)
    Builder(
      builder: (context) => _Pill(
        label: 'Current'.tr,
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.sensors,
      ),
    ),
];

/// A pond's round icon beside its name, filled in for the device's current
/// pond.
class _PondIcon extends StatelessWidget {
  const _PondIcon({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: place.isCurrent
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      foregroundColor: place.isCurrent
          ? scheme.onPrimary
          : scheme.onSurfaceVariant,
      child: const Icon(Icons.water_drop_outlined, size: 18),
    );
  }
}

/// The "Current" pill under a pond's name, when it applies.
class _Tags extends StatelessWidget {
  const _Tags({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) {
    final pills = _tagPills(place);
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: pills,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

String _pondLabel(DeviceStay stay) => stay.pondName ?? '';

String _readingsLabel(int count) => count == 1
    ? '1 complete reading'.tr
    : '{0} complete readings'.trf([groupThousands(count)]);

String _visitsLabel(_Place place) => place.stays.length == 1
    ? '1 visit'.tr
    : '{0} visits'.trf([place.stays.length]);

/// "Oct 9, 3:15 PM – Oct 11, 8:13 AM", or "Since Oct 9, 3:15 PM" while the
/// device is still there. The year is added when it isn't this year.
String _rangeLabel(DeviceStay stay) {
  String when(DateTime t) {
    final label = TrendStep.fifteenMinutes.fullLabel(t);
    return t.year == DateTime.now().year ? label : '$label, ${t.year}';
  }

  final end = stay.endedAt;
  return end == null
      ? 'Since {0}'.trf([when(stay.startedAt)])
      : '${when(stay.startedAt)} – ${when(end)}';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct 14", with the year when it isn't this year.
String _dateLabel(DateTime t) {
  final label = '${_monthNames[t.month - 1]} ${t.day}';
  return t.year == DateTime.now().year ? label : '$label, ${t.year}';
}

/// A visit's dates, without repeating the day: "Oct 14 · 12:13 PM – 2:46 PM",
/// "Oct 11, 10:48 PM – Oct 14, 3:25 AM", or "Since Oct 14, 12:13 PM".
String _compactRange(DeviceStay stay) {
  final start = stay.startedAt;
  final end = stay.endedAt;
  if (end == null) {
    return 'Since {0}'.trf(['${_dateLabel(start)}, ${clockLabel(start)}']);
  }
  if (DateUtils.isSameDay(start, end)) {
    return '${_dateLabel(start)} · ${clockLabel(start)} – ${clockLabel(end)}';
  }
  return '${_dateLabel(start)}, ${clockLabel(start)} – '
      '${_dateLabel(end)}, ${clockLabel(end)}';
}

/// "Under 1 min", "45 min", "2 h 33 min", "3 d 4 h".
String _durationLabel(Duration d) {
  if (d.inMinutes < 1) return 'Under 1 min'.tr;
  if (d.inHours < 1) return '{0} min'.trf([d.inMinutes]);
  if (d.inDays < 1) {
    final m = d.inMinutes % 60;
    return m == 0
        ? '{0} h'.trf([d.inHours])
        : '{0} h {1} min'.trf([d.inHours, m]);
  }
  final h = d.inHours % 24;
  return h == 0 ? '{0} d'.trf([d.inDays]) : '{0} d {1} h'.trf([d.inDays, h]);
}
