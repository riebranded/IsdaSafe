import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/pond_verification.dart';
import '../providers/pond_provider.dart';
import '../services/usb_sensor/device_claim.dart';
import '../services/usb_sensor/device_registry.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../theme/app_spacing.dart';
import 'confirm_dialog.dart';
import 'device_wifi_dialog.dart';
import 'pond_dialogs.dart';
import 'qr_claim_dialog.dart';
import '../l10n/tr.dart';

/// The whole add-a-pond journey, shared by the dashboard's empty state and the
/// shell's "Add pond" button: pick name/location (and photo if in-house), save
/// the pond as pending, then tell the user it's being verified.
///
/// The device is paired AFTER verification: the "pond verified" notification
/// opens [runPairDeviceFlow]. Until a device is paired the pond shows no
/// readings. Fish species are asked right after pairing.
Future<void> runAddPondFlow(BuildContext context) async {
  final draft = await showAddPondDialog(context);
  if (draft == null || !context.mounted) return;

  final pond = await context.read<PondProvider>().addPond(
    draft.name,
    latitude: draft.latitude,
    longitude: draft.longitude,
    verification: draft.verification,
  );
  if (!context.mounted) return;
  if (pond == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't save the pond. Check your connection and try again.".tr,
        ),
      ),
    );
    return;
  }

  await showVerificationStartedDialog(
    context,
    pondName: pond.name,
    provider: context.read<PondProvider>(),
    pondId: pond.id,
    method: draft.verification.method,
    checkingLabel: draft.verification.evidencePhotos.isEmpty
        ? null
        : 'Checking the satellite view, and your photos if buildings hide the pond'
              .tr,
  );
}

/// Pairs an IsdaSafe device with a verified [pond] by scanning the device's
/// QR label (see [showQrClaimDialog]); no cable needed. From then on the pond
/// shows the readings the device sends over WiFi. Then asks for the pond's
/// fish species if it has none yet.
///
/// Opened from the "pond verified" notification and from the "Pair a device"
/// prompt on ponds without one. With [claim] (a label scanned with the
/// phone's own camera) it pairs that device straight away. Returns true once
/// paired.
Future<bool> runPairDeviceFlow(
  BuildContext context,
  Pond pond, {
  ClaimPayload? claim,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final provider = context.read<PondProvider>();
  // Pairing removes the "Pair a device" prompt [context] may belong to, so
  // the dialogs after it are shown from the navigator's.
  final navigator = Navigator.of(context);
  final deviceId = await showQrClaimDialog(context, pond: pond, initial: claim);
  if (deviceId == null || !navigator.mounted) return false;
  PondReadingsStore.instance.setDevice(pond.id, deviceId);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '{0} is now paired. Its readings appear once the device sends them over WiFi.'
            .trf([pond.name]),
      ),
    ),
  );
  await showDeviceWifiDialog(navigator.context, deviceId: deviceId);

  if (!navigator.mounted || pond.speciesNames.isNotEmpty) return true;
  final species = await showSelectSpeciesDialog(navigator.context);
  if (species != null) {
    await provider.setSpecies(
      pond.id,
      species.names,
      biomassKg: species.biomassKg,
    );
  }
  return true;
}

/// Asks which of [ponds] to use. Null if cancelled.
Future<Pond?> _pickPond(
  BuildContext context, {
  required String title,
  required String message,
  required List<Pond> ponds,
}) {
  return showDialog<Pond>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pond in ponds)
                    ListTile(
                      leading: const Icon(Icons.water_drop_outlined),
                      title: Text(pond.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(pond),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
      ],
    ),
  );
}

/// This account's verified ponds that don't have a device yet.
Future<List<Pond>> _pondsWithoutDevice(BuildContext context) async {
  final provider = context.read<PondProvider>();
  final store = PondReadingsStore.instance;
  if (provider.ponds.isEmpty) await provider.refresh();
  if (!store.loaded) await store.refresh();
  return [
    for (final pond in provider.ponds)
      if (store.deviceFor(pond.id) == null) pond,
  ];
}

/// A device's QR label scanned with the phone's own camera opened the site
/// (`?claim=...`): asks which pond it's for, then pairs it.
Future<void> openClaimLink(BuildContext context, ClaimPayload claim) async {
  final messenger = ScaffoldMessenger.of(context);
  final ponds = await _pondsWithoutDevice(context);
  if (!context.mounted) return;
  if (ponds.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'To pair device {0}, add a pond and wait for it to be verified, then scan the label again.'
              .trf([claim.deviceId]),
        ),
      ),
    );
    return;
  }
  final pond = await _pickPond(
    context,
    title: 'Pair device {0}'.trf([claim.deviceId]),
    message: 'Which pond will this device monitor?'.tr,
    ponds: ponds,
  );
  if (pond == null || !context.mounted) return;
  await runPairDeviceFlow(context, pond, claim: claim);
}

final _deviceIdInText = RegExp(r'\b[0-9A-F]{12}\b');

