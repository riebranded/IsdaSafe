import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'lazy_load_footer.dart';
import 'status_badge.dart';
import '../l10n/tr.dart';

/// Every reading in the timeframe, newest first and grouped by day, with one
/// column per metric the device sent — the raw values behind the trend charts,
/// for when a farmer wants the exact numbers. Values outside the healthy range
/// are colored by their status so they stand out while scrolling. Wide screens
/// get a table; narrow ones a card per reading with each value under its
/// sensor's name. Readings appear a page at a time, the next page loading as
/// the list is scrolled to its end. Give it a key per pond and timeframe so
/// it starts over at the first page when either changes.
class ReadingHistoryTable extends StatefulWidget {
  const ReadingHistoryTable({super.key, required this.history});

  /// Per metric, oldest first (see `PondSnapshotCache`).
  final Map<MetricType, List<SensorReading>> history;

  @override
  State<ReadingHistoryTable> createState() => _ReadingHistoryTableState();
}

class _ReadingHistoryTableState extends State<ReadingHistoryTable> {
  static const _pageSize = 20;
  int _shown = _pageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // One row per reading time across every metric. A device's metrics can
    // have gaps (a sensor that failed to read), so a cell may be empty.
    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final type in MetricType.values) {
      for (final reading in widget.history[type] ?? const <SensorReading>[]) {
        (byTime[reading.timestamp] ??= {})[type] = reading.value;
      }
    }
    // Leave out metrics the device never sent in this timeframe, rather than
    // a column of dashes.
    final types = [
      for (final type in MetricType.values)
        if (widget.history[type]?.isNotEmpty ?? false) type,
    ];
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));

    if (times.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Icon(Icons.table_rows_outlined, color: muted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'No readings in this timeframe'.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final outOfRange = times
        .where(
          (t) => byTime[t]!.entries.any(
            (e) =>
                metricBands[e.key]!.statusFor(e.value) != ReadingStatus.normal,
          ),
        )
        .length;
    final shown = _shown.clamp(0, times.length);
    final remaining = times.length - shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _SummaryChip(
              icon: Icons.table_rows_outlined,
              label: times.length == 1
                  ? '1 reading'.tr
                  : '{0} readings'.trf([times.length]),
              color: muted,
            ),
            _SummaryChip(
              icon: outOfRange == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              label: outOfRange == 0
                  ? 'All within healthy range'.tr
                  : '{0} outside healthy range'.trf([outOfRange]),
              color: outOfRange == 0
                  ? context.statusColors.good
                  : context.statusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final rows = <Widget>[];
              if (wide) rows.add(_HeaderRow(types: types));
              DateTime? currentDay;
              for (final time in times.take(shown)) {
                final day = DateUtils.dateOnly(time);
                if (day != currentDay) {
                  currentDay = day;
                  rows.add(_DayHeader(label: _dayLabel(time)));
                } else {
                  rows.add(const Divider(height: 1));
                }
                rows.add(
                  wide
                      ? _TableRow(
                          time: _time(time),
                          types: types,
                          values: byTime[time]!,
                        )
                      : _CompactRow(
                          time: _time(time),
                          types: types,
                          values: byTime[time]!,
                        ),
                );
              }
              return Column(children: rows);
            },
          ),
        ),
        LazyLoadFooter(
          remaining: remaining,
          onLoadMore: () => setState(() => _shown += _pageSize),
        ),
      ],
    );
  }

  String _dayLabel(DateTime t) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(t);
    if (day == today) return 'Today'.tr;
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday'.tr;
    return '${t.month}/${t.day}/${t.year}';
  }

  String _time(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final suffix = t.hour < 12 ? 'AM'.tr : 'PM'.tr;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $suffix';
  }
}

const _timeColumnWidth = 96.0;

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

/// Column titles for the wide layout.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.types});

  final List<MetricType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Text('Time'.tr, style: style),
          ),
          for (final type in types)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(type.icon, size: 14, color: palette.of(type)),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      type.unit.isEmpty
                          ? type.label
                          : '${type.label} (${type.unit})',
                      style: style,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs + 2,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One reading time in the wide layout: time, then a right-aligned value per
/// metric column.
class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.time,
    required this.types,
    required this.values,
  });

  final String time;
  final List<MetricType> types;
  final Map<MetricType, double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Text(
              time,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          for (final type in types)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _Value(type: type, value: values[type], showUnit: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// One reading time in the narrow layout: the time, then a grid with each
/// metric's value under its name (two per line on a phone).
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.time,
    required this.types,
    required this.values,
  });

  final String time;
  final List<MetricType> types;
  final Map<MetricType, double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.md;
              final columns = constraints.maxWidth >= 420 ? 3 : 2;
              final cellWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final type in types)
                    SizedBox(
                      width: cellWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The sensor's name over its value.
                          Row(
                            children: [
                              Icon(
                                type.icon,
                                size: 14,
                                color: palette.of(type),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  type.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          _Value(
                            type: type,
                            value: values[type],
                            showUnit: true,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A value colored by its health status (with a dot when it's outside the
/// healthy range), or "—" when the sensor had no reading at that time.
class _Value extends StatelessWidget {
  const _Value({
    required this.type,
    required this.value,
    required this.showUnit,
  });

  final MetricType type;
  final double? value;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = this.value;
    final base = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (value == null) {
      return Text(
        '—',
        style: base?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final status = metricBands[type]!.statusFor(value);
    final normal = status == ReadingStatus.normal;
    final color = status.colorOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!normal) ...[
          Tooltip(
            message: status.label,
            child: Icon(Icons.circle, size: 8, color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        // Shrink a long value (with unit) to fit a narrow phone cell rather
        // than overflowing or cutting the number off.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              showUnit ? type.format(value) : type.formatValue(value),
              style: base?.copyWith(
                color: normal ? null : color,
                fontWeight: normal ? null : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
