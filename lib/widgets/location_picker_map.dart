import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Country-wide default view (roughly the geographic center of the
/// Philippines) shown when a pond has no prior location to anchor on.
const LatLng kDefaultMapCenter = LatLng(12.8797, 121.7740);
const double kDefaultMapZoom = 5.5;

/// Closest zoom Google Maps supports, used when first centering on the
/// user's location. If imagery isn't available at this level for a given
/// spot, the SDK automatically clamps down to whatever it does support.
const double kUserLocationMapZoom = 21;

/// Closer zoom used when editing an existing pond location.
const double kFocusedMapZoom = 14;

/// google_maps_flutter has no official Windows/Linux/macOS support, so those
/// platforms fall back to manual coordinate entry instead of a map view.
bool get isMapViewSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS;

/// A map with a pin fixed at the center of the viewport. The user pans and
/// zooms the map underneath it to position the pin precisely.
///
/// Camera updates are reported through [onCenterChanged] without rebuilding
/// this widget. [onUserInteraction] distinguishes manual adjustment from
/// initial/programmatic movement. A changed [initialCenter] recenters the
/// existing controller instead of replacing the map. [centerLabel] identifies
/// a programmatically supplied location and is hidden after manual movement.
///
/// On platforms where [isMapViewSupported] is false, renders a manual
/// latitude/longitude entry form instead.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    required this.onCenterChanged,
    this.centerLabel,
    this.onUserInteraction,
    this.onLocateMe,
    this.isLocatingMe = false,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final ValueChanged<LatLng> onCenterChanged;
  final String? centerLabel;
  final VoidCallback? onUserInteraction;

  /// Shows a "my location" button when non-null; pressing it asks the
  /// caller to re-fetch the current position and pass it back through a
  /// new [initialCenter], which recenters the map.
  final VoidCallback? onLocateMe;

  /// Swaps the button's icon for a spinner and disables it, so the tap
  /// gets an immediate visual response even while the location fetch
  /// itself (GPS/network) is still in flight.
  final bool isLocatingMe;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  GoogleMapController? _mapController;
  late bool _showCenterLabel;
  var _isProgrammaticMove = false;

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

    final controller = _mapController;
    if (controller == null) return;
    _isProgrammaticMove = true;
    controller.moveCamera(
      CameraUpdate.newLatLngZoom(widget.initialCenter, widget.initialZoom),
    );
  }

  void _handleCameraMoveStarted() {
    if (_isProgrammaticMove) return;
    if (_showCenterLabel) setState(() => _showCenterLabel = false);
    widget.onUserInteraction?.call();
  }

  void _handleCameraMove(CameraPosition position) {
    widget.onCenterChanged(position.target);
  }

  void _handleCameraIdle() {
    _isProgrammaticMove = false;
  }

  void _handleManualInteraction() {
    if (_showCenterLabel) setState(() => _showCenterLabel = false);
    widget.onUserInteraction?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    debugPrint(
      'LocationPickerMap.build: kIsWeb=$kIsWeb '
      'isMapViewSupported=$isMapViewSupported '
      'initialCenter=${widget.initialCenter} initialZoom=${widget.initialZoom}',
    );

    if (!isMapViewSupported) {
      debugPrint('LocationPickerMap: rendering manual entry fallback');
      return _ManualLocationEntry(
        initialCenter: widget.initialCenter,
        centerLabel: _showCenterLabel ? widget.centerLabel : null,
        onCenterChanged: widget.onCenterChanged,
        onUserInteraction: _handleManualInteraction,
        onLocateMe: widget.onLocateMe,
        isLocatingMe: widget.isLocatingMe,
      );
    }

    debugPrint('LocationPickerMap: building GoogleMap widget');
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialCenter,
              zoom: widget.initialZoom,
            ),
            onMapCreated: (controller) {
              debugPrint(
                'LocationPickerMap: onMapCreated fired '
                '(platform view + JS API ready)',
              );
              _mapController = controller;
            },
            onCameraMoveStarted: _handleCameraMoveStarted,
            onCameraMove: _handleCameraMove,
            onCameraIdle: _handleCameraIdle,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
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
          if (widget.onLocateMe != null)
            // Positioned top-right so it can't overlap the center pin, the
            // "You're here" label (which floats below-center), or the
            // Cancel/Save buttons below the map. Wrapped in PointerInterceptor
            // because google_maps_flutter_web renders the map as a real
            // browser platform view — without this, taps here would pass
            // straight through to the map underneath instead of the button.
            Positioned(
              right: 8,
              top: 8,
              child: PointerInterceptor(
                child: FloatingActionButton.small(
                  heroTag: null,
                  onPressed: widget.isLocatingMe ? null : widget.onLocateMe,
                  child: widget.isLocatingMe
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fallback used on platforms without a supported map view (currently
/// Windows, Linux, and macOS — see [isMapViewSupported]).
class _ManualLocationEntry extends StatefulWidget {
  const _ManualLocationEntry({
    required this.initialCenter,
    required this.onCenterChanged,
    this.centerLabel,
    this.onUserInteraction,
    this.onLocateMe,
    this.isLocatingMe = false,
  });

  final LatLng initialCenter;
  final ValueChanged<LatLng> onCenterChanged;
  final String? centerLabel;
  final VoidCallback? onUserInteraction;
  final VoidCallback? onLocateMe;
  final bool isLocatingMe;

  @override
  State<_ManualLocationEntry> createState() => _ManualLocationEntryState();
}

class _ManualLocationEntryState extends State<_ManualLocationEntry> {
  late final _latController = TextEditingController(
    text: widget.initialCenter.latitude.toStringAsFixed(4),
  );
  late final _lngController = TextEditingController(
    text: widget.initialCenter.longitude.toStringAsFixed(4),
  );

  @override
  void didUpdateWidget(covariant _ManualLocationEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCenter.latitude != widget.initialCenter.latitude ||
        oldWidget.initialCenter.longitude != widget.initialCenter.longitude) {
      _latController.text = widget.initialCenter.latitude.toStringAsFixed(4);
      _lngController.text = widget.initialCenter.longitude.toStringAsFixed(4);
    }
  }

  void _handleChanged(String _) {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    if (lat == null || lng == null) return;
    widget.onUserInteraction?.call();
    widget.onCenterChanged(LatLng(lat, lng));
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.centerLabel != null) ...[
              Text(
                widget.centerLabel!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              "Map view isn't available on this platform. "
              'Enter coordinates manually.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _latController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
              onChanged: _handleChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lngController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
              onChanged: _handleChanged,
            ),
            if (widget.onLocateMe != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.isLocatingMe ? null : widget.onLocateMe,
                icon: widget.isLocatingMe
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