/// The owner of a device answers a transfer request (from its notification).
Future<void> openTransferRequest(BuildContext context, String message) async {
  final messenger = ScaffoldMessenger.of(context);
  final deviceId = _deviceIdInText.firstMatch(message)?.group(0);
  final registry = DeviceRegistry.instance;
  final requests = await registry.pendingTransferRequests();
  if (!context.mounted) return;
  final request = requests
      .where((r) => deviceId == null || r.deviceId == deviceId)
      .firstOrNull;
  if (request == null) {
    messenger.showSnackBar(
      SnackBar(content: Text('This request was already answered.'.tr)),
    );
    return;
  }

  final approve = await showDecisionDialog(
    context,
    icon: Icons.swap_horiz,
    title: 'Transfer device {0}?'.trf([request.deviceId]),
    message:
        'Someone who has this device\'s label asked for it. If you approve, the device and its future readings move to their account and it\'s removed from your pond. Its past readings stay with you. Approve only if you gave them the device.'
            .tr,
    confirmLabel: 'Transfer device'.tr,
    cancelLabel: 'Decline'.tr,
    destructive: true,
  );
  if (approve == null || !context.mounted) return;

  final ok = await registry.respondToTransfer(request.id, approve: approve);
  if (!context.mounted) return;
  if (ok && approve) await PondReadingsStore.instance.refresh();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        !ok
            ? "Couldn't send your answer. Check your connection and try again."
                  .tr
            : approve
            ? 'Device {0} was transferred.'.trf([request.deviceId])
            : 'Transfer declined.'.tr,
      ),
    ),
  );
}

/// A device was just transferred to this account (from its notification):
/// asks which pond it's for.
Future<void> openAssignTransferredDevice(
  BuildContext context,
  String message,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final deviceId = _deviceIdInText.firstMatch(message)?.group(0);
  if (deviceId == null) return;
  final ponds = await _pondsWithoutDevice(context);
  if (!context.mounted) return;
  if (ponds.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Add a pond without a device first, then open this notification again.'
              .tr,
        ),
      ),
    );
    return;
  }
  final pond = await _pickPond(
    context,
    title: 'Choose a pond for device {0}'.trf([deviceId]),
    message: 'Which pond will this device monitor?'.tr,
    ponds: ponds,
  );
  if (pond == null || !context.mounted) return;
  final ok = await DeviceRegistry.instance.assignPond(deviceId, pond.id);
  if (!context.mounted) return;
  if (ok) PondReadingsStore.instance.setDevice(pond.id, deviceId);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? '{0} is now paired. Its readings appear once the device sends them over WiFi.'
                  .trf([pond.name])
            : "Couldn't pair the device. Check your connection and try again."
                  .tr,
      ),
    ),
  );
  // A transferred device has moved to a new owner, usually a new place.
  if (ok && context.mounted) {
    await showDeviceWifiDialog(context, deviceId: deviceId);
  }
}

/// Finds the pond a "pond verified" notification is about and pairs a device
/// with it, unless it already has one.
Future<void> openPairDeviceForPond(BuildContext context, String pondId) async {
  final provider = context.read<PondProvider>();
  final messenger = ScaffoldMessenger.of(context);
  Pond? find() => provider.ponds.where((p) => p.id == pondId).firstOrNull;
  var pond = find();
  if (pond == null) {
    await provider.refresh();
    pond = find();
  }
  if (!context.mounted) return;
  if (pond == null) {
    messenger.showSnackBar(
      SnackBar(content: Text('This pond is no longer available.'.tr)),
    );
    return;
  }
  final store = PondReadingsStore.instance;
  if (!store.loaded) await store.refresh();
  if (!context.mounted) return;
  if (store.deviceFor(pond.id) != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('{0} already has a paired device.'.trf([pond.name])),
      ),
    );
    return;
  }
  await runPairDeviceFlow(context, pond);
}

/// Asks for the photos a `needs_photos` pond is waiting for (the modal with the
/// photo grid), uploads them, and tells the user the comparison has started.
/// Shared by the dashboard banner, the notification card and the snackbar.
Future<void> runAddEvidencePhotosFlow(BuildContext context, Pond pond) async {
  final provider = context.read<PondProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final photos = await showEvidencePhotosDialog(context, pondName: pond.name);
  if (photos == null || !context.mounted) return;

  final ok = await provider.submitEvidencePhotos(pond.id, photos);
  if (!context.mounted) return;
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Couldn\'t send the photos. Check your connection and try again.'.tr,
        ),
      ),
    );
    return;
  }
  await showVerificationStartedDialog(
    context,
    pondName: pond.name,
    provider: provider,
    pondId: pond.id,
    method: VerificationMethod.photo,
    checkingLabel: 'Comparing your photos with the satellite view'.tr,
  );
}

/// Opens the photo modal for [pondId] from a notification. The pond's status
/// may not have refreshed yet if the notification only just arrived, so it
/// re-fetches once before concluding the pond isn't waiting for photos.
Future<void> openAddPhotosForPond(BuildContext context, String pondId) async {
  final provider = context.read<PondProvider>();
  Pond? find() {
    for (final pond in provider.needsPhotosPonds) {
      if (pond.id == pondId) return pond;
    }
    return null;
  }

  final messenger = ScaffoldMessenger.of(context);
  var pond = find();
  if (pond == null) {
    await provider.refresh();
    pond = find();
  }
  if (!context.mounted) return;
  if (pond == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('This pond isn\'t waiting for photos any more.'.tr),
      ),
    );
    return;
  }
  await runAddEvidencePhotosFlow(context, pond);
}
