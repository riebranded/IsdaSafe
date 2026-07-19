import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/current_location_service.dart';
import '../theme/app_spacing.dart';
import 'location_picker_map.dart';

/// Shows a text-field dialog for renaming a pond.
/// Returns the entered (trimmed, non-empty) name, or null if cancelled.
Future<String?> showPondNameDialog(
  BuildContext context, {
  String title = 'Rename pond',
  String initialValue = '',
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initialValue);

  return showDialog<String>(
    context: context,
    builder: (context) {
      String? errorText;

      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) {
              setState(() => errorText = 'Enter a pond name');
              return;
            }
            Navigator.of(context).pop(trimmed);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Pond name',
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) setState(() => errorText = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: Text(confirmLabel)),
            ],
          );
        },
      );
    },
  );
}

/// Result of [showAddPondDialog].
typedef NewPondDraft = ({String name, double latitude, double longitude});

typedef CurrentLocationLoader = Future<LatLng?> Function();

/// Shows the combined pond-name and map-pin dialog.
///
/// The picker first requests a foreground location and opens centered on that
/// fix. If location is unavailable or permission is rejected, it uses the
/// Philippines-wide fallback and requires the user to move the map manually.
/// [currentLocationLoader] and [tileProvider] allow deterministic tests.
Future<NewPondDraft?> showAddPondDialog(
  BuildContext context, {
  TileProvider? tileProvider,
  CurrentLocationLoader? currentLocationLoader,
}) {
  return showDialog<NewPondDraft>(
    context: context,
    builder: (context) => _AddPondDialog(
      tileProvider: tileProvider,
      currentLocationLoader:
          currentLocationLoader ?? CurrentLocationService.getCurrentLocation,
    ),
  );
}

class _AddPondDialog extends StatefulWidget {
  const _AddPondDialog({
    required this.currentLocationLoader,
    this.tileProvider,
  });

  final CurrentLocationLoader currentLocationLoader;
  final TileProvider? tileProvider;

  @override
  State<_AddPondDialog> createState() => _AddPondDialogState();
}

class _AddPondDialogState extends State<_AddPondDialog> {
  final _nameController = TextEditingController();
  final _center = ValueNotifier<LatLng>(kDefaultMapCenter);
  final _canSubmit = ValueNotifier<bool>(false);

  var _isLocating = true;
  var _hasName = false;
  var _hasPickedLocation = false;
  var _userAdjustedMap = false;
  var _isAtUserLocation = false;
  var _mapZoom = kDefaultMapZoom;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    LatLng? location;
    try {
      location = await widget.currentLocationLoader();
    } catch (_) {
      location = null;
    }
    if (!mounted) return;

    if (location != null && !_userAdjustedMap) {
      _center.value = location;
      _hasPickedLocation = true;
      _isAtUserLocation = true;
      _mapZoom = kUserLocationMapZoom;
    }
    _updateCanSubmit();
    setState(() => _isLocating = false);
  }

  void _updateCanSubmit() {
    _canSubmit.value = _hasName && _hasPickedLocation;
  }

  void _handleNameChanged(String value) {
    final hasName = value.trim().isNotEmpty;
    if (hasName == _hasName) return;
    _hasName = hasName;
    _updateCanSubmit();
  }

  void _handleUserInteraction() {
    _userAdjustedMap = true;
    _isAtUserLocation = false;
    if (_hasPickedLocation) return;
    _hasPickedLocation = true;
    _updateCanSubmit();
  }

  void _handleCenterChanged(LatLng center) {
    _center.value = center;
  }

  void _submit() {
    final center = _center.value;
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      latitude: center.latitude,
      longitude: center.longitude,
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _center.dispose();
    _canSubmit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add pond', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Pond name'),
                onChanged: _handleNameChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: LocationPickerMap(
                  initialCenter: _center.value,
                  initialZoom: _mapZoom,
                  centerLabel: _isAtUserLocation ? "You're here" : null,
                  tileProvider: widget.tileProvider,
                  onUserInteraction: _handleUserInteraction,
                  onCenterChanged: _handleCenterChanged,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ValueListenableBuilder<LatLng>(
                valueListenable: _center,
                builder: (context, center, _) {
                  final message = _hasPickedLocation
                      ? '${center.latitude.toStringAsFixed(4)}, '
                            '${center.longitude.toStringAsFixed(4)}'
                      : _isLocating
                      ? 'Finding your location… You can adjust the map now.'
                      : 'Location unavailable. Pan the map to position the pin.';
                  return Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ValueListenableBuilder<bool>(
                    valueListenable: _canSubmit,
                    builder: (context, canSubmit, _) => FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      child: const Text('Add pond'),
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

/// Result of [showEditLocationDialog].
typedef LocationDraft = ({double latitude, double longitude});

/// Shows a map-only dialog for updating an existing pond's location.
///
/// Camera movement updates only the coordinate label, rather than rebuilding
/// the map on every frame.
Future<LocationDraft?> showEditLocationDialog(
  BuildContext context, {
  required double initialLatitude,
  required double initialLongitude,
  TileProvider? tileProvider,
}) async {
  final center = ValueNotifier(LatLng(initialLatitude, initialLongitude));

  final result = await showDialog<LocationDraft>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit location', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: LocationPickerMap(
                    initialCenter: center.value,
                    initialZoom: kFocusedMapZoom,
                    tileProvider: tileProvider,
                    onCenterChanged: (newCenter) => center.value = newCenter,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ValueListenableBuilder<LatLng>(
                  valueListenable: center,
                  builder: (context, value, _) => Text(
                    '${value.latitude.toStringAsFixed(4)}, '
                    '${value.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () {
                        final value = center.value;
                        Navigator.of(context).pop((
                          latitude: value.latitude,
                          longitude: value.longitude,
                        ));
                      },
                      child: const Text('Save location'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  center.dispose();
  return result;
}
