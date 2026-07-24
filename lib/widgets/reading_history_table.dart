import 'package:flutter/material.dart';

import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// One row per individual reading (most-recent first), one column per
/// metric — the raw values behind each metric's own trend chart, for when
/// a farmer wants the exact numbers rather than a line on a graph.
class ReadingHistoryTable extends StatelessWidget {
  const ReadingHistoryTable({super.key, required this.history});

  final Map<MetricType, List<SensorReading>> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.metricPalette;
    final pointCount = history[MetricType.values.first]!.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest),
        columns: [
          const DataColumn(label: Text('Time')),
          for (final type in MetricType.values)
            DataColumn(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type.icon, size: 14, color: palette.of(type)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(type.label),
                ],
              ),
            ),
        ],
        rows: [
          for (var i = pointCount - 1; i >= 0; i--)
            DataRow(
              cells: [
                DataCell(Text(_formatTimestamp(history[MetricType.values.first]![i].timestamp))),
                for (final type in MetricType.values)
                  DataCell(Text(type.format(history[type]![i].value))),
              ],
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
