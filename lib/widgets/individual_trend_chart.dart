import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import '../l10n/tr.dart';

/// One metric as a card: on the left its name, latest value, status, healthy
/// range and when it was last updated; on the right its trend on its own
/// real-value scale. Hover or tap/drag the chart to read the value at a point.
/// On narrow screens the chart drops below the details.
class IndividualTrendChart extends StatelessWidget {
  const IndividualTrendChart({
    super.key,
    required this.type,
    required this.history,
    required this.range,
    this.timeFormat,
    this.onTap,
  });

  /// Makes the card tappable (e.g. to open a detailed view). The chart's own
  /// tap/drag scrubbing still takes precedence over it.
  final VoidCallback? onTap;

  final MetricType type;
  final List<SensorReading> history;

  /// Overrides [range]'s x-axis labels, for a custom timeframe.
  final String Function(DateTime)? timeFormat;

  /// Drives the bottom axis's date/time label granularity — must match
  /// whatever range [history] was actually fetched for (see
  /// `AnalyticsScreen`'s `_range`/`historyForRange`).
  final TrendRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = context.metricPalette.of(type);
    final latest = history.last;
    final status = metricBands[type]!.statusFor(latest.value);

    final detailsContent = _Details(
      type: type,
      latest: latest,
      status: status,
      color: color,
      showChevron: onTap != null,
    );
    final details = onTap == null
        ? detailsContent
        : InkWell(onTap: onTap, child: detailsContent);
    final chart = _Chart(
      type: type,
      history: history,
      timeFormat: timeFormat ?? range.formatTimestamp,
      color: color,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 560) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 230, child: details),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  Expanded(child: SizedBox(height: 200, child: chart)),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              Divider(height: 1, color: scheme.outlineVariant),
              SizedBox(height: 200, child: chart),
            ],
          );
        },
      ),
    );
  }
}

/// The healthy band, from the warning thresholds (the range outside which a
/// reading stops being "normal").
String healthyRangeLabel(MetricType type) {
  final bands = metricBands[type]!;
  final lo = bands.warningLow, hi = bands.warningHigh;
  final unit = type.unit.isEmpty ? '' : ' ${type.unit}';
  if (lo != null && hi != null) {
    return '${type.formatValue(lo)} – ${type.formatValue(hi)}$unit';
  }
  if (hi != null) return 'Up to {0}{1}'.trf([type.formatValue(hi), unit]);
  if (lo != null) return 'At least {0}{1}'.trf([type.formatValue(lo), unit]);
  return '—';
}

class _Details extends StatelessWidget {
  const _Details({
    required this.type,
    required this.latest,
    required this.status,
    required this.color,
    required this.showChevron,
  });

  final MetricType type;
  final SensorReading latest;
  final ReadingStatus status;
  final Color color;
  final bool showChevron;

  String _healthyRange() => healthyRangeLabel(type);

