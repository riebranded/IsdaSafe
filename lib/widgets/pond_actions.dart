import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/tr.dart';
import '../models/pond.dart';
import '../models/pond_verification.dart';
import '../providers/pond_provider.dart';
import '../services/usb_sensor/device_registry.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../services/usb_sensor/usb_sensor_hub.dart';
import 'confirm_dialog.dart';
import 'location_picker_map.dart';
import 'pond_dialogs.dart';

/// Pond actions shared by the pond list and the pond page's "Pond & device"
/// panel.

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Moves [pond] to a new spot. A new location means a new verification: the
/// pond leaves the dashboard until the new spot is confirmed, like a newly
/// added pond. Its paired device stays paired and keeps recording. Returns
/// true when the location was changed.
Future<bool> changePondLocation(BuildContext context, Pond pond) async {
  final proceed = await showConfirmDialog(
    context,
    icon: Icons.edit_location_alt_outlined,
    title: 'Change location?'.tr,
    message:
        '"{0}" will be verified again at its new location. Until that finishes it won\'t show on your dashboard. Its paired device stays paired and keeps recording.'
            .trf([pond.name]),
    confirmLabel: 'Change location'.tr,
  );
  if (!proceed || !context.mounted) return false;

  final location = await showEditLocationDialog(
    context,
    initialLatitude: pond.latitude ?? kDefaultMapCenter.latitude,
    initialLongitude: pond.longitude ?? kDefaultMapCenter.longitude,
  );
  if (location == null || !context.mounted) return false;
  if (location.latitude == pond.latitude &&
      location.longitude == pond.longitude) {
    return false; // Unchanged: nothing to verify.
  }

  final provider = context.read<PondProvider>();
  final ok = await provider.setLocation(
    pond.id,
    latitude: location.latitude,
    longitude: location.longitude,
  );
  if (!context.mounted) return ok;
  if (!ok) {
    _showError(
      context,
      'Couldn\'t save changes. Check your connection and try again.'.tr,
    );
    return false;
  }
  await showVerificationStartedDialog(
    context,
    pondName: pond.name,
    provider: provider,
    pondId: pond.id,
    method: pond.verificationMethod ?? VerificationMethod.satellite,
  );
  return true;
}

/// Unpairs [deviceId] from [pondId]: revokes its token, so its readings stop
/// being accepted until someone pairs it again. Returns true when removed.
Future<bool> removePondDevice(
  BuildContext context, {
  required String pondId,
  required String deviceId,
}) async {
  final proceed = await showConfirmDialog(
    context,
    icon: Icons.link_off,
    title: 'Remove this device?'.tr,
    message:
        'Device {0} will stop sending readings to your account. To use it again, pair it with a pond by scanning its QR label.'
            .trf([deviceId]),
    confirmLabel: 'Remove device'.tr,
    destructive: true,
  );
  if (!proceed || !context.mounted) return false;

  final ok = await DeviceRegistry.instance.unpair(deviceId);
  if (!ok) {
    if (context.mounted) {
      _showError(
        context,
        "Couldn't remove the device. Check your connection and try again.".tr,
      );
    }
    return false;
  }
  final hub = UsbSensorHub.instance;
  // The token is already revoked; also wipe it from the device if it's
  // plugged in here.
  if (hub.deviceId == deviceId) unawaited(hub.sendUnpair());
  if (hub.linkedPondId == pondId) await hub.unlink();
  PondReadingsStore.instance.removeDevice(pondId);
  return true;
}
