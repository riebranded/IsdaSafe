import 'package:flutter/material.dart';

enum ReadingStatus { normal, warning, critical }

/// Icon/label are theme-independent semantics. The actual [Color] for a
/// status is theme-dependent (light vs dark contrast) and lives in
/// `widgets/status_badge.dart`'s `ReadingStatusColor` extension instead.
extension ReadingStatusInfo on ReadingStatus {
  IconData get icon {
    switch (this) {
      case ReadingStatus.normal:
        return Icons.check_circle;
      case ReadingStatus.warning:
        return Icons.warning_rounded;
      case ReadingStatus.critical:
        return Icons.error;
    }
  }

  String get label {
    switch (this) {
      case ReadingStatus.normal:
        return 'Normal';
      case ReadingStatus.warning:
        return 'Warning';
      case ReadingStatus.critical:
        return 'Critical';
    }
  }
}
