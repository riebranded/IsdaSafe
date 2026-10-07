import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pond.dart';
import '../models/pond_verification.dart';
import '../providers/pond_provider.dart';
import 'pond_dialogs.dart';
import '../l10n/tr.dart';

/// The whole add-a-pond journey, shared by the dashboard's empty state and the
/// shell's "Add pond" button: pick name/location (and photo if in-house), save
/// the pond as pending, then tell the user it's being verified.
///
/// Fish species are deliberately NOT asked here: the pond isn't on the
/// dashboard until it's verified, so the dashboard offers to add them once it
/// is.
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
          'Couldn\'t save the pond. Check your connection and try again.'.tr,
        ),
      ),
    );
    return;
  }

  await showVerificationStartedDialog(
    context,
    pondName: pond.name,
    method: draft.verification.method,
    checkingLabel: draft.verification.evidencePhotos.isEmpty
        ? null
        : 'Checking the satellite view, and your photos if buildings hide the pond'.tr,
  );
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
