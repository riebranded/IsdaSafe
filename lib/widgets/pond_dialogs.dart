import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../models/pond_verification.dart';
import '../services/current_location_service.dart';
import '../services/fish_species_catalog.dart';
import '../services/location_search_service.dart';
import '../services/pond_photo_picker.dart';
import '../theme/app_spacing.dart';
import 'location_picker_map.dart';
import '../l10n/tr.dart';

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
              setState(() => errorText = 'Enter a pond name'.tr);
              return;
            }
            Navigator.of(context).pop(trimmed);
          }

          return AlertDialog(
            title: Text(title.tr),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Pond name'.tr,
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
                child: Text('Cancel'.tr),
              ),
              FilledButton(onPressed: submit, child: Text(confirmLabel.tr)),
            ],
          );
        },
      );
    },
  );
}

/// Result of [showAddPondDialog]. [verification] says how the pond will be
/// verified (satellite imagery, or an in-house photo to upload) — the check
/// itself runs afterwards on the server, see `verify-pond`.
typedef NewPondDraft = ({
  String name,
  double latitude,
  double longitude,
  PondVerification verification,
});

typedef CurrentLocationLoader = Future<LatLng?> Function();

/// Shows the combined pond-name and map-pin dialog.
///
/// The picker first requests a foreground location and opens centered on that
/// fix. If location is unavailable or permission is rejected, it uses the
/// Philippines-wide fallback and requires the user to move the map manually.
///
/// Normally the pond is verified against satellite imagery. Ticking "In-house
/// pond" skips that and asks for a photo of the pond instead. Either way the
/// dialog returns immediately; verification happens in the background.
/// A search box above the map jumps the pin to a typed place name.
/// [currentLocationLoader], [photoPicker] and [locationSearch] allow
/// deterministic tests.
Future<NewPondDraft?> showAddPondDialog(
  BuildContext context, {
  CurrentLocationLoader? currentLocationLoader,
  PondPhotoPicker? photoPicker,
  LocationSearchService? locationSearch,
}) {
  return showDialog<NewPondDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AddPondDialog(
      currentLocationLoader:
          currentLocationLoader ?? CurrentLocationService.getCurrentLocation,
      photoPicker: photoPicker ?? ImagePickerPondPhotoPicker(),
      locationSearch:
          locationSearch ??
          FallbackLocationSearchService(
            primary: PhotonLocationSearchService(),
            fallback: NominatimLocationSearchService(),
          ),
    ),
  );
}

/// Tells the user their pond is now being verified and how they'll hear back.
/// Shown right after a pond is saved.
Future<void> showVerificationStartedDialog(
  BuildContext context, {
  required String pondName,
  VerificationMethod method = VerificationMethod.satellite,
  String? checkingLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _VerificationStartedDialog(
      pondName: pondName,
      method: method,
      checkingLabel: checkingLabel,
    ),
  );
}

class _VerificationStartedDialog extends StatelessWidget {
  const _VerificationStartedDialog({
    required this.pondName,
    required this.method,
    this.checkingLabel,
  });

  final String pondName;
  final VerificationMethod method;

