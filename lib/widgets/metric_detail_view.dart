import 'package:flutter/material.dart';

import '../models/metric_guidance.dart';
import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import '../models/weather_context.dart';
import '../services/pond_snapshot_cache.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'individual_trend_chart.dart';
import 'lazy_load_footer.dart';
import 'metric_range_bar.dart';
import 'modal_date_range_picker.dart';
import 'reading_history_table.dart';
import 'status_badge.dart';
import 'timeframe_picker.dart';
import 'weather_context_card.dart';
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
  MetricDetailView view({required bool showHeader}) => MetricDetailView(
    pond: pond,
    type: type,
    cache: cache,
    initialRange: initialRange,
    initialCustom: initialCustom,
    showHeader: showHeader,
  );
  if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
          child: view(showHeader: true),
        ),
      ),
    );
  }
  // The page's app bar shows the title and back button, so no header.
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(type.label),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                pond.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(child: view(showHeader: false)),
      ),
    ),
  );
}

/// One metric in depth, top to bottom:
///  * its current value(s): big, with status, where it sits in the healthy
///    range, and when it was read;
///  * what to do, when a value is outside the healthy range;
///  * what it measures and why it matters;
///  * its trend over a preset or custom timeframe, with the lowest / average /
///    highest values and when they happened;
///  * every reading in that timeframe (folded away until asked for).
/// Metrics with [MetricTypeInfo.companions] (humidity → air temperature,
/// ammonia → free ammonia) show those alongside: both current values, and a
/// switch between their trends.
class MetricDetailView extends StatefulWidget {
  const MetricDetailView({
    super.key,
    required this.pond,
    required this.type,
    required this.cache,
    required this.initialRange,
    this.initialCustom,
    this.showHeader = true,
  });

  final Pond pond;
  final MetricType type;
  final PondSnapshotCache cache;
  final TrendRange initialRange;
  final DateTimeRange? initialCustom;

  /// The title and close button; off when a page's app bar shows them.
  final bool showHeader;

  @override
  State<MetricDetailView> createState() => _MetricDetailViewState();
}

class _MetricDetailViewState extends State<MetricDetailView> {
  late TrendRange _range = widget.initialRange;
  late DateTimeRange? _custom = widget.initialCustom;

  /// Which series the trend shows (the tapped metric or a companion).
  late MetricType _trendOf = widget.type;

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
    List<SensorReading> historyOf(MetricType t) => custom != null
        ? widget.cache.historyForPeriod(widget.pond, t, custom.start, end)
        : widget.cache.historyForRange(widget.pond, t, _range);
    final series = [type, ...type.companions];
    final histories = {for (final t in series) t: historyOf(t)};
    final snapshot = widget.cache.snapshotFor(widget.pond);
    final latest = {for (final t in series) t: ?snapshot?.reading(t)};
    final String Function(DateTime)? timeFormat = custom == null
        ? null
        : (t) => formatCustomTimestamp(t, end.difference(custom.start));
    final timeframeKey = ValueKey<Object>(custom ?? _range);

    final guidance = [
      for (final t in series)
        if (latest[t] case final reading?)
          if (guidanceFor(t, reading.value) case final text?)
            (type: t, reading: reading, text: text),
    ];
    // What the weather is doing to these readings; on humidity's own page,
    // everything it's affecting.
    final weather = snapshot == null
        ? const <WeatherInsight>[]
        : [
            for (final insight in weatherInsights(
              snapshot.readings,
              history: snapshot.history,
            ))
              if (type == MetricType.humidity ||
                  series.contains(insight.affects))
                insight,
          ];

    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NowTiles(types: series, latest: latest),
          for (final g in guidance) ...[
            const SizedBox(height: AppSpacing.md),
            _GuidanceCallout(type: g.type, reading: g.reading, text: g.text),
          ],
          if (weather.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, insight) in weather.indexed) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.md),
                      WeatherInsightRow(insight: insight),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _AboutCard(types: series),
          const SizedBox(height: AppSpacing.xl),
          _SectionTitle(icon: Icons.show_chart, title: 'Trend'.tr),
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
          ),
          if (series.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _SeriesPicker(
              types: series,
              selected: _trendOf,
              onSelected: (t) => setState(() => _trendOf = t),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          IndividualTrendChart(
            type: _trendOf,
            history: histories[_trendOf]!,
            range: _range,
            timeFormat: timeFormat,
          ),
          const SizedBox(height: AppSpacing.md),
          _Summary(type: _trendOf, history: histories[_trendOf]!),
          const SizedBox(height: AppSpacing.xl),
          _ReadingsSection(
            key: timeframeKey,
            count: {
              for (final h in histories.values)
                for (final r in h) r.timestamp,
            }.length,
            child: series.length == 1
                ? _ReadingsList(type: type, history: histories[type]!)
                // One row per reading time, a column per series.
                : ReadingHistoryTable(history: histories),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          _Header(pond: widget.pond, type: type),
          const Divider(height: 1),
        ],
        Flexible(child: body),
      ],
    );
  }
}

