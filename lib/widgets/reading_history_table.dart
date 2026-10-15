import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import '../services/readings_pager.dart';
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
/// sensor's name.
///
/// Readings come from a [ReadingsPager]: only a page is fetched at first, and
/// the next one as the list is scrolled to its end, so a long timeframe never
/// downloads everything at once. Give it a key per pond and timeframe so it
/// starts over when either changes.
class ReadingHistoryTable extends StatefulWidget {
  const ReadingHistoryTable({super.key, this.pager, this.history, this.types})
    : assert(pager != null || history != null);

  /// Fetches the timeframe's readings page by page. Owned by the caller.
  final ReadingsPager? pager;

  /// Readings already in memory, per metric and oldest first, used instead
  /// of [pager].
  final Map<MetricType, List<SensorReading>>? history;

  /// Only these metrics' columns; by default every metric with a value.
  final List<MetricType>? types;

  @override
  State<ReadingHistoryTable> createState() => _ReadingHistoryTableState();
}

class _ReadingHistoryTableState extends State<ReadingHistoryTable> {
  ReadingsPager? _own;

  ReadingsPager get _pager => widget.pager ?? _own!;

  @override
  void initState() {
    super.initState();
    if (widget.pager == null) {
      final history = widget.history!;
      final end = DateTime.now().add(const Duration(days: 3650));
      _own = ReadingsPager(
        pondId: '',
        start: DateTime(1970),
        end: end,
        source: MemoryReadingsPageSource(history),
      );
    }
    // The first page; the rest as the list is scrolled to its end.
    _pager.loadMore();
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _pager, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pager = _pager;
    final wanted = widget.types ?? MetricType.values;

    // One row per reading time. A device's metrics can have gaps (a sensor
    // that failed to read), so a cell may be empty.
    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final row in pager.rows) {
      final values = {
        for (final e in row.values.entries)
          if (wanted.contains(e.key)) e.key: e.value,
      };
      if (values.isNotEmpty) byTime[row.time] = values;
    }
    // Leave out metrics the device never sent, rather than a column of
    // dashes.
    final types = [
      for (final type in wanted)
        if (byTime.values.any((v) => v.containsKey(type))) type,
    ];
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));

    if (times.isEmpty) {
      if (pager.loading || (pager.remaining > 0 && pager.error == null)) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_rows_outlined, color: muted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      pager.error == null
                          ? 'No readings in this timeframe'.tr
                          : "Couldn't load the readings.".tr,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
              // Below the message: on a narrow phone there's no room beside it.
              if (pager.error != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: pager.loadMore,
                    icon: const Icon(Icons.refresh),
                    label: Text('Retry'.tr),
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
    final remaining = pager.remaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _SummaryChip(
              icon: outOfRange == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              // Counted over the readings loaded so far.
              label: outOfRange == 0
                  ? (remaining > 0
                        ? 'None outside healthy range so far'.tr
                        : 'All within healthy range'.tr)
                  : (remaining > 0
                        ? '{0} outside healthy range so far'.trf([outOfRange])
                        : '{0} outside healthy range'.trf([outOfRange])),
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
              String label(DateTime t) => pager.withDates
                  ? (pager.step?.fullLabel(t) ??
                        TrendStep.fifteenMinutes.fullLabel(t))
                  : pager.step?.rowLabel(t) ?? _time(t);
              final rows = <Widget>[];
              rows.add(_HeaderRow(types: types));
              DateTime? currentDay;
              for (final time in times) {
                final day = DateUtils.dateOnly(time);
                if (!pager.withDates &&
                    day != currentDay &&
                    (pager.step?.withinDay ?? true)) {
                  currentDay = day;
                  rows.add(_DayHeader(label: _dayLabel(time)));
                } else if (time != times.first) {
                  rows.add(const Divider(height: 1));
                }
                rows.add(
                  _TableRow(
                    time: label(time),
                    types: types,
                    values: byTime[time]!,
                  ),
                );
              }
              final table = Column(children: rows);
              // The same table as on a wide screen; a phone scrolls it
              // sideways instead of squeezing it.
              final tableWidth =
                  _timeColumnWidth +
                  AppSpacing.lg * 2 +
                  types.length * _metricColumnWidth;
              if (constraints.maxWidth >= tableWidth) return table;
              return _SidewaysScroll(width: tableWidth, child: table);
            },
          ),
        ),
        if (pager.loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (pager.error != null)
          Center(
            child: TextButton.icon(
              onPressed: pager.loadMore,
              icon: const Icon(Icons.refresh),
              label: Text("Couldn't load more readings. Retry".tr),
            ),
          )
        else
          LazyLoadFooter(remaining: remaining, onLoadMore: pager.loadMore),
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

const _timeColumnWidth = 128.0;

/// The narrowest a metric's column gets before the table scrolls sideways.
const _metricColumnWidth = 104.0;

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

/// A column's full title: "Dissolved oxygen (mg/L)".
String _headerLabel(MetricType type) =>
    type.unit.isEmpty ? type.label : '${type.label} (${type.unit})';

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
              // A narrow column cuts its title short; hovering (or
              // long-pressing) shows it in full.
              child: Tooltip(
                message: _headerLabel(type),
                waitDuration: const Duration(milliseconds: 300),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(type.icon, size: 14, color: palette.of(type)),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        _headerLabel(type),
                        style: style,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
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
/// The table scrolled sideways on a phone, with cues that it can be: a hint
/// above while it's still at the start, a fading arrow on the right edge
/// until the last column is reached, and a visible scrollbar.
class _SidewaysScroll extends StatefulWidget {
  const _SidewaysScroll({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_SidewaysScroll> createState() => _SidewaysScrollState();
}

class _SidewaysScrollState extends State<_SidewaysScroll> {
  final _controller = ScrollController();
  var _atStart = true;
  var _atEnd = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onNotification(Notification n) {
    final metrics = switch (n) {
      ScrollNotification() => n.metrics,
      ScrollMetricsNotification() => n.metrics,
      _ => null,
    };
    if (metrics == null || metrics.axis != Axis.horizontal) return false;
    final atStart = metrics.pixels <= metrics.minScrollExtent + 4;
    final atEnd = metrics.pixels >= metrics.maxScrollExtent - 4;
    if (atStart != _atStart || atEnd != _atEnd) {
      // Notifications can arrive mid-layout; update after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _atStart = atStart;
            _atEnd = atEnd;
          });
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _atStart
              ? Container(
                  color: scheme.secondaryContainer.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs + 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swipe,
                        size: 16,
                        color: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Swipe sideways to see every sensor'.tr,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Stack(
          children: [
            NotificationListener<Notification>(
              onNotification: _onNotification,
              child: Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: widget.width, child: widget.child),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _atEnd ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 36,
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.surface.withValues(alpha: 0),
                          scheme.surface.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
