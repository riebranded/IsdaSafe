import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/weather_context.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import 'metric_range_bar.dart';
import 'reading_sparkline.dart';
import 'status_badge.dart';

/// A single metric stat-tile: icon, label, value+unit, a trend sparkline, a
/// compact range bar showing where the value sits within its healthy band,
/// and a status badge — with a colored accent stripe (not a full-color
/// fill) carrying the status.
class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.reading,
    required this.history,
    this.onTap,
  });

  final SensorReading reading;
  final List<SensorReading> history;

  /// Makes the card tappable (e.g. to open the metric's detail view).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = metricBands[reading.type]!.statusFor(reading.value);
    final theme = Theme.of(context);
    // Humidity is weather, not water: no healthy/warning status of its own.
    final weather = reading.type == MetricType.humidity;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: weather
                    ? theme.colorScheme.outlineVariant
                    : status.colorOf(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            reading.type.icon,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Expanded(
                            child: Text(
                              reading.type.label,
                              style: theme.textTheme.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        reading.type.format(reading.value),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ReadingSparkline(type: reading.type, history: history),
                      const SizedBox(height: AppSpacing.sm),
                      MetricRangeBar(type: reading.type, value: reading.value),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: weather
                            ? _WeatherBadge(label: weatherFeel(reading.value))
                            : StatusBadge(status: status),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The humidity card's badge: how the air feels ("Muggy", "Dry",
/// "Comfortable"), in a neutral colour since it isn't a pond status.
class _WeatherBadge extends StatelessWidget {
  const _WeatherBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (theme.textTheme.labelMedium ?? const TextStyle())
                  .copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