  /// Overrides the default "what we're checking" line.
  final String? checkingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checking =
        checkingLabel ??
        (method == VerificationMethod.photo
            ? 'Checking your pond photos'.tr
            : 'Analyzing satellite imagery of your pin'.tr);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.verified_user_outlined,
                            size: 36,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '“{0}” is under review'.trf([pondName]),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your pond has an ongoing review. This usually takes a minute or two, and you can keep using the app meanwhile.'.tr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          child: Column(
                            children: [
                              _VerificationStep(
                                icon: Icons.travel_explore,
                                text: checking,
                                active: true,
                              ),
                              _VerificationStep(
                                icon: Icons.notifications_outlined,
                                text:
                                    "We'll notify you on your device and in the app when the review updates".tr,
                              ),
                              _VerificationStep(
                                icon: Icons.dashboard_outlined,
                                text:
                                    'Once verified, it appears on your dashboard'.tr,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Got it'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationStep extends StatelessWidget {
  _VerificationStep({
    required this.icon,
    required this.text,
    this.active = false,
  });

  final IconData icon;
  final String text;

  /// The step happening right now (shown in the primary color with a spinner).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: active ? theme.colorScheme.onSurface : color,
                fontWeight: active ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (active)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _AddPondDialog extends StatefulWidget {
  const _AddPondDialog({
    required this.currentLocationLoader,
    required this.photoPicker,
    required this.locationSearch,
  });

  final CurrentLocationLoader currentLocationLoader;
  final PondPhotoPicker photoPicker;
  final LocationSearchService locationSearch;

  @override
  State<_AddPondDialog> createState() => _AddPondDialogState();
}

class _AddPondDialogState extends State<_AddPondDialog> {
  final _nameController = TextEditingController();
  final _center = ValueNotifier<LatLng>(kDefaultMapCenter);
  final _canSubmit = ValueNotifier<bool>(false);

  var _isLocating = true;
  var _isLocatingMe = false;
  var _hasName = false;
  var _hasPickedLocation = false;
  var _userAdjustedMap = false;
  var _isAtUserLocation = false;
  var _mapZoom = kDefaultMapZoom;

  var _isInHouse = false;

  /// Name of the place the pin was last jumped to via search.
  String? _searchLabel;

  /// Photos added on the form: optional for satellite ponds (used if
  /// buildings hide the pond), required — at least [kMinEvidencePhotos] — for
  /// in-house ponds, whose photos are the whole proof.
  final _evidencePhotos = <PondPhoto>[];
  String? _evidenceError;

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

  Future<void> _handleLocateMe() async {
    if (_isLocatingMe) return;
    setState(() => _isLocatingMe = true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Finding your location…'.tr),
        duration: Duration(seconds: 2),
      ),
    );

    LatLng? location;
    try {
      location = await widget.currentLocationLoader();
    } catch (_) {
      location = null;
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
    if (!mounted) return;

    if (location == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Couldn\'t get your location. Check that location access is allowed for this site/app.'.tr,
          ),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Located: {0}, {1}'.trf([location.latitude.toStringAsFixed(4), location.longitude.toStringAsFixed(4)]),
        ),
      ),
    );

    _userAdjustedMap = false;
    _center.value = location;
    _hasPickedLocation = true;
    _isAtUserLocation = true;
    _mapZoom = kUserLocationMapZoom;
    _updateCanSubmit();
    setState(() {});
  }

  void _updateCanSubmit() {
    _canSubmit.value =
        _hasName &&
        _hasPickedLocation &&
        (!_isInHouse || _evidencePhotos.length >= kMinEvidencePhotos);
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
    _searchLabel = null;
    if (_hasPickedLocation) return;
    _hasPickedLocation = true;
    _updateCanSubmit();
  }

  void _handleCenterChanged(LatLng center) {
    _center.value = center;
  }

  /// Jumps the map pin to [place], like tapping "locate me" but for a searched
  /// place instead of the device's position.
  void _selectPlace(PlaceResult place) {
    _userAdjustedMap = false;
    _center.value = LatLng(place.latitude, place.longitude);
    _hasPickedLocation = true;
    _isAtUserLocation = false;
    _mapZoom = kSearchResultMapZoom;
    _updateCanSubmit();
    setState(() {
      _searchLabel = place.title;
    });
  }

  void _handleInHouseChanged(bool? value) {
    setState(() => _isInHouse = value ?? false);
    _updateCanSubmit();
  }

