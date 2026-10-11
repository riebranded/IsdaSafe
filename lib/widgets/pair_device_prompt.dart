import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/pond.dart';
import '../services/usb_sensor/pond_readings_store.dart';
import '../theme/app_spacing.dart';
import 'add_pond_flow.dart';
import 'device_wifi_dialog.dart';

/// Shown in place of a pond's readings until it has some: a "Pair a device"
/// button when no device is paired, or a note that the paired device hasn't
/// sent a reading yet. [compact] fits inside a pond card.
class PairDevicePrompt extends StatelessWidget {
  const PairDevicePrompt({super.key, required this.pond, this.compact = false});

  final Pond pond;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = PondReadingsStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final muted = theme.colorScheme.onSurfaceVariant;
        final state = store.stateFor(pond.id);
        final deviceId = store.deviceFor(pond.id);

        if (state == PondDataState.loading) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: compact ? 18 : 28,
                height: compact ? 18 : 28,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final paired = state != PondDataState.unpaired;
        final icon = paired ? Icons.hourglass_top : Icons.sensors_off;
        final title = paired
            ? 'Waiting for the first reading'.tr
            : 'No device paired yet'.tr;
        final message = paired
            ? 'Device {0} is paired. Readings appear here once it sends one over WiFi.'
                  .trf([deviceId])
            : 'Pair an IsdaSafe device to see this pond\'s readings.'.tr;
        final button = paired
            // Usually it hasn't been put on WiFi yet (not on pond cards).
            ? (deviceId == null || compact
                  ? null
                  : OutlinedButton.icon(
                      onPressed: () =>
                          showDeviceWifiDialog(context, deviceId: deviceId),
                      icon: const Icon(Icons.wifi),
                      label: Text('Connect to WiFi'.tr),
                    ))
            : FilledButton.icon(
                onPressed: () => runPairDeviceFlow(context, pond),
                icon: const Icon(Icons.add_link),
                label: Text('Pair a device'.tr),
              );

        if (compact) {
          return Row(
            children: [
              Icon(icon, size: 20, color: muted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  paired ? title : message,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              if (button != null) ...[
                const SizedBox(width: AppSpacing.sm),
                button,
              ],
            ],
          );
        }

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Icon(icon, size: 40, color: muted),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  textAlign: TextAlign.center,
                ),
                if (button != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  button,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
