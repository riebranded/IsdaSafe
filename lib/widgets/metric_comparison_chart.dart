import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// All 5 metrics' recent trends on one shared axis — each mapped through
/// [MetricBands.riskOf] rather than raw values, so "up" always means
/// "toward trouble" regardless of which direction is dangerous for that
/// metric. Answers "are these drifting together," which per-metric
/// sparklines (see `ReadingCard`) can't show. Tap or drag to see the real
/// value (with units) each line had at that point.
class MetricComparisonChart extends StatefulWidget {
  const MetricComparisonChart({super.key, required this.history});

  final Map<MetricType, List<SensorReading>> history;

  @override
  State<MetricComparisonChart> createState() => _MetricComparisonChartState();
}

class _MetricComparisonChartState extends State<MetricComparisonChart> {
  int? _selectedIndex;

  int get _pointCount => widget.history[MetricType.values.first]!.length;

  void _selectAt(double localX, double width) {
    if (_pointCount < 2) return;
    final fraction = (localX / width).clamp(0.0, 1.0);
    final index = (fraction * (_pointCount - 1)).round().clamp(0, _pointCount - 1);
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    final selectedIndex = _selectedIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                onPanStart: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                onPanUpdate: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 160),
                  painter: _ComparisonChartPainter(
                    history: widget.history,
                    palette: palette,
                    mutedColor: theme.colorScheme.onSurfaceVariant,
                    surfaceColor: theme.colorScheme.surface,
                    selectedIndex: selectedIndex,
                  ),
                ),
              );
            },
          ),
        ),
        if (selectedIndex != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ValueTooltip(history: widget.history, index: selectedIndex),
        ],
        const SizedBox(height: AppSpacing.md),
        _Legend(palette: palette),
      ],
    );
  }
}

class _ComparisonChartPainter extends CustomPainter {
  _ComparisonChartPainter({
    required this.history,
    required this.palette,
    required this.mutedColor,
    required this.surfaceColor,
    required this.selectedIndex,
  });

  final Map<MetricType, List<SensorReading>> history;
  final MetricPalette palette;
  final Color mutedColor;
  final Color surfaceColor;
  final int? selectedIndex;

  static const _topInset = 16.0;
  static const _bottomInset = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _topInset - _bottomInset;
    double yOf(double risk) => _topInset + (1 - risk) * plotHeight;

    final hairlinePaint = Paint()
      ..color = mutedColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, yOf(1)), Offset(size.width, yOf(1)), hairlinePaint);

    final label = TextPainter(
      text: TextSpan(text: 'Critical', style: TextStyle(color: mutedColor, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(0, (yOf(1) - label.height - 2).clamp(0, size.height)));

    final points = history[MetricType.values.first]!.length;
    final dx = points > 1 ? size.width / (points - 1) : 0.0;

    for (final type in MetricType.values) {
      final bands = metricBands[type]!;
      final series = history[type]!;
      final path = Path();
      for (var i = 0; i < series.length; i++) {
        final point = Offset(dx * i, yOf(bands.riskOf(series[i].value)));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.of(type)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final index = selectedIndex;
    if (index != null) {
      final x = dx * index;
      canvas.drawLine(
        Offset(x, _topInset),
        Offset(x, size.height),
        Paint()
          ..color = mutedColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      for (final type in MetricType.values) {
        final bands = metricBands[type]!;
        final point = Offset(x, yOf(bands.riskOf(history[type]![index].value)));
        canvas.drawCircle(point, 4, Paint()..color = surfaceColor);
        canvas.drawCircle(point, 3, Paint()..color = palette.of(type));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.history != history ||
        oldDelegate.palette != palette;
  }
}

/// Real values (with units) at the tapped/dragged point — the risk axis
/// itself is deliberately abstract, so this is the only place the actual
/// numbers behind the lines are recoverable.
class _ValueTooltip extends StatelessWidget {
  const _ValueTooltip({required this.history, required this.index});

  final Map<MetricType, List<SensorReading>> history;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    final timestamp = history[MetricType.values.first]![index].timestamp;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _relativeLabel(timestamp),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final type in MetricType.values)
                _ValueChip(color: palette.of(type), text: type.format(history[type]![index].value)),
            ],
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

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.xs),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// Mandatory at 5 series (dataviz series-count ladder) — keeps identity off
/// color-alone, styled like `StatusBadge`'s pill chips.
class _Legend extends StatelessWidget {
  const _Legend({required this.palette});

  final MetricPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final type in MetricType.values)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: palette.of(type).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 14, color: palette.of(type)),
                const SizedBox(width: 4),
                Text(
                  type.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.of(type),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
