import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Country-wide default view (roughly the geographic center of the
/// Philippines) shown when a pond has no prior location to anchor on.
const LatLng kDefaultMapCenter = LatLng(12.8797, 121.7740);
const double kDefaultMapZoom = 5.5;

/// Wider neighborhood view used when first centering on the user's location.
const double kUserLocationMapZoom = 12;

/// Closer zoom used when editing an existing pond location.
const double kFocusedMapZoom = 14;

/// A map with a pin fixed at the center of the viewport. The user pans and
/// zooms the map underneath it to position the pin precisely.
///
/// Camera updates are reported through [onCenterChanged] without rebuilding
/// this widget. [onUserInteraction] distinguishes manual adjustment from
/// initial/programmatic movement. A changed [initialCenter] recenters the
/// existing controller instead of replacing the map. [centerLabel] identifies
/// a programmatically supplied location and is hidden after manual movement.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    required this.onCenterChanged,
    this.centerLabel,
    this.onUserInteraction,
    this.tileProvider,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final ValueChanged<LatLng> onCenterChanged;
  final String? centerLabel;
  final VoidCallback? onUserInteraction;
  final TileProvider? tileProvider;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  final _mapController = MapController();
  late bool _showCenterLabel;

  @override
  void initState() {
    super.initState();
    _showCenterLabel = widget.centerLabel != null;
  }

  @override
  void didUpdateWidget(covariant LocationPickerMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerLabel != widget.centerLabel) {
      _showCenterLabel = widget.centerLabel != null;
    }

    final centerChanged =
        oldWidget.initialCenter.latitude != widget.initialCenter.latitude ||
        oldWidget.initialCenter.longitude != widget.initialCenter.longitude;
    if (!centerChanged && oldWidget.initialZoom == widget.initialZoom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(widget.initialCenter, widget.initialZoom);
      }
    });
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      if (_showCenterLabel) setState(() => _showCenterLabel = false);
      widget.onUserInteraction?.call();
    }
    widget.onCenterChanged(camera.center);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              onPositionChanged: _handlePositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.isdasafe',
                tileProvider: widget.tileProvider ?? NetworkTileProvider(),
                panBuffer: 0,
                keepBuffer: 1,
                tileDisplay: const TileDisplay.instantaneous(),
                tileUpdateTransformer: TileUpdateTransformers.throttle(
                  const Duration(milliseconds: 100),
                ),
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Icon(
                Icons.location_pin,
                size: 40,
                color: theme.colorScheme.primary,
                shadows: const [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          if (_showCenterLabel && widget.centerLabel != null)
            IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, 30),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      widget.centerLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
