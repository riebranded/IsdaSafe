import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import 'reading_card.dart';
import 'staggered_entrance.dart';

/// Grid of the 5 [ReadingCard]s — a single fixed 5-column row once there's
/// genuinely room for five legible cards, falling back to a responsive
/// multi-column/narrow layout below that.
class ReadingGrid extends StatelessWidget {
  const ReadingGrid({super.key, required this.readings, required this.history});

  final Map<MetricType, SensorReading> readings;
  final Map<MetricType, List<SensorReading>> history;

  /// Minimum width this grid's own box needs before a single fixed 5-column
  /// row is comfortable (~120px per card). Below it we fall back to the
  /// responsive delegate. Keyed off the grid's real constraints — not the
  /// window — because the same body is embedded in the map page's ~360px
  /// side panel while the window is still "wide"; keying off MediaQuery
  /// there crammed 5 columns into that panel and overflowed every card.
  static const double _fiveColumnMinWidth = 600;

  @override
  Widget build(BuildContext context) {
    final windowIsWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useFixedFive = windowIsWide && constraints.maxWidth >= _fiveColumnMinWidth;

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
            for (final (index, type) in MetricType.values.indexed)
              StaggeredEntrance(
                index: index,
                child: ReadingCard(reading: readings[type]!, history: history[type]!),
              ),
          ],
        );
      },
    );
  }
}
