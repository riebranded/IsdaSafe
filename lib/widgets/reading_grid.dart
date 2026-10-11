import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../l10n/tr.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import 'reading_card.dart';
import 'staggered_entrance.dart';

/// Grid of the 5 [ReadingCard]s (a "No reading yet" card for a metric the
/// device hasn't sent) — a single fixed 5-column row once there's
/// genuinely room for five legible cards, falling back to a responsive
/// multi-column/narrow layout below that.
class ReadingGrid extends StatelessWidget {
  const ReadingGrid({
    super.key,
    required this.readings,
    required this.history,
    this.onTapMetric,
  });

  final Map<MetricType, SensorReading> readings;
  final Map<MetricType, List<SensorReading>> history;

  /// Called with a card's metric when it's tapped; null makes the cards
  /// non-interactive.
  final ValueChanged<MetricType>? onTapMetric;

  /// Minimum width this grid's own box needs before a single fixed 5-column
  /// row is comfortable (~120px per card). Below it we fall back to the
  /// responsive delegate. Keyed off the grid's real constraints — not the
  /// window — because the same body is embedded in the map page's ~360px
  /// side panel while the window is still "wide"; keying off MediaQuery
  /// there crammed 5 columns into that panel and overflowed every card.
  static const double _fiveColumnMinWidth = 600;

  @override
  Widget build(BuildContext context) {
    final windowIsWide =
        MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useFixedFive =
            windowIsWide && constraints.maxWidth >= _fiveColumnMinWidth;

        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: useFixedFive
              ? const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.72,
                )
              : const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.72,
                ),
          children: [
            for (final (index, type) in MetricType.primary.indexed)
              StaggeredEntrance(
                index: index,
                child: switch (readings[type]) {
                  final reading? => ReadingCard(
                    reading: reading,
                    history: history[type] ?? [reading],
                    onTap: onTapMetric == null
                        ? null
                        : () => onTapMetric!(type),
                  ),
                  null => _NoReadingCard(
                    type: type,
                    onTap: onTapMetric == null
                        ? null
                        : () => onTapMetric!(type),
                  ),
                },
              ),
          ],
        );
      },
    );
  }
}

/// A metric the device hasn't sent a value for (e.g. its probe isn't
/// connected).
class _NoReadingCard extends StatelessWidget {
  const _NoReadingCard({required this.type, this.onTap});

  final MetricType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, size: 18, color: muted),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      type.label,
                      style: theme.textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '—',
                style: theme.textTheme.titleLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No reading yet'.tr,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
