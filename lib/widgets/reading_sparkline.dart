import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/reading_bands.dart';
import '../models/sensor_reading.dart';
import 'status_badge.dart';

/// Compact trend line for one metric's recent [history] — answers "is this
/// getting worse" at a glance, next to [MetricRangeBar]'s "where is it now".
/// Colored by the *current* (last) point's status, matching the status
/// badge/range-bar marker elsewhere on the same card. Deliberately bare: no
/// axes, gridlines, or labels — this is a stat-tile sparkline, not a chart.
class ReadingSparkline extends StatelessWidget {
  const ReadingSparkline({super.key, required this.type, required this.history});

  final MetricType type;
  final List<SensorReading> history;

  @override
  Widget build(BuildContext context) {
    final bands = metricBands[type]!;
    final status = bands.statusFor(history.last.value);
    final color = status.colorOf(context);
    final positions = [for (final point in history) bands.positionOf(point.value)];

    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, 28),
            painter: _SparklinePainter(positions: positions, color: color),
          );
        },
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.positions, required this.color});

  final List<double> positions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    // Positions are 0 (band min) to 1 (band max) — flip so higher values sit
    // higher on screen, and inset vertically so the line never clips.
    const inset = 4.0;
    final dx = size.width / (positions.length - 1);
    Offset pointAt(int i) {
      final y = inset + (1 - positions[i]) * (size.height - inset * 2);
      return Offset(dx * i, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < positions.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final last = pointAt(positions.length - 1);
    canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.positions != positions || oldDelegate.color != color;
  }
}
