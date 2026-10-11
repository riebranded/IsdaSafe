import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/weather_context.dart';
import '../theme/app_spacing.dart';
import 'status_badge.dart';

/// "Weather around the pond": humidity and air temperature, and what that
/// weather is doing to the water readings right now ([weatherInsights]).
/// Nothing when the device hasn't sent humidity.
class WeatherContextCard extends StatelessWidget {
  const WeatherContextCard({super.key, required this.snapshot});

  final PondSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final humidity = snapshot.reading(MetricType.humidity);
    if (humidity == null) return const SizedBox.shrink();
    final air = snapshot.reading(MetricType.airTemperature);
    final insights = weatherInsights(
      snapshot.readings,
      history: snapshot.history,
    );
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, size: 20, color: muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Weather around the pond'.tr,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  [
                    '${MetricType.humidity.format(humidity.value)} '
                        '${weatherFeel(humidity.value).toLowerCase()}',
                    if (air != null)
                      MetricType.airTemperature.format(air.value),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (insights.isEmpty)
              Text(
                'No weather risks to the water right now.'.tr,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              )
            else
              for (final (index, insight) in insights.indexed) ...[
                if (index > 0) const SizedBox(height: AppSpacing.md),
                WeatherInsightRow(insight: insight),
              ],
          ],
        ),
      ),
    );
  }
}

/// One [WeatherInsight]: which water reading it's about, what the weather
/// is doing, and what to do. Info-only insights use the theme's accent;
/// warnings use the status colour.
class WeatherInsightRow extends StatelessWidget {
  const WeatherInsightRow({super.key, required this.insight});

  final WeatherInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = insight.severity == ReadingStatus.normal
        ? theme.colorScheme.primary
        : insight.severity.colorOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          insight.severity == ReadingStatus.normal
              ? Icons.info_outline
              : insight.severity.icon,
          size: 20,
          color: color,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${insight.title} · ${insight.affects.label}',
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(insight.message, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