  String _lastUpdated() {
    final diff = DateTime.now().difference(latest.timestamp);
    if (diff.inMinutes < 1) return 'Just now'.tr;
    if (diff.inMinutes < 60) return '{0} min ago'.trf([diff.inMinutes]);
    if (diff.inHours < 24) return '{0} hours ago'.trf([diff.inHours]);
    return '{0} days ago'.trf([diff.inDays]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = status.colorOf(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(type.icon, size: 20, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  type.label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: type.formatValue(latest.value),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (type.unit.isNotEmpty)
                  TextSpan(
                    text: ' ${type.unit}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: statusColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                status.label,
                style: theme.textTheme.labelLarge?.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Healthy range'.tr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(_healthyRange(), style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.circle, size: 6, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Last updated: {0}'.trf([_lastUpdated()]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chart extends StatefulWidget {
  const _Chart({
    required this.type,
    required this.history,
    required this.timeFormat,
    required this.color,
  });

  final MetricType type;
  final List<SensorReading> history;
  final String Function(DateTime) timeFormat;
  final Color color;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  int? _selectedIndex;

  void _selectAt(double localX, double width, double leftMargin) {
    final count = widget.history.length;
    if (count < 2) return;
    final plotWidth = width - leftMargin - _TrendPainter.rightInset;
    final fraction = ((localX - leftMargin) / plotWidth).clamp(0.0, 1.0);
    final index = (fraction * (count - 1)).round().clamp(0, count - 1);
    if (index != _selectedIndex) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = widget.history;

    final values = [for (final point in history) point.value];
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      min -= 1;
      max += 1;
    }
    // A little headroom so the line never hugs the edges.
    final pad = (max - min) * 0.08;
    min -= pad;
    max += pad;

    final labelStyle = TextStyle(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final leftMargin = _measureLeftMargin(
      [max, min],
      widget.type.formatValue,
      labelStyle,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          void select(Offset p) =>
              _selectAt(p.dx, constraints.maxWidth, leftMargin);
          return MouseRegion(
            onHover: (e) => select(e.localPosition),
            onExit: (_) => setState(() => _selectedIndex = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => select(d.localPosition),
              onPanStart: (d) => select(d.localPosition),
              onPanUpdate: (d) => select(d.localPosition),
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _TrendPainter(
                  history: history,
                  min: min,
                  max: max,
                  color: widget.color,
                  mutedColor: theme.colorScheme.onSurfaceVariant,
                  surfaceColor: theme.colorScheme.surface,
                  gridColor: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                  selectedIndex: _selectedIndex,
                  valueFormat: widget.type.format,
                  axisValueFormat: widget.type.formatValue,
                  timeFormat: widget.timeFormat,
                  leftMargin: leftMargin,
                  labelStyle: labelStyle,
                  tooltipColor: theme.colorScheme.inverseSurface,
                  tooltipTextColor: theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The widest of [values] (as formatted by [format]) plus a small gap —
/// used as the chart's left margin so the y-axis labels never clip.
double _measureLeftMargin(
  List<double> values,
  String Function(double) format,
  TextStyle style,
) {
  var widest = 0.0;
  for (final value in values) {
    final painter = TextPainter(
      text: TextSpan(text: format(value), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + AppSpacing.md;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.history,
    required this.min,
    required this.max,
    required this.color,
    required this.mutedColor,
    required this.surfaceColor,
    required this.gridColor,
    required this.selectedIndex,
    required this.valueFormat,
    required this.axisValueFormat,
    required this.timeFormat,
    required this.leftMargin,
    required this.labelStyle,
    required this.tooltipColor,
    required this.tooltipTextColor,
  });

  final List<SensorReading> history;
  final double min;
  final double max;
  final Color color;
  final Color mutedColor;
  final Color surfaceColor;
  final Color gridColor;
  final int? selectedIndex;
  final Color tooltipColor;
  final Color tooltipTextColor;

  /// Value with unit, for the tooltip.
  final String Function(double) valueFormat;

  /// Bare number, for the y-axis (the unit is already on the card).
  final String Function(double) axisValueFormat;

  /// A point's timestamp at this chart's [TrendRange] granularity.
  final String Function(DateTime) timeFormat;

  final double leftMargin;
  final TextStyle labelStyle;

  static const rightInset = 8.0;
  static const _topInset = 8.0;
  static const _xAxisHeight = 20.0;
  static const _yTicks = 5;
  static const _maxXLabels = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final plotTop = _topInset;
    final plotBottom = size.height - _xAxisHeight;
    final plotHeight = plotBottom - plotTop;
    final plotRight = size.width - rightInset;
    final plotWidth = plotRight - leftMargin;

    double yOf(double value) =>
        plotTop + (1 - (value - min) / (max - min)) * plotHeight;
    double xOf(int i) =>
        leftMargin +
        (history.length > 1
            ? plotWidth / (history.length - 1) * i
            : plotWidth / 2);

    // Light horizontal gridlines with y labels.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var t = 0; t < _yTicks; t++) {
      final value = min + (max - min) * t / (_yTicks - 1);
      final y = yOf(value);
      canvas.drawLine(Offset(leftMargin, y), Offset(plotRight, y), gridPaint);
      final label = TextPainter(
        text: TextSpan(text: axisValueFormat(value), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          leftMargin - AppSpacing.sm - label.width,
          (y - label.height / 2).clamp(0.0, plotBottom - label.height),
        ),
      );
    }

    final points = [
      for (var i = 0; i < history.length; i++)
        Offset(xOf(i), yOf(history[i].value)),
    ];

    // A smooth curve through the points (horizontal control handles, so it
    // never overshoots the data).
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }

    final area = Path.from(line)
      ..lineTo(points.last.dx, plotBottom)
      ..lineTo(points.first.dx, plotBottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTRB(leftMargin, plotTop, plotRight, plotBottom),
            ),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // X-axis labels, thinned so they never crowd each other.
    final step = (points.length / _maxXLabels).ceil().clamp(1, points.length);
    for (var i = 0; i < points.length; i += step) {
      final label = TextPainter(
        text: TextSpan(
          text: timeFormat(history[i].timestamp),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (points[i].dx - label.width / 2).clamp(
        leftMargin,
        size.width - label.width,
      );
      label.paint(canvas, Offset(x, plotBottom + 6));
    }

    final index = selectedIndex;
    if (index == null) return;

    final p = points[index];
    canvas.drawLine(
      Offset(p.dx, plotTop),
      Offset(p.dx, plotBottom),
      Paint()
        ..color = mutedColor.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(p, 5, Paint()..color = surfaceColor);
    canvas.drawCircle(p, 3.5, Paint()..color = color);

    // Dark tooltip card: time over value, kept inside the plot.
    final time = TextPainter(
      text: TextSpan(
        text: timeFormat(history[index].timestamp),
        style: TextStyle(
          fontSize: 10,
          color: tooltipTextColor.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final value = TextPainter(
      text: TextSpan(
        text: valueFormat(history[index].value),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tooltipTextColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 10.0, padY = 6.0;
    final w = (time.width > value.width ? time.width : value.width) + padX * 2;
    final h = time.height + value.height + padY * 2;
    final left = (p.dx - w / 2).clamp(0.0, size.width - w);
    // Above the point when there's room, else below it.
    final top = p.dy - h - 12 >= 0 ? p.dy - h - 12 : p.dy + 12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = tooltipColor,
    );
    time.paint(canvas, Offset(left + padX, top + padY));
    value.paint(canvas, Offset(left + padX, top + padY + time.height));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.history != history ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.color != color ||
        oldDelegate.leftMargin != leftMargin;
  }
}
