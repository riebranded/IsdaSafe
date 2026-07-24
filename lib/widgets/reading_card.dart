import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
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
  const ReadingCard({super.key, required this.reading, required this.history});

  final SensorReading reading;
  final List<SensorReading> history;

  @override
  Widget build(BuildContext context) {
    final status = metricBands[reading.type]!.statusFor(reading.value);
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: status.colorOf(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(reading.type.icon, size: 18, color: theme.colorScheme.primary),
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
                      child: StatusBadge(status: status),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
