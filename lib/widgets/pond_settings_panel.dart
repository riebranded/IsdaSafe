import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/pond.dart';
import '../screens/notifications_screen.dart' show relativeTime;
import '../services/usb_sensor/device_registry.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../theme/app_spacing.dart';
import 'device_wifi_dialog.dart';
import 'pond_actions.dart';

/// Opens [PondSettingsPanel] as a bottom sheet. [onLocationChanged] runs after
/// the sheet closes, once the pond's location was changed.
Future<void> showPondSettingsSheet(
  BuildContext context, {
  required Pond pond,
  VoidCallback? onLocationChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pond & device'.tr,
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          PondSettingsPanel(
            pond: pond,
            onLocationChanged: () {
              Navigator.of(sheetContext).pop();
              onLocationChanged?.call();
            },
          ),
        ],
      ),
    ),
  );
}

/// The pond's location and its IsdaSafe device, each on its own row with its
/// action (change location, remove device) so none of them crowd the
/// readings.
class PondSettingsPanel extends StatefulWidget {
  const PondSettingsPanel({
    super.key,
    required this.pond,
    this.onLocationChanged,
  });

  final Pond pond;

  /// Called after the location changed (the pond is then being verified
  /// again and leaves the dashboard).
  final VoidCallback? onLocationChanged;

  @override
  State<PondSettingsPanel> createState() => _PondSettingsPanelState();
}

class _PondSettingsPanelState extends State<PondSettingsPanel> {
  late Future<String?> _deviceId = DeviceRegistry.instance.deviceForPond(
    widget.pond.id,
  );
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeLocation() => _run(() async {
    final changed = await changePondLocation(context, widget.pond);
    if (changed) widget.onLocationChanged?.call();
  });

  Future<void> _removeDevice(String deviceId) => _run(() async {
    final removed = await removePondDevice(
      context,
      pondId: widget.pond.id,
      deviceId: deviceId,
    );
    if (removed && mounted) {
      setState(() => _deviceId = Future.value(null));
    }
  });

  /// Whether the device is online (uploading), with a way to change its WiFi
  /// network or put it back on WiFi.
  Widget _connectionRow(String deviceId) {
    final store = PondReadingsStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final connection = store.connectionFor(widget.pond.id);
        final last = store.lastUploadFor(widget.pond.id);
        final online = connection == DeviceConnection.online;
        return _SettingRow(
          icon: online ? Icons.wifi : Icons.wifi_off,
          iconColor: online ? null : Theme.of(context).colorScheme.error,
          title: 'Internet'.tr,
          subtitle: last == null
              ? 'No reading received yet'.tr
              : online
              ? 'Online · Last reading: {0}'.trf([relativeTime(last)])
              : 'Offline · no reading since {0}'.trf([relativeTime(last)]),
          action: OutlinedButton.icon(
            onPressed: () => showDeviceWifiDialog(
              context,
              deviceId: deviceId,
              reason: switch (connection) {
                DeviceConnection.online => WifiSetupReason.change,
                DeviceConnection.offline => WifiSetupReason.reconnect,
                _ => WifiSetupReason.firstSetup,
              },
            ),
            icon: Icon(online ? Icons.wifi : Icons.wifi_find, size: 18),
            label: Text(switch (connection) {
              DeviceConnection.online => 'Change WiFi'.tr,
              DeviceConnection.offline => 'Reconnect to WiFi'.tr,
              _ => 'Connect to WiFi'.tr,
            }),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pond = widget.pond;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<String?>(
        future: _deviceId,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final deviceId = snapshot.data;
          return Column(
            children: [
              _SettingRow(
                icon: Icons.location_on_outlined,
                title: 'Location'.tr,
                subtitle: pond.hasLocation
                    ? '${pond.latitude!.toStringAsFixed(5)}, ${pond.longitude!.toStringAsFixed(5)}'
                    : 'No location set'.tr,
                action: OutlinedButton.icon(
                  onPressed: _busy ? null : _changeLocation,
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: Text('Change'.tr),
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.memory,
                title: 'IsdaSafe device'.tr,
                subtitle: loading
                    ? 'Loading…'.tr
                    : deviceId == null
                    ? 'No device paired'.tr
                    : 'ID {0}'.trf([deviceId]),
              ),
              if (deviceId != null) ...[
                const Divider(height: 1),
                _connectionRow(deviceId),
                const Divider(height: 1),
                _SettingRow(
                  icon: Icons.link_off,
                  iconColor: theme.colorScheme.error,
                  title: 'Remove device'.tr,
                  subtitle:
                      'Its readings stop being saved until it\'s paired again.'
                          .tr,
                  action: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _busy ? null : () => _removeDevice(deviceId),
                    child: Text('Remove'.tr),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Icon, title and subtitle, with the [action] beside them — or below them
/// when there isn't room, so the button never squeezes or covers the text.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = iconColor ?? scheme.onSurfaceVariant;

    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
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

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = this.action;
          if (action == null) return text;
          if (constraints.maxWidth >= 420) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: AppSpacing.md),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(left: 36 + AppSpacing.md),
                child: Align(alignment: Alignment.centerLeft, child: action),
              ),
            ],
          );
        },
      ),
    );
  }
}
