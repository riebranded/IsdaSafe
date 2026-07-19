import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import 'reading_card.dart';
import 'staggered_entrance.dart';

/// Responsive grid of the 5 [ReadingCard]s — multi-column on wide/web
/// viewports, falls back to fewer columns on narrow/phone widths.
class ReadingGrid extends StatelessWidget {
  const ReadingGrid({super.key, required this.readings});

  final Map<MetricType, SensorReading> readings;

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      maxCrossAxisExtent: 260,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 0.88,
      children: [
        for (final (index, type) in MetricType.values.indexed)
          StaggeredEntrance(index: index, child: ReadingCard(reading: readings[type]!)),
      ],
    );
  }
}
