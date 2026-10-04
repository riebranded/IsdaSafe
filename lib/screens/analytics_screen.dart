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

  /// A user-picked timeframe; when set it replaces [_range].
  DateTimeRange? _custom;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange:
          _custom ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      helpText: 'Select a timeframe',
    );
    if (picked == null || !mounted) return;
    setState(() => _custom = picked);
  }

  String _customLabel(DateTimeRange range) {
    String day(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return '${day(range.start)} – ${day(range.end)}';
  }

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
    final custom = _custom;
    // The picked end date is inclusive: run to the end of that day, but never
    // into the future.
    final now = DateTime.now();
    final customStart = custom?.start;
    var effectiveEnd = now;
    if (custom != null) {
      final endOfDay = DateTime(
        custom.end.year,
        custom.end.month,
        custom.end.day,
        23,
        59,
        59,
      );
      effectiveEnd = endOfDay.isAfter(now) ? now : endOfDay;
    }
    final rangedHistory = {
      for (final type in MetricType.values)
        type: customStart != null
            ? widget.cache.historyForPeriod(
                selected,
                type,
                customStart,
                effectiveEnd,
              )
            : widget.cache.historyForRange(selected, type, _range),
    };
    final String Function(DateTime) timeFormat = customStart != null
        ? (t) => formatCustomTimestamp(t, effectiveEnd.difference(customStart))
        : _range.formatTimestamp;

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
            child: Row(
              children: [
                SegmentedButton<TrendRange>(
                  emptySelectionAllowed: true,
                  segments: [
                    for (final range in TrendRange.values)
                      ButtonSegment(value: range, label: Text(range.label)),
                  ],
                  selected: custom == null ? {_range} : {},
                  onSelectionChanged: (ranges) => setState(() {
                    _custom = null;
                    if (ranges.isNotEmpty) _range = ranges.first;
                  }),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (custom == null)
                  OutlinedButton.icon(
                    onPressed: _pickCustomRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: const Text('Custom'),
                  )
                else
                  InputChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_customLabel(custom)),
                    onPressed: _pickCustomRange,
                    onDeleted: () => setState(() => _custom = null),
                    deleteButtonTooltipMessage: 'Clear custom timeframe',
                  ),
              ],
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
              timeFormat: custom == null ? null : timeFormat,
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
