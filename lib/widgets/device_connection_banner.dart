import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/pond.dart';
import '../screens/notifications_screen.dart' show relativeTime;
import '../services/usb_sensor/pond_readings_store.dart';
import '../theme/app_spacing.dart';
import 'device_wifi_dialog.dart';

/// Whether [pond]'s device is online (it uploaded recently), and when it
/// isn't, a "Reconnect to WiFi" button. Nothing when the pond has no device,
/// or when it has never uploaded ([PairDevicePrompt] covers that).
class DeviceConnectionBanner extends StatelessWidget {
  const DeviceConnectionBanner({super.key, required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    final store = PondReadingsStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final deviceId = store.deviceFor(pond.id);
        final last = store.lastUploadFor(pond.id);
        final connection = store.connectionFor(pond.id);
        if (deviceId == null || last == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        if (connection == DeviceConnection.online) {
          return Row(
            children: [
              Icon(Icons.wifi, size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Device online · Last reading: {0}'.trf([relativeTime(last)]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        }

        final color = scheme.error;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final message = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.wifi_off, color: color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device offline'.tr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No reading since {0}. It may have lost its WiFi connection.'
                              .trf([relativeTime(last)]),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final button = FilledButton.tonalIcon(
                onPressed: () => showDeviceWifiDialog(
                  context,
                  deviceId: deviceId,
                  reason: WifiSetupReason.reconnect,
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(
                  'Reconnect to WiFi'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
              // Phones: the button gets its own full-width line, so neither
              // it nor the message is squeezed.
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    message,
                    const SizedBox(height: AppSpacing.md),
                    button,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: AppSpacing.md),
                  button,
                ],
              );
            },
          ),
        );
      },
    );
  }
}
