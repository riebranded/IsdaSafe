import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'individual_trend_chart.dart';
import 'modal_date_range_picker.dart';
import '../l10n/tr.dart';

/// Opens [MetricDetailView] for [type]: a modal dialog on wide windows, its own
/// full page on phones.
Future<void> showMetricDetail(
  BuildContext context, {
  required Pond pond,
  required MetricType type,
  required PondSnapshotCache cache,
  required TrendRange initialRange,
  DateTimeRange? initialCustom,
}) {
  final view = MetricDetailView(
    pond: pond,
    type: type,
    cache: cache,
    initialRange: initialRange,
    initialCustom: initialCustom,
  );
  if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: view,
        ),
      ),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('${type.label} · ${pond.name}')),
        body: SafeArea(child: view),
      ),
    ),
  );
}

/// A single metric in depth: its trend over a preset or custom timeframe, the
/// min / average / max for that window, and every reading in it.
class MetricDetailView extends StatefulWidget {
  const MetricDetailView({
    super.key,
    required this.pond,
    required this.type,
    required this.cache,
    required this.initialRange,
    this.initialCustom,
  });

  final Pond pond;
  final MetricType type;
  final PondSnapshotCache cache;
  final TrendRange initialRange;
  final DateTimeRange? initialCustom;

  @override
  State<MetricDetailView> createState() => _MetricDetailViewState();
}

class _MetricDetailViewState extends State<MetricDetailView> {
  late TrendRange _range = widget.initialRange;
  late DateTimeRange? _custom = widget.initialCustom;

  Future<void> _pickCustomRange() async {
    final picked = await showModalDateRangePicker(context, initial: _custom);
    if (picked == null || !mounted) return;
    setState(() => _custom = picked);
  }

  String _customLabel(DateTimeRange range) {
    String day(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return '${day(range.start)} – ${day(range.end)}';
  }

  String _fullTimestamp(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final suffix = t.hour < 12 ? 'AM'.tr : 'PM'.tr;
    final minute = t.minute.toString().padLeft(2, '0');
    return '${t.month}/${t.day}/${t.year}  $hour12:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;
    final custom = _custom;

    // The picked end date is inclusive, but never runs into the future.
    final now = DateTime.now();
    var end = now;
    if (custom != null) {
      final endOfDay = DateTime(
        custom.end.year,
        custom.end.month,
        custom.end.day,
        23,
        59,
        59,
      );
      end = endOfDay.isAfter(now) ? now : endOfDay;
    }
    final history = custom != null
        ? widget.cache.historyForPeriod(widget.pond, type, custom.start, end)
        : widget.cache.historyForRange(widget.pond, type, _range);
    final String Function(DateTime)? timeFormat = custom == null
        ? null
        : (t) => formatCustomTimestamp(t, end.difference(custom.start));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.pond.name} · ${type.label}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close'.tr,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
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
                    label: Text('Custom'.tr),
                  )
                else
                  InputChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_customLabel(custom)),
                    onPressed: _pickCustomRange,
                    onDeleted: () => setState(() => _custom = null),
                    deleteButtonTooltipMessage: 'Clear custom timeframe'.tr,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          IndividualTrendChart(
            type: type,
            history: history,
            range: _range,
            timeFormat: timeFormat,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Summary(type: type, history: history),
          const SizedBox(height: AppSpacing.lg),
          Text('Readings'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final reading in history.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(type.format(reading.value)),
              trailing: Text(
                _fullTimestamp(reading.timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.type, required this.history});

  final MetricType type;
  final List<SensorReading> history;

  @override
  Widget build(BuildContext context) {
    final values = [for (final r in history) r.value];
    if (values.isEmpty) return const SizedBox.shrink();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final color = context.metricPalette.of(type);

    Widget stat(String label, String value) => Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        stat('Lowest'.tr, type.format(min)),
        const SizedBox(width: AppSpacing.sm),
        stat('Average'.tr, type.format(avg)),
        const SizedBox(width: AppSpacing.sm),
        stat('Highest'.tr, type.format(max)),
      ],
    );
  }
}