  void _submit() {
    final center = _center.value;
    // Fewer than the minimum can't be used, so they aren't sent (and an
    // in-house pond can't get here without enough).
    final photos = _evidencePhotos.length >= kMinEvidencePhotos
        ? List.of(_evidencePhotos)
        : const <PondPhoto>[];
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      latitude: center.latitude,
      longitude: center.longitude,
      verification: PondVerification(
        // In-house ponds skip the satellite check entirely — a covered pond or
        // tank shows nothing from above — and are verified by their photos.
        method: _isInHouse
            ? VerificationMethod.photo
            : VerificationMethod.satellite,
        evidencePhotos: photos,
      ),
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

    // A full-screen page: map on the left, details on the right. Narrow
    // screens (phones) stack them instead. The Scaffold keeps snackbars inside
    // the page rather than behind it.
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close'.tr,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Add a pond'.tr),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: _buildMap(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 440,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: _buildFormStep(theme),
                      ),
                    ),
                  ],
                );
              }
              final mapHeight = (constraints.maxHeight * 0.45).clamp(
                280.0,
                520.0,
              );
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _buildFormStep(
                  theme,
                  mapAbove: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: SizedBox(height: mapHeight, child: _buildMap()),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The pin-picking map with the place search floating inside it.
  Widget _buildMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapHeight = constraints.maxHeight;
        return Stack(
          children: [
            Positioned.fill(
              child: LocationPickerMap(
                initialCenter: _center.value,
                initialZoom: _mapZoom,
                centerLabel: _isAtUserLocation ? 'You\'re here'.tr : _searchLabel,
                onUserInteraction: _handleUserInteraction,
                onCenterChanged: _handleCenterChanged,
                onLocateMe: _handleLocateMe,
                isLocatingMe: _isLocatingMe,
              ),
            ),
            if (isMapViewSupported)
              Positioned(
                left: AppSpacing.sm,
                // Leaves room for the locate-me button at the right.
                right: 56,
                top: AppSpacing.sm,
                // PointerInterceptor: on web the map is a platform view that
                // would otherwise swallow taps and drags meant for the search
                // box.
                child: PointerInterceptor(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: mapHeight - 2 * AppSpacing.sm,
                    ),
                    child: _PlaceSearch(
                      service: widget.locationSearch,
                      onSelected: _selectPlace,
                      // Whatever room the map has under the search bar.
                      maxResultsHeight: (mapHeight - 2 * AppSpacing.sm - 62)
                          .clamp(120.0, 400.0),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// What still blocks "Add pond", phrased as the next thing to do; null when
  /// the form is ready.
  String? _nextStep() {
    if (!_hasName) return 'Enter a pond name to continue.'.tr;
    if (!_hasPickedLocation) {
      return _isLocating
          ? 'Finding your location…'.tr
          : 'Pan the map to place the pin on your pond.'.tr;
    }
    if (_isInHouse && _evidencePhotos.length < kMinEvidencePhotos) {
      final missing = kMinEvidencePhotos - _evidencePhotos.length;
      return 'Add {0} more {1} to continue.'.trf([missing, missing == 1 ? 'photo'.tr : 'photos'.tr]);
    }
    return null;
  }

  /// A numbered step: a badge (a check once [done]) beside the content.
  Widget _stepCard(
    ThemeData theme, {
    required int number,
    required bool done,
    required Widget child,
  }) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: done
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
              child: done
                  ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                  : Text(
                      '$number',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// Name, location, pond type and photos as numbered steps, with a footer
  /// that says what's left and holds the action buttons. [mapAbove] puts the
  /// map at the top of the scrolling content on narrow screens.
  Widget _buildFormStep(ThemeData theme, {Widget? mapAbove}) {
    final scheme = theme.colorScheme;
    const gap = SizedBox(height: AppSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mapAbove != null) ...[mapAbove, gap],
                Text(
                  'Pin your pond on the map. We\'ll verify it before it appears on your dashboard.'.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                gap,
                _stepCard(
                  theme,
                  number: 1,
                  done: _hasName,
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Pond name'.tr,
                      prefixIcon: Icon(Icons.water_drop_outlined),
                    ),
                    onChanged: (value) {
                      _handleNameChanged(value);
                      setState(() {});
                    },
                  ),
                ),
                gap,
                // Desktop has no map view (it falls back to manual lat/lng
                // entry), so the search box sits here.
                if (!isMapViewSupported) ...[
                  _PlaceSearch(
                    service: widget.locationSearch,
                    onSelected: _selectPlace,
                  ),
                  gap,
                ],
                _stepCard(
                  theme,
                  number: 2,
                  done: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type of pond'.tr, style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      // Material (not DecoratedBox) so the tile's tap ripple
                      // shows on top of the tinted background.
                      Material(
                        color: _isInHouse
                            ? scheme.primaryContainer.withValues(alpha: 0.5)
                            : Colors.transparent,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: _isInHouse
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _isInHouse,
                          onChanged: _handleInHouseChanged,
                          title: Text('In-house pond'.tr),
                          subtitle: Text(
                            'Covered, indoors, or a tank that satellite can\'t see. You\'ll verify with a photo instead.'.tr,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                gap,
                _stepCard(
                  theme,
                  number: 3,
                  done: _evidencePhotos.length >= kMinEvidencePhotos,
                  child: _buildPhotosSection(theme),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        ValueListenableBuilder<bool>(
          valueListenable: _canSubmit,
          builder: (context, canSubmit, _) {
            final next = _nextStep();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      next == null ? Icons.check_circle : Icons.info_outline,
                      size: 18,
                      color: next == null
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        next ?? 'Ready to add your pond.'.tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: next == null
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel'.tr),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: canSubmit ? _submit : null,
                        child: Text('Add pond'.tr),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Upload of several pond photos. For a satellite pond they're optional and
  /// only used if the satellite check finds buildings over the pin (a pond could
  /// be hidden inside), in which case they're compared with the satellite image
  /// straight away. For an in-house pond they're required: no satellite check
  /// is done, so the photos are the proof.
  Widget _buildPhotosSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    final count = _evidencePhotos.length;
    final enough = count >= kMinEvidencePhotos;
    final required = _isInHouse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Photos of your pond'.tr,
                style: theme.textTheme.titleSmall,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: required
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                child: Text(
                  required ? 'Required'.tr : 'Optional'.tr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: required
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          required
              ? 'Add at least {0} photos of the pond or tank, showing the water. The satellite check is skipped for in-house ponds, so these photos are the proof.'.trf([kMinEvidencePhotos])
              : "Add {0} or more. If buildings hide the pond on the satellite map, we'll compare them with it right away, so you won't be asked for photos later.".trf([kMinEvidencePhotos]),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _PhotoGrid(
          photos: _evidencePhotos,
          maxPhotos: kMaxEvidencePhotos,
          picker: widget.photoPicker,
          onAdded: (added) {
            setState(() {
              _evidencePhotos.addAll(added);
              _evidenceError = null;
            });
            _updateCanSubmit();
          },
          onRemoved: (i) {
            setState(() => _evidencePhotos.removeAt(i));
            _updateCanSubmit();
          },
          onError: (message) => setState(() => _evidenceError = message),
        ),
        if (count > 0 || required) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                enough ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: enough ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  enough
                      ? '{0} photos ready.'.trf([count])
                      : required
                      ? '{0} of {1} photos added. Add {2} more to continue.'.trf([count, kMinEvidencePhotos, kMinEvidencePhotos - count])
                      : "Add {0} more, or remove these. They're only used with {1} or more.".trf([kMinEvidencePhotos - count, kMinEvidencePhotos]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: enough ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_evidenceError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _PhotoErrorBanner(message: _evidenceError!),
        ],
      ],
    );
  }
}

/// Zoom used after jumping to a searched place — close enough to find the pond.
const double kSearchResultMapZoom = 17;

/// A pill-shaped place search: type a name, press the arrow (or Enter), pick a
/// match. Owns its own query, loading and result state; the parent only hears
/// about the chosen place.
class _PlaceSearch extends StatefulWidget {
  const _PlaceSearch({
    required this.service,
    required this.onSelected,
    this.maxResultsHeight = 280,
  });

  final LocationSearchService service;
  final ValueChanged<PlaceResult> onSelected;

  /// Cap on the result list; it scrolls beyond this.
  final double maxResultsHeight;

  @override
  State<_PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<_PlaceSearch> {
  final _controller = TextEditingController();
  var _isSearching = false;

  /// Matches for the last search; null when nothing should be listed.
  List<PlaceResult>? _results;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2 || _isSearching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await widget.service.search(query);
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _results = results;
      });
    } on LocationSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = e.message.tr;
      });
    }
  }

  void _select(PlaceResult place) {
    setState(() {
      _results = null;
      _error = null;
    });
    widget.onSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final results = _results;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          shadowColor: Colors.black54,
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onChanged: (_) {
              if (_results != null || _error != null) {
                setState(() {
                  _results = null;
                  _error = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: 'Search for a place'.tr,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Search'.tr,
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _search,
                    ),
            ),
          ),
        ),
        if (_error != null || (results != null && results.isEmpty))
          _SearchCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                _error ?? 'No places found. Try a nearby town or landmark.'.tr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _error != null
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (results != null && results.isNotEmpty)
          _SearchCard(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxResultsHeight),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final place in results)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        place.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: place.subtitle.isEmpty
                          ? null
                          : Text(
                              place.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => _select(place),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Elevated surface for a search message or result list under the search bar.
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      // Material so the tiles' ripples draw over the surface colour.
      child: Material(
        elevation: 3,
        shadowColor: Colors.black54,
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: child,
      ),
    );
  }
}

/// Icon-in-a-circle with a title and one-line explanation, heading each step
/// of the add-pond dialog.
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.tr, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoTip extends StatelessWidget {
  _PhotoTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _PhotoErrorBanner extends StatelessWidget {
  const _PhotoErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for [kMinEvidencePhotos]–[kMaxEvidencePhotos] photos of a pond that
/// satellite imagery couldn't confirm because buildings cover it. They are
/// compared with the satellite image to check they show the same place.
///
/// Returns the photos, or null if cancelled. [photoPicker] allows tests.
Future<List<PondPhoto>?> showEvidencePhotosDialog(
  BuildContext context, {
  required String pondName,
  PondPhotoPicker? photoPicker,
}) {
  return showDialog<List<PondPhoto>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _EvidencePhotosDialog(
      pondName: pondName,
      photoPicker: photoPicker ?? ImagePickerPondPhotoPicker(),
    ),
  );
}

class _EvidencePhotosDialog extends StatefulWidget {
  const _EvidencePhotosDialog({
    required this.pondName,
    required this.photoPicker,
  });

  final String pondName;
  final PondPhotoPicker photoPicker;

  @override
  State<_EvidencePhotosDialog> createState() => _EvidencePhotosDialogState();
}

class _EvidencePhotosDialogState extends State<_EvidencePhotosDialog> {
  final _photos = <PondPhoto>[];
  String? _error;

  bool get _enough => _photos.length >= kMinEvidencePhotos;
  bool get _full => _photos.length >= kMaxEvidencePhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DialogHeader(
                        icon: Icons.photo_library_outlined,
                        title: 'Add photos of “{0}”'.trf([widget.pondName]),
                        subtitle:
                            'Buildings cover this spot on the satellite map, so we compare your photos with it to confirm the pond is really there.'.tr,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PhotoTip(
                        text:
                            'Add at least {0} photos from different angles'.trf([kMinEvidencePhotos]),
                      ),
                      _PhotoTip(
                        text:
                            'Show the water and what is around it: roof, walls, fence, trees'.tr,
                      ),
                      _PhotoTip(
                        text:
                            'Screenshots, internet images and photos of a screen are rejected'.tr,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _PhotoGrid(
                        photos: _photos,
                        maxPhotos: kMaxEvidencePhotos,
                        picker: widget.photoPicker,
                        onAdded: (added) => setState(() {
                          _photos.addAll(added);
                          _error = null;
                        }),
                        onRemoved: (i) => setState(() => _photos.removeAt(i)),
                        onError: (message) => setState(() => _error = message),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(
                            _enough ? Icons.check_circle : Icons.info_outline,
                            size: 18,
                            color: _enough
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _enough
                                  ? '{0} photos added. You can send them now{1}.'.trf([_photos.length, _full ? '' : ' or add up to ${kMaxEvidencePhotos - _photos.length} more'])
                                  : '{0} of {1} photos added. Add {2} more.'.trf([_photos.length, kMinEvidencePhotos, kMinEvidencePhotos - _photos.length]),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _enough
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _PhotoErrorBanner(message: _error!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel'.tr),
                  ),
                  FilledButton(
                    onPressed: _enough
                        ? () => Navigator.of(
                            context,
                          ).pop(List<PondPhoto>.of(_photos))
                        : null,
                    child: Text(
                      _enough
                          ? 'Submit {0} photos'.trf([_photos.length])
                          : 'Submit photos'.tr,
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

/// Thumbnails of the chosen photos plus the buttons to add more: "Take photo"
/// (phones only, live camera) and "Add photos" (the gallery / file chooser,
/// which accepts several pictures at once). Hides the add buttons at
/// [maxPhotos]. The parent owns the list; this only asks the picker and reports
/// what was added, removed, or went wrong.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.photos,
    required this.maxPhotos,
    required this.picker,
    required this.onAdded,
    required this.onRemoved,
    required this.onError,
  });

  final List<PondPhoto> photos;
  final int maxPhotos;
  final PondPhotoPicker picker;
  final ValueChanged<List<PondPhoto>> onAdded;
  final ValueChanged<int> onRemoved;
  final ValueChanged<String> onError;

  Future<void> _take(BuildContext context) async {
    try {
      final photo = await picker.pickPhoto();
      if (photo != null && context.mounted) onAdded([photo]);
    } on PondPhotoException catch (e) {
      if (context.mounted) onError(e.message.tr);
    }
  }

  Future<void> _upload(BuildContext context) async {
    try {
      final picked = await picker.pickPhotos(
        maxCount: maxPhotos - photos.length,
      );
      if (picked.isNotEmpty && context.mounted) onAdded(picked);
    } on PondPhotoException catch (e) {
      if (context.mounted) onError(e.message.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = photos.length >= maxPhotos;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (i, photo) in photos.indexed)
          _PhotoThumb(photo: photo, onRemove: () => onRemoved(i)),
        if (!full && picker.usesCamera)
          _AddPhotoTile(
            label: 'Take photo'.tr,
            icon: Icons.photo_camera_outlined,
            onTap: () => _take(context),
          ),
        if (!full)
          _AddPhotoTile(
            label: picker.usesCamera ? 'Upload photos'.tr : 'Add photos'.tr,
            icon: Icons.add_photo_alternate_outlined,
            onTap: () => _upload(context),
          ),
      ],
    );
  }
}

/// A chosen photo with a remove button.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.onRemove});

  final PondPhoto photo;
  final VoidCallback onRemove;

  static const double size = 96;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.memory(photo.bytes, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                    semanticLabel: 'Remove photo'.tr,
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

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _PhotoThumb.size,
      height: _PhotoThumb.size,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a checklist of [FishSpeciesCatalog.species] for the user to mark
/// which fish/shrimp a pond actually holds — used afterwards to suggest
/// feeding times on that pond's dashboard. Pass [initialSelection] (species
/// names) to pre-check a pond's existing species when editing.
///
/// Returns the selected species' names, or null if the dialog was
/// dismissed/skipped (callers should leave the pond's species untouched in
/// that case, rather than clearing them).
Future<List<String>?> showSelectSpeciesDialog(
  BuildContext context, {
  List<String> initialSelection = const [],
  String title = 'Add fish species',
}) {
  final selected = {...initialSelection};

  return showDialog<List<String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title.tr),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Which fish or shrimp does this pond have? This is used to suggest feeding times.'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final species in FishSpeciesCatalog.species.where(
                    (s) => s.assignableToPond,
                  ))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(species.name),
                      title: Text('${species.name} (${species.localName})'),
                      onChanged: (checked) {
                        setState(() {
                          if (checked ?? false) {
                            selected.add(species.name);
                          } else {
                            selected.remove(species.name);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Skip'.tr),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected.toList()),
                child: Text('Done'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Result of [showEditLocationDialog].
typedef LocationDraft = ({double latitude, double longitude});

/// Shows a map-only dialog for updating an existing pond's location.
///
/// Opens centered on the user's current location, same as [showAddPondDialog]
/// — falling back to the pond's existing coordinates if a fix isn't
/// available. The embedded locate-me button silently recenters the pin on
/// tap; no snackbar messaging either way. [currentLocationLoader] allows
/// deterministic tests.
Future<LocationDraft?> showEditLocationDialog(
  BuildContext context, {
  required double initialLatitude,
  required double initialLongitude,
  CurrentLocationLoader? currentLocationLoader,
}) {
  return showDialog<LocationDraft>(
    context: context,
    builder: (context) => _EditLocationDialog(
      initialLatitude: initialLatitude,
      initialLongitude: initialLongitude,
      currentLocationLoader:
          currentLocationLoader ?? CurrentLocationService.getCurrentLocation,
    ),
  );
}

class _EditLocationDialog extends StatefulWidget {
  const _EditLocationDialog({
    required this.initialLatitude,
    required this.initialLongitude,
    required this.currentLocationLoader,
  });

  final double initialLatitude;
  final double initialLongitude;
  final CurrentLocationLoader currentLocationLoader;

  @override
  State<_EditLocationDialog> createState() => _EditLocationDialogState();
}

class _EditLocationDialogState extends State<_EditLocationDialog> {
  late final _center = ValueNotifier<LatLng>(
    LatLng(widget.initialLatitude, widget.initialLongitude),
  );

  var _isLocatingMe = false;
  var _userAdjustedMap = false;
  var _isAtUserLocation = false;
  var _mapZoom = kFocusedMapZoom;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  // Silent by design: this only recenters the map if a fix resolves before
  // the user has touched it, and otherwise just leaves the pond's existing
  // location in place — no message either way.
  Future<void> _loadCurrentLocation() async {
    LatLng? location;
    try {
      location = await widget.currentLocationLoader();
    } catch (_) {
      location = null;
    }
    if (!mounted || _userAdjustedMap || location == null) return;

    _center.value = location;
    setState(() {
      _isAtUserLocation = true;
      _mapZoom = kUserLocationMapZoom;
    });
  }

  Future<void> _handleLocateMe() async {
    if (_isLocatingMe) return;
    setState(() => _isLocatingMe = true);

    LatLng? location;
    try {
      location = await widget.currentLocationLoader();
    } catch (_) {
      location = null;
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
    if (!mounted || location == null) return;

    _userAdjustedMap = false;
    _center.value = location;
    setState(() {
      _isAtUserLocation = true;
      _mapZoom = kUserLocationMapZoom;
    });
  }

  void _handleUserInteraction() {
    _userAdjustedMap = true;
    if (_isAtUserLocation) setState(() => _isAtUserLocation = false);
  }

  @override
  void dispose() {
    _center.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Edit location'.tr, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: LocationPickerMap(
                  initialCenter: _center.value,
                  initialZoom: _mapZoom,
                  centerLabel: _isAtUserLocation ? 'You\'re here'.tr : null,
                  onUserInteraction: _handleUserInteraction,
                  onCenterChanged: (newCenter) => _center.value = newCenter,
                  onLocateMe: _handleLocateMe,
                  isLocatingMe: _isLocatingMe,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ValueListenableBuilder<LatLng>(
                valueListenable: _center,
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
                    child: Text('Cancel'.tr),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: () {
                      final value = _center.value;
                      Navigator.of(context).pop((
                        latitude: value.latitude,
                        longitude: value.longitude,
                      ));
                    },
                    child: Text('Save location'.tr),
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
