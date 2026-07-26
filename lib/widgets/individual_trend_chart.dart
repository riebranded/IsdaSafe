import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// One metric's own recent trend, plotted on its own real-value scale.
/// Answers "what did this metric actually do" for one reading type at a
/// time. Tap or drag to see the real value at that point.
class IndividualTrendChart extends StatefulWidget {
  const IndividualTrendChart({super.key, required this.type, required this.history});

  final MetricType type;
  final List<SensorReading> history;

  @override
  State<IndividualTrendChart> createState() => _IndividualTrendChartState();
}

class _IndividualTrendChartState extends State<IndividualTrendChart> {
  int? _selectedIndex;

  void _selectAt(double localX, double width) {
    final count = widget.history.length;
    if (count < 2) return;
    final fraction = (localX / width).clamp(0.0, 1.0);
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
          height: 120,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                onPanStart: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                onPanUpdate: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 120),
                  painter: _TrendPainter(
                    history: widget.history,
                    min: min,
                    max: max,
                    color: color,
                    mutedColor: theme.colorScheme.onSurfaceVariant,
                    surfaceColor: theme.colorScheme.surface,
                    selectedIndex: selectedIndex,
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.type.format(max), style: theme.textTheme.labelSmall),
            Text(widget.type.format(min), style: theme.textTheme.labelSmall),
          ],
        ),
        if (selectedIndex != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ValueTooltip(reading: widget.history[selectedIndex], color: color),
        ],
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.history,
    required this.min,
    required this.max,
    required this.color,
    required this.mutedColor,
    required this.surfaceColor,
    required this.selectedIndex,
  });

  final List<SensorReading> history;
  final double min;
  final double max;
  final Color color;
  final Color mutedColor;
  final Color surfaceColor;
  final int? selectedIndex;

  static const _inset = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _inset * 2;
    double yOf(double value) => _inset + (1 - (value - min) / (max - min)) * plotHeight;

    final dx = history.length > 1 ? size.width / (history.length - 1) : 0.0;
    final points = [for (var i = 0; i < history.length; i++) Offset(dx * i, yOf(history[i].value))];

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
      final x = dx * index;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = mutedColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      drawEmphasized(points[index]);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.history != history ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.color != color;
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            reading.type.format(reading.value),
            style: theme.textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _relativeLabel(reading.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
