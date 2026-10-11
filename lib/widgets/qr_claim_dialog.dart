import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/tr.dart';
import '../models/pond.dart';
import '../services/usb_sensor/device_claim.dart';
import '../services/usb_sensor/device_registry.dart';
import '../services/usb_sensor/qr_image_decoder.dart';
import '../theme/app_spacing.dart';

/// Pairs a device with [pond] by its QR label: scan it with the camera,
/// upload a photo of it, or type the device ID and claim code printed under
/// it; the database then files the device's readings under this account and
/// pond. No cable needed, but the device must be on WiFi to send readings.
/// With [initial] (a label scanned with the phone's own camera app), it pairs
/// straight away.
///
/// [pickImage] picks the photo to upload (tests swap it out); it returns the
/// image's bytes, or null if the user cancels.
///
/// Returns the device ID once paired, or null if cancelled.
Future<String?> showQrClaimDialog(
  BuildContext context, {
  required Pond pond,
  ClaimPayload? initial,
  DeviceRegistry? registry,
  Future<Uint8List?> Function()? pickImage,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _QrClaimDialog(
      pond: pond,
      initial: initial,
      registry: registry ?? DeviceRegistry.instance,
      pickImage: pickImage ?? _pickImageFromDevice,
    ),
  );
}

/// The browser's file chooser on the web; the photo gallery on phones.
Future<Uint8List?> _pickImageFromDevice() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

enum _Step {
  scan,
  readingPhoto,
  manual,
  working,
  ownedByOther,
  transferRequested,
  error,
}

class _QrClaimDialog extends StatefulWidget {
  const _QrClaimDialog({
    required this.pond,
    required this.initial,
    required this.registry,
    required this.pickImage,
  });

  final Pond pond;
  final ClaimPayload? initial;
  final DeviceRegistry registry;
  final Future<Uint8List?> Function() pickImage;

  @override
  State<_QrClaimDialog> createState() => _QrClaimDialogState();
}

class _QrClaimDialogState extends State<_QrClaimDialog> {
  // With a label already scanned, don't start the camera at all.
  late var _step = widget.initial == null ? _Step.scan : _Step.working;
  ClaimPayload? _payload;
  String? _error;
  String? _scanHint;
  bool _transferPending = false;
  bool _handlingScan = false;

