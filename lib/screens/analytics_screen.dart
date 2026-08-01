import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/trend_range.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/reading_history_table.dart';

/// A pond selector plus that pond's per-metric trends and raw reading
/// history — lets a farmer switch between ponds without leaving Analytics.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String? _selectedId;
  var _range = TrendRange.hourly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ponds = context.watch<PondProvider>().ponds;

    if (ponds.isEmpty) {
      return Center(
        child: Text(
          'Add a pond to see its trends here.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final selected = ponds.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () => ponds.first,
    );
    final rangedHistory = {
      for (final type in MetricType.values)
        type: widget.cache.historyForRange(selected, type, _range),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: [
                for (final pond in ponds)
                  ButtonSegment(value: pond.id, label: Text(pond.name)),
              ],
              selected: {selected.id},
              onSelectionChanged: (ids) =>
                  setState(() => _selectedId = ids.first),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TrendRange>(
              segments: [
                for (final range in TrendRange.values)
                  ButtonSegment(value: range, label: Text(range.label)),
              ],
              selected: {_range},
              onSelectionChanged: (ranges) =>
                  setState(() => _range = ranges.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Individual trends', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          for (final type in MetricType.values) ...[
            IndividualTrendChart(
              type: type,
              history: rangedHistory[type]!,
              range: _range,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Individual readings', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ReadingHistoryTable(history: rangedHistory),
        ],
      ),
    );
  }
}
