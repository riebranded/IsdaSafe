import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// One metric's own recent trend, plotted on its own real-value scale.
/// Answers "what did this metric actually do" for one reading type at a
/// time. Tap or drag to see the real value at that point.
class IndividualTrendChart extends StatefulWidget {
  const IndividualTrendChart({
    super.key,
    required this.type,
    required this.history,
    required this.range,
  });

  final MetricType type;
  final List<SensorReading> history;

  /// Drives the bottom axis's date/time label granularity — must match
  /// whatever range [history] was actually fetched for (see
  /// `AnalyticsScreen`'s `_range`/`historyForRange`).
  final TrendRange range;

  @override
  State<IndividualTrendChart> createState() => _IndividualTrendChartState();
}

class _IndividualTrendChartState extends State<IndividualTrendChart> {
  int? _selectedIndex;

  void _selectAt(double localX, double width, double leftMargin) {
    final count = widget.history.length;
    if (count < 2) return;
    final plotWidth = width - leftMargin;
    final fraction = ((localX - leftMargin) / plotWidth).clamp(0.0, 1.0);
    final index = (fraction * (count - 1)).round().clamp(0, count - 1);
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    final color = palette.of(widget.type);
    final selectedIndex = _selectedIndex;

    final values = [for (final point in widget.history) point.value];
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      min -= 1;
      max += 1;
    }

    final yAxisLabelStyle = TextStyle(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final leftMargin = _measureLeftMargin(
      [max, (max + min) / 2, min],
      widget.type.format,
      yAxisLabelStyle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.type.icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(widget.type.label, style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 160,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _selectAt(
                  d.localPosition.dx,
                  constraints.maxWidth,
                  leftMargin,
                ),
                onPanStart: (d) => _selectAt(
                  d.localPosition.dx,
                  constraints.maxWidth,
                  leftMargin,
                ),
                onPanUpdate: (d) => _selectAt(
                  d.localPosition.dx,
                  constraints.maxWidth,
                  leftMargin,
                ),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 160),
                  painter: _TrendPainter(
                    history: widget.history,
                    min: min,
                    max: max,
                    color: color,
                    mutedColor: theme.colorScheme.onSurfaceVariant,
                    surfaceColor: theme.colorScheme.surface,
                    gridColor: theme.colorScheme.outlineVariant,
                    selectedIndex: selectedIndex,
                    valueFormat: widget.type.format,
                    timeFormat: widget.range.formatTimestamp,
                    leftMargin: leftMargin,
                    yAxisLabelStyle: yAxisLabelStyle,
                  ),
                ),
              );
            },
          ),
        ),
        if (selectedIndex != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ValueTooltip(reading: widget.history[selectedIndex], color: color),
        ],
      ],
    );
  }
}

/// The widest of [values] (as formatted by [format]) plus a small gap —
/// used as the chart's left margin so the y-axis labels never clip, without
/// reserving more space than the longest one actually needs.
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
  return widest + AppSpacing.xs;
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
    required this.timeFormat,
    required this.leftMargin,
    required this.yAxisLabelStyle,
  });

  final List<SensorReading> history;
  final double min;
  final double max;
  final Color color;
  final Color mutedColor;
  final Color surfaceColor;
  final Color gridColor;
  final int? selectedIndex;

  /// Renders a value (with unit) for the y-axis gridline labels.
  final String Function(double) valueFormat;

  /// Renders a point's timestamp for its x-axis label, at this chart's
  /// selected [TrendRange] granularity.
  final String Function(DateTime) timeFormat;

  final double leftMargin;
  final TextStyle yAxisLabelStyle;

  static const _topInset = 8.0;
  static const _xAxisHeight = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotTop = _topInset;
    final plotBottom = size.height - _xAxisHeight;
    final plotHeight = plotBottom - plotTop;
    final plotWidth = size.width - leftMargin;

    double yOf(double value) =>
        plotTop + (1 - (value - min) / (max - min)) * plotHeight;
    double xOf(int i) =>
        leftMargin +
        (history.length > 1
            ? plotWidth / (history.length - 1) * i
            : plotWidth / 2);

    // Y-axis gridlines + labels (max / mid / min).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final value in [max, (max + min) / 2, min]) {
      final y = yOf(value);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width, y), gridPaint);
      final labelPainter = TextPainter(
        text: TextSpan(text: valueFormat(value), style: yAxisLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          0,
          (y - labelPainter.height / 2).clamp(
            0.0,
            plotBottom - labelPainter.height,
          ),
        ),
      );
    }

    final points = [
      for (var i = 0; i < history.length; i++)
        Offset(xOf(i), yOf(history[i].value)),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // A small marker at every recorded reading, so the line reads as
    // discrete data points rather than a smooth, sourceless curve.
    final haloPaint = Paint()..color = surfaceColor;
    final dotPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 3, haloPaint);
      canvas.drawCircle(point, 1.8, dotPaint);
    }

    void drawEmphasized(Offset point) {
      canvas.drawCircle(point, 4, haloPaint);
      canvas.drawCircle(point, 3, dotPaint);
    }

    // The current (latest) reading is always emphasized, even without
    // interaction — it's the value the rest of the dashboard reports.
    drawEmphasized(points.last);

    final index = selectedIndex;
    if (index != null) {
      final x = points[index].dx;
      canvas.drawLine(
        Offset(x, plotTop),
        Offset(x, plotBottom),
        Paint()
          ..color = mutedColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      drawEmphasized(points[index]);
    }

    // X-axis date/time label under every point.
    for (var i = 0; i < points.length; i++) {
      final isEmphasized = i == points.length - 1 || i == index;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: timeFormat(history[i].timestamp),
          style: TextStyle(
            fontSize: 9,
            color: isEmphasized ? color : mutedColor,
            fontWeight: isEmphasized ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (points[i].dx - labelPainter.width / 2).clamp(
        leftMargin,
        size.width - labelPainter.width,
      );
      labelPainter.paint(canvas, Offset(labelX, plotBottom + 3));
    }
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

class _ValueTooltip extends StatelessWidget {
  const _ValueTooltip({required this.reading, required this.color});

  final SensorReading reading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            reading.type.format(reading.value),
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _relativeLabel(reading.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _relativeLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
