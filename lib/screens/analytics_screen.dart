import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/metric_comparison_chart.dart';

/// A pond selector plus that pond's trend-comparison chart (the same
/// [MetricComparisonChart] used on each pond's own dashboard) — lets a
/// farmer switch between ponds without leaving Analytics.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ponds = context.watch<PondProvider>().ponds;

    if (ponds.isEmpty) {
      return Center(
        child: Text('Add a pond to see its trends here.', style: theme.textTheme.bodyMedium),
      );
    }

    final selected = ponds.firstWhere((p) => p.id == _selectedId, orElse: () => ponds.first);
    final snapshot = widget.cache.snapshotFor(selected);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: [for (final pond in ponds) ButtonSegment(value: pond.id, label: Text(pond.name))],
              selected: {selected.id},
              onSelectionChanged: (ids) => setState(() => _selectedId = ids.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Trend comparison — ${selected.name}', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          MetricComparisonChart(history: snapshot.history),
        ],
      ),
    );
  }
}
