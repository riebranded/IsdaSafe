import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/reading_status.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/location_picker_map.dart';
import 'pond_dashboard_screen.dart';

/// All ponds pinned on one map (colored by overall status), tapping a
/// marker shows that pond's full dashboard on the right on wide/web
/// viewports — the exact `PondDashboardBody` content used elsewhere — or
/// pushes the full-screen [PondDashboardScreen] on narrow widths, where
/// there's no room for a persistent side panel. Falls back to a plain
/// coordinate list on platforms without a supported map view (see
/// [isMapViewSupported]), matching `LocationPickerMap`'s own fallback for
/// the same limitation.
class PondMapScreen extends StatefulWidget {
  const PondMapScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  @override
  State<PondMapScreen> createState() => _PondMapScreenState();
}

class _PondMapScreenState extends State<PondMapScreen> {
  Pond? _selected;

  void _handleSelect(BuildContext context, Pond pond, bool isWide) {
    if (isWide) {
      setState(() => _selected = pond);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PondDashboardScreen(pond: pond)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pondProvider = context.watch<PondProvider>();
    final ponds = pondProvider.ponds;

    if (ponds.isEmpty && pondProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    var selected = _selected;
    if (selected != null && !ponds.any((p) => p.id == selected!.id)) {
      selected = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint;
        final selectedId = isWide ? selected?.id : null;
        final map = isMapViewSupported
            ? _PondMap(
                ponds: ponds,
                cache: widget.cache,
                selectedId: selectedId,
                onSelect: (pond) => _handleSelect(context, pond, isWide),
              )
            : _PondCoordinateList(
                ponds: ponds,
                selectedId: selectedId,
                onSelect: (pond) => _handleSelect(context, pond, isWide),
              );

        if (!isWide) return map;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: map),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: selected == null
                  ? const _NoPondSelected()
                  : ChangeNotifierProvider<DashboardProvider>(
                      key: ValueKey(selected.id),
                      create: (_) => DashboardProvider(pond: selected!),
                      child: PondDashboardBody(pond: selected, showHeader: true),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PondMap extends StatelessWidget {
  const _PondMap({required this.ponds, required this.cache, required this.selectedId, required this.onSelect});

  final List<Pond> ponds;
  final PondSnapshotCache cache;
  final String? selectedId;
  final ValueChanged<Pond> onSelect;

  double _hueForStatus(ReadingStatus status) {
    return switch (status) {
      ReadingStatus.normal => BitmapDescriptor.hueGreen,
      ReadingStatus.warning => BitmapDescriptor.hueOrange,
      ReadingStatus.critical => BitmapDescriptor.hueRed,
    };
  }

  /// One marker per located pond. The info window shows the pond name plus a
  /// status line and a tap hint — a title-only [InfoWindow] renders as an
  /// awkward tall, near-empty bubble, whereas a title + snippet lays out as a
  /// normal, content-sized card. Tapping either the marker or the bubble
  /// opens the pond (right panel on wide, full screen on narrow).
  Marker _markerFor(Pond pond) {
    final status = overallStatus(cache.snapshotFor(pond).readings);
    return Marker(
      markerId: MarkerId(pond.id),
      position: LatLng(pond.latitude!, pond.longitude!),
      infoWindow: InfoWindow(
        title: pond.name,
        snippet: 'Status: ${status.label} · Tap to view readings',
        onTap: () => onSelect(pond),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(_hueForStatus(status)),
      onTap: () => onSelect(pond),
    );
  }

  @override
  Widget build(BuildContext context) {
    final located = ponds.where((p) => p.hasLocation).toList();
    final initialTarget = located.isNotEmpty
        ? LatLng(located.first.latitude!, located.first.longitude!)
        : kDefaultMapCenter;

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialTarget, zoom: kDefaultMapZoom),
      myLocationButtonEnabled: false,
      markers: {for (final pond in located) _markerFor(pond)},
    );
  }
}

/// Used on platforms where `google_maps_flutter` has no map view (desktop
/// native — Windows/Linux/macOS) — same limitation `LocationPickerMap`
/// already works around.
class _PondCoordinateList extends StatelessWidget {
  const _PondCoordinateList({required this.ponds, required this.selectedId, required this.onSelect});

  final List<Pond> ponds;
  final String? selectedId;
  final ValueChanged<Pond> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          "Map view isn't available on this platform. Select a pond to see its readings.",
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final pond in ponds)
          Card(
            child: ListTile(
              selected: pond.id == selectedId,
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(pond.name),
              subtitle: Text(
                pond.hasLocation
                    ? '${pond.latitude!.toStringAsFixed(4)}, ${pond.longitude!.toStringAsFixed(4)}'
                    : 'No location set',
              ),
              onTap: () => onSelect(pond),
            ),
          ),
      ],
    );
  }
}

class _NoPondSelected extends StatelessWidget {
  const _NoPondSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.water_drop_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tap a pond marker to see its readings',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