  final _deviceIdField = TextEditingController();
  final _codeField = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claim(initial));
    }
  }

  @override
  void dispose() {
    _deviceIdField.dispose();
    _codeField.dispose();
    unawaited(_scanner?.dispose());
    super.dispose();
  }

  /// Created when the camera view is first shown and kept for the dialog's
  /// lifetime: the view comes and goes (e.g. while a photo is read), and a
  /// controller disposed with it could still be starting the camera.
  MobileScannerController? _scanner;

  MobileScannerController get _scannerController => _scanner ??=
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  void _onDetect(BarcodeCapture capture) {
    if (_handlingScan || _step != _Step.scan) return;
    for (final barcode in capture.barcodes) {
      final payload = parseClaimPayload(barcode.rawValue ?? '');
      if (payload != null) {
        _handlingScan = true;
        _claim(payload).whenComplete(() => _handlingScan = false);
        return;
      }
    }
    setState(
      () => _scanHint =
          "That isn't an IsdaSafe label. Scan the QR code on the device.".tr,
    );
  }

  /// Reads the QR code in a photo of the label (or the label's image file)
  /// and pairs the device like a camera scan would.
  Future<void> _uploadPhoto() async {
    final Uint8List? bytes;
    try {
      bytes = await widget.pickImage();
    } catch (_) {
      if (mounted) {
        setState(
          () => _scanHint = "Couldn't open that photo. Try another one.".tr,
        );
      }
      return;
    }
    if (bytes == null || !mounted) return; // Cancelled.

    setState(() {
      _step = _Step.readingPhoto;
      _scanHint = null;
    });
    final text = await decodeQrFromImage(bytes);
    if (!mounted) return;
    final payload = text == null ? null : parseClaimPayload(text);
    if (payload == null) {
      setState(() {
        _step = _Step.scan;
        _scanHint = text == null
            ? "Couldn't find a QR code in that photo. Try a sharper photo taken closer to the label, or enter the code instead."
                  .tr
            : "That isn't an IsdaSafe label. Scan the QR code on the device."
                  .tr;
      });
      return;
    }
    await _claim(payload);
  }

  void _submitManual() {
    final payload = claimPayloadFrom(_deviceIdField.text, _codeField.text);
    if (payload == null) {
      setState(
        () => _error =
            'Check the device ID (12 characters) and the claim code on the label.'
                .tr,
      );
      return;
    }
    _claim(payload);
  }

  Future<void> _claim(ClaimPayload payload) async {
    setState(() {
      _payload = payload;
      _step = _Step.working;
      _error = null;
    });
    final result = await widget.registry.claim(
      payload.deviceId,
      payload.code,
      widget.pond.id,
    );
    if (!mounted) return;
    switch (result.status) {
      case ClaimStatus.claimed:
        Navigator.of(context).pop(payload.deviceId);
        return;
      case ClaimStatus.ownedByOther:
        setState(() {
          _step = _Step.ownedByOther;
          _transferPending = result.transferPending;
        });
        return;
      case ClaimStatus.inUse:
        _fail(
          'This device is already paired with {0}. Remove it from that pond first, then pair it here.'
              .trf([result.pondName ?? 'another pond'.tr]),
        );
      case ClaimStatus.pondHasDevice:
        _fail(
          'This pond already has a paired device. Remove it first to pair a different one.'
              .tr,
        );
      case ClaimStatus.invalid:
        _fail(
          "That label doesn't match a registered IsdaSafe device. Check the device ID and claim code."
              .tr,
        );
      case ClaimStatus.rateLimited:
        _fail('Too many tries. Wait an hour, then try again.'.tr);
      case ClaimStatus.failed:
        _fail(
          "Couldn't pair the device. Check your connection and try again.".tr,
        );
    }
  }

  void _fail(String message) {
    setState(() {
      _step = _Step.error;
      _error = message;
    });
  }

  Future<void> _requestTransfer() async {
    final payload = _payload;
    if (payload == null) return;
    setState(() => _step = _Step.working);
    final status = await widget.registry.requestTransfer(
      payload.deviceId,
      payload.code,
    );
    if (!mounted) return;
    switch (status) {
      case TransferRequestStatus.requested ||
          TransferRequestStatus.alreadyRequested:
        setState(() => _step = _Step.transferRequested);
      case TransferRequestStatus.unclaimed ||
          TransferRequestStatus.alreadyYours:
        // Its owner let it go (or it's ours now): just claim it.
        await _claim(payload);
      case TransferRequestStatus.invalid:
        _fail(
          "That label doesn't match a registered IsdaSafe device. Check the device ID and claim code."
              .tr,
        );
      case TransferRequestStatus.rateLimited:
        _fail('Too many tries. Wait an hour, then try again.'.tr);
      case TransferRequestStatus.failed:
        _fail(
          "Couldn't send the request. Check your connection and try again.".tr,
        );
    }
  }

  void _backToScan() => setState(() {
    _step = _Step.scan;
    _error = null;
    _scanHint = null;
  });

  @override
  Widget build(BuildContext context) {
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text('Cancel'.tr),
    );
    final close = FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text('Close'.tr),
    );

    return switch (_step) {
      _Step.scan => _frame(
        icon: Icons.qr_code_scanner,
        title: 'Scan the device\'s QR label'.tr,
        message:
            'Point the camera at the QR code on your IsdaSafe device. Make sure the device is switched on and connected to WiFi.'
                .tr,
        body: [
          const SizedBox(height: AppSpacing.lg),
          _ScannerView(controller: _scannerController, onDetect: _onDetect),
          if (_scanHint != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _scanHint!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: _uploadPhoto,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text('Upload a photo of the label'.tr),
            ),
          ),
          Text(
            'Only use photos of your own device\'s label.'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        actions: [
          cancel,
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _step = _Step.manual;
              _error = null;
            }),
            icon: const Icon(Icons.keyboard_outlined, size: 18),
            label: Text('Enter code instead'.tr),
          ),
        ],
      ),
      _Step.manual => _frame(
        icon: Icons.keyboard_outlined,
        title: 'Enter the label\'s code'.tr,
        message:
            'Type the device ID and claim code printed under the QR code.'.tr,
        body: [
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _deviceIdField,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Device ID'.tr,
              hintText: '6C383B124B00',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _codeField,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Claim code'.tr,
              hintText: 'ABCD-EFGH-JKMN',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submitManual(),
          ),
        ],
        actions: [
          TextButton(onPressed: _backToScan, child: Text('Scan instead'.tr)),
          FilledButton(onPressed: _submitManual, child: Text('Pair'.tr)),
        ],
      ),
      _Step.readingPhoto => _frame(
        icon: Icons.photo_library_outlined,
        title: 'Reading the photo…'.tr,
        message: 'Looking for the QR code on the label.'.tr,
        body: const [
          SizedBox(height: AppSpacing.lg),
          Center(child: CircularProgressIndicator()),
        ],
        actions: const [],
      ),
      _Step.working => _frame(
        icon: Icons.link,
        title: 'Pairing the device…'.tr,
        message: 'This only takes a moment.'.tr,
        body: const [
          SizedBox(height: AppSpacing.lg),
          Center(child: CircularProgressIndicator()),
        ],
        actions: const [],
      ),
      _Step.ownedByOther => _frame(
        icon: Icons.lock_outline,
        title: 'This device belongs to someone else'.tr,
        message: _transferPending
            ? 'You already asked its owner to transfer it to you. You\'ll get a notification when they answer.'
                  .tr
            : 'It\'s paired with another IsdaSafe account. If they gave it to you, ask them to transfer it: they\'ll get a notification to approve.'
                  .tr,
        body: const [],
        actions: [
          if (_transferPending)
            close
          else ...[
            cancel,
            FilledButton.icon(
              onPressed: _requestTransfer,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text('Request transfer'.tr),
            ),
          ],
        ],
      ),
      _Step.transferRequested => _frame(
        icon: Icons.mark_email_read_outlined,
        title: 'Transfer requested'.tr,
        message:
            'The owner will get a notification. Once they approve, you\'ll be notified and can choose a pond for the device.'
                .tr,
        body: const [],
        actions: [close],
      ),
      _Step.error => _frame(
        icon: Icons.error_outline,
        title: 'Couldn\'t pair the device'.tr,
        message: _error ?? '',
        body: const [],
        actions: [
          cancel,
          FilledButton(onPressed: _backToScan, child: Text('Try again'.tr)),
        ],
      ),
    };
  }

  Widget _frame({
    required IconData icon,
    required String title,
    required String message,
    required List<Widget> body,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 32,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      ...body,
                    ],
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: AppSpacing.sm,
                  overflowSpacing: AppSpacing.xs,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The camera preview, square, with a hint when the camera can't be used.
class _ScannerView extends StatelessWidget {
  const _ScannerView({required this.controller, required this.onDetect});

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ColoredBox(
              color: Colors.black,
              child: MobileScanner(
                controller: controller,
                onDetect: onDetect,
                errorBuilder: (context, error) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera access is blocked. Allow it in your browser or phone settings, or enter the code instead.'
                                .tr
                          : 'The camera isn\'t available here. Enter the code instead.'
                                .tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
