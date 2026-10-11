import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/trend_range.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/pair_device_prompt.dart';
import '../widgets/metric_detail_view.dart';
import '../widgets/modal_date_range_picker.dart';
import '../widgets/reading_history_table.dart';
import '../widgets/timeframe_picker.dart';
import '../l10n/tr.dart';

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
    final picked = await showModalDateRangePicker(context, initial: _custom);
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
          'Add a pond to see its trends here.'.tr,
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
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<String>(
              // Rebuilt when the shown pond changes (or is renamed) so its
              // text follows.
              key: ValueKey((selected.id, selected.name)),
              width: constraints.maxWidth < 360 ? constraints.maxWidth : 320,
              label: Text('Pond'.tr),
              leadingIcon: const Icon(Icons.water_drop_outlined),
              initialSelection: selected.id,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                for (final pond in ponds)
                  DropdownMenuEntry(value: pond.id, label: pond.name),
              ],
              onSelected: (id) {
                if (id != null) setState(() => _selectedId = id);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TimeframePicker(
            range: _range,
            custom: custom,
            customLabel: custom == null ? null : _customLabel(custom),
            onRange: (range) => setState(() {
              _custom = null;
              _range = range;
            }),
            onCustom: _pickCustomRange,
            onClearCustom: () => setState(() => _custom = null),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.cache.snapshotFor(selected) == null)
            PairDevicePrompt(pond: selected)
          else ...[
            Text('Individual trends'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            for (final type in MetricType.primary) ...[
              IndividualTrendChart(
                type: type,
                history: rangedHistory[type]!,
                range: _range,
                timeFormat: custom == null ? null : timeFormat,
                onTap: () => showMetricDetail(
                  context,
                  pond: selected,
                  type: type,
                  cache: widget.cache,
                  initialRange: _range,
                  initialCustom: custom,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('Individual readings'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ReadingHistoryTable(
              key: ValueKey((selected.id, _range, custom)),
              history: rangedHistory,
            ),
          ],
        ],
      ),
    );
  }
}
