import 'package:flutter/material.dart';

import '../models/reading_status.dart';
import '../theme/app_theme.dart';

export '../models/reading_status.dart';

extension ReadingStatusColor on ReadingStatus {
  /// The only place a [ReadingStatus] maps to an actual [Color] — reads
  /// from the theme's [StatusColors] extension so light/dark contrast is
  /// handled in one place (`theme/app_theme.dart`).
  Color colorOf(BuildContext context) {
    final colors = context.statusColors;
    switch (this) {
      case ReadingStatus.normal:
        return colors.good;
      case ReadingStatus.warning:
        return colors.warning;
      case ReadingStatus.critical:
        return colors.critical;
    }
  }
}

/// A small icon + text pill so status is never conveyed by color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ReadingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.colorOf(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12);

    return Semantics(
      label: '${status.label} status',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: labelStyle.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