/// The modal's title bar: the metric, its pond, and a close button. Stays put
/// while the rest scrolls.
class _Header extends StatelessWidget {
  const _Header({required this.pond, required this.type});

  final Pond pond;
  final MetricType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.metricPalette.of(type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(type.icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: theme.textTheme.titleLarge),
                Text(
                  pond.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close'.tr,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

/// The current value of each of [types], side by side when there's room.
class _NowTiles extends StatelessWidget {
  const _NowTiles({required this.types, required this.latest});

  final List<MetricType> types;
  final Map<MetricType, SensorReading> latest;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final type in types) _NowTile(type: type, reading: latest[type]),
    ];
    if (tiles.length == 1) return tiles.single;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                tile,
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tile),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One metric's latest value, big, with its status, where it sits in the
/// healthy range, and how long ago it was read.
class _NowTile extends StatelessWidget {
  const _NowTile({required this.type, required this.reading});

  final MetricType type;
  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final reading = this.reading;
    final status = reading == null
        ? null
        : metricBands[type]!.statusFor(reading.value);
    final accent = status?.colorOf(context) ?? scheme.outlineVariant;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          type.icon,
                          size: 18,
                          color: context.metricPalette.of(type),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Expanded(
                          child: Text(
                            type.label,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        if (status != null) StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      reading == null ? '—' : type.format(reading.value),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: reading == null ? muted : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (reading != null) ...[
                      MetricRangeBar(type: type, value: reading.value),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(
                      reading == null
                          ? 'No reading yet'.tr
                          : '{0} · Healthy: {1}'.trf([
                              _ago(reading.timestamp),
                              healthyRangeLabel(type),
                            ]),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Updated just now", "Updated 5 min ago", ...
String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Updated just now'.tr;
  if (diff.inMinutes < 60) return 'Updated {0} min ago'.trf([diff.inMinutes]);
  if (diff.inHours < 24) return 'Updated {0} h ago'.trf([diff.inHours]);
  return 'Updated {0} d ago'.trf([diff.inDays]);
}

/// What to do about a value outside the healthy range, tinted by how serious
/// it is.
class _GuidanceCallout extends StatelessWidget {
  const _GuidanceCallout({
    required this.type,
    required this.reading,
    required this.text,
  });

  final MetricType type;
  final SensorReading reading;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = metricBands[type]!.statusFor(reading.value);
    final color = status.colorOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What to do: {0}'.trf([type.label]),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What each of [types] measures and why it matters. The tapped metric's is
/// open; its companions' fold open on tap.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.types});

  final List<MetricType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = types.first;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'What is {0}?'.trf([main.label]),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(main.description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          for (final companion in types.skip(1)) ...[
            const Divider(height: 1),
            Theme(
              // No extra divider lines from the tile itself.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                expandedAlignment: Alignment.centerLeft,
                leading: Icon(
                  companion.icon,
                  size: 20,
                  color: context.metricPalette.of(companion),
                ),
                title: Text(
                  'What is {0}?'.trf([companion.label]),
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  Text(
                    companion.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Switches the trend between the tapped metric and its companions.
class _SeriesPicker extends StatelessWidget {
  const _SeriesPicker({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<MetricType> types;
  final MetricType selected;
  final ValueChanged<MetricType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<MetricType>(
        showSelectedIcon: false,
        segments: [
          for (final t in types)
            ButtonSegment(
              value: t,
              icon: Icon(t.icon, size: 18, color: context.metricPalette.of(t)),
              label: Text(t.label),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onSelected(s.first),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.type, required this.history});

  final MetricType type;
  final List<SensorReading> history;

  /// "2:15 PM" today, otherwise "10/9 2:15 PM".
  static String _when(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final clock =
        '$hour12:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM'.tr : 'PM'.tr}';
    return DateUtils.isSameDay(t, DateTime.now())
        ? clock
        : '${t.month}/${t.day} $clock';
  }

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final lowest = history.reduce((a, b) => b.value < a.value ? b : a);
    final highest = history.reduce((a, b) => b.value > a.value ? b : a);
    final avg =
        history.map((r) => r.value).reduce((a, b) => a + b) / history.length;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget stat(String label, double value, String? when) {
      final status = metricBands[type]!.statusFor(value);
      return Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(
                  type.format(value),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: status == ReadingStatus.normal
                        ? null
                        : status.colorOf(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (when != null)
                  Text(
                    when,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            stat('Lowest'.tr, lowest.value, _when(lowest.timestamp)),
            const SizedBox(width: AppSpacing.sm),
            stat('Average'.tr, avg, null),
            const SizedBox(width: AppSpacing.sm),
            stat('Highest'.tr, highest.value, _when(highest.timestamp)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          history.length == 1
              ? 'Based on 1 reading in this timeframe'.tr
              : 'Based on {0} readings in this timeframe'.trf([history.length]),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// Every reading in the timeframe, folded away until asked for so the trend
/// stays in view.
class _ReadingsSection extends StatelessWidget {
  const _ReadingsSection({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          leading: Icon(
            Icons.table_rows_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text('Show readings'.tr, style: theme.textTheme.titleSmall),
          subtitle: Text(
            count == 0
                ? 'No readings in this timeframe'.tr
                : count == 1
                ? '1 reading in this timeframe'.tr
                : '{0} readings in this timeframe'.trf([count]),
          ),
          children: [child],
        ),
      ),
    );
  }
}

/// Every reading in the timeframe, newest first and grouped by day. Each row
/// shows the reading's health status and how much it moved since the reading
/// before it, so spikes and out-of-range values stand out while scrolling.
class _ReadingsList extends StatefulWidget {
  const _ReadingsList({required this.type, required this.history});

  final MetricType type;

  /// Oldest first, as returned by [PondSnapshotCache].
  final List<SensorReading> history;

  @override
  State<_ReadingsList> createState() => _ReadingsListState();
}

class _ReadingsListState extends State<_ReadingsList> {
  /// Readings shown at first, and added each time the list is scrolled to
  /// its end ([LazyLoadFooter]).
  static const _pageSize = 20;
  int _shown = _pageSize;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;
    final history = widget.history;
    final total = history.length;

    // The count is in the "Show readings" fold-out this sits in.
    if (total == 0) {
      return Text(
        'No readings in this timeframe'.tr,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final shown = _shown.clamp(0, total);
    final rows = <Widget>[];
    DateTime? currentDay;
    for (var i = total - 1; i >= total - shown; i--) {
      final reading = history[i];
      final day = DateUtils.dateOnly(reading.timestamp);
      if (day != currentDay) {
        currentDay = day;
        rows.add(_DayHeader(label: _dayLabel(reading.timestamp)));
      } else {
        rows.add(const Divider(height: 1, indent: AppSpacing.lg));
      }
      rows.add(
        _ReadingRow(
          type: type,
          reading: reading,
          previous: i > 0 ? history[i - 1] : null,
          time: _time(reading.timestamp),
        ),
      );
    }

    final remaining = total - shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inside the fold-out's card: an outline, not another card.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Column(children: rows),
          ),
        ),
        LazyLoadFooter(
          remaining: remaining,
          onLoadMore: () => setState(() => _shown += _pageSize),
        ),
      ],
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

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.type,
    required this.reading,
    required this.previous,
    required this.time,
  });

  final MetricType type;
  final SensorReading reading;
  final SensorReading? previous;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = metricBands[type]!.statusFor(reading.value);
    final statusColor = status.colorOf(context);
    final isNormal = status == ReadingStatus.normal;

    // Compare at display precision so "+0.0" never shows as a change.
    final prev = previous;
    final delta = prev == null
        ? 0.0
        : double.parse(type.formatValue(reading.value)) -
              double.parse(type.formatValue(prev.value));

    return Container(
      color: isNormal ? null : statusColor.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Tooltip(
            message: status.label,
            child: Icon(status.icon, size: 18, color: statusColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            type.format(reading.value),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (delta != 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                  color: muted,
                ),
                Text(
                  type.formatValue(delta.abs()),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          if (!isNormal) ...[
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(status: status),
          ],
          const Spacer(),
          Text(
            time,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
