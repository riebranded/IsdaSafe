import '../l10n/tr.dart';
/// How far back — and at what granularity — an [IndividualTrendChart] plots.
/// Point count is kept modest (vs. e.g. 60 minute-by-minute points for
/// `fifteenMinutes`) so every point's x-axis label stays legible instead of
/// overlapping its neighbors.
enum TrendRange { fifteenMinutes, hourly, week, month, year }

extension TrendRangeInfo on TrendRange {
  String get label {
    switch (this) {
      case TrendRange.fifteenMinutes:
        return '15 min'.tr;
      case TrendRange.hourly:
        return 'Hourly'.tr;
      case TrendRange.week:
        return 'Week'.tr;
      case TrendRange.month:
        return 'Month'.tr;
      case TrendRange.year:
        return 'Year'.tr;
    }
  }

  int get pointCount {
    switch (this) {
      case TrendRange.fifteenMinutes:
        return 8;
      case TrendRange.hourly:
        return 8;
      case TrendRange.week:
        return 7;
      case TrendRange.month:
        // Full month names ("September") are wide — fewer points keeps
        // neighboring x-axis labels from crowding into each other.
        return 6;
      case TrendRange.year:
        return 6;
    }
  }

  Duration get interval {
    switch (this) {
      case TrendRange.fifteenMinutes:
        return const Duration(minutes: 15);
      case TrendRange.hourly:
        return const Duration(hours: 1);
      case TrendRange.week:
        return const Duration(days: 1);
      case TrendRange.month:
        return const Duration(days: 30);
      case TrendRange.year:
        return const Duration(days: 365);
    }
  }

  /// A compact x-axis label for [time], scaled to this range's granularity —
  /// e.g. "3:15 PM" for every 15 minutes, "3 AM" hourly, "Mon" for a week,
  /// "January" for a month (one point per month), the plain year number for
  /// a year (one point per year).
  String formatTimestamp(DateTime time) {
    switch (this) {
      case TrendRange.fifteenMinutes:
        final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
        final suffix = time.hour < 12 ? 'AM' : 'PM';
        final minute = time.minute.toString().padLeft(2, '0');
        return '$hour12:$minute $suffix';
      case TrendRange.hourly:
        final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
        final suffix = time.hour < 12 ? 'AM' : 'PM';
        return '$hour12 $suffix';
      case TrendRange.week:
        const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return weekdays[time.weekday - 1];
      case TrendRange.month:
        return _monthNames[time.month - 1];
      case TrendRange.year:
        return time.year.toString();
    }
  }
}

/// An x-axis label for [time] on a custom timeframe spanning [span]: the time
/// of day for a day or two, "Oct 4" for up to a few months, otherwise
/// "Oct 2026".
String formatCustomTimestamp(DateTime time, Duration span) {
  if (span <= const Duration(days: 2)) {
    return TrendRange.hourly.formatTimestamp(time);
  }
  final month = _monthNames[time.month - 1].substring(0, 3);
  if (span <= const Duration(days: 92)) return '$month ${time.day}';
  return '$month ${time.year}';
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
