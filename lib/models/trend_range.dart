import 'package:flutter/material.dart';

import '../l10n/tr.dart';

/// How readings are grouped on a trend chart: one point per step, showing
/// that step's average (and its lowest-highest spread).
enum TrendStep { fifteenMinutes, hour, day, week, month, year }

extension TrendStepInfo on TrendStep {
  /// The step's name for the database's `pond_reading_trend`.
  String get rpcName => switch (this) {
    TrendStep.fifteenMinutes => '15min',
    TrendStep.hour => 'hour',
    TrendStep.day => 'day',
    TrendStep.week => 'week',
    TrendStep.month => 'month',
    TrendStep.year => 'year',
  };

  /// For the custom timeframe's "Group by" choice.
  String get label => switch (this) {
    TrendStep.fifteenMinutes => '15 min'.tr,
    TrendStep.hour => 'Hour'.tr,
    TrendStep.day => 'Day'.tr,
    TrendStep.week => 'Week'.tr,
    TrendStep.month => 'Month'.tr,
    TrendStep.year => 'Year'.tr,
  };

  /// "every 15 minutes", "by hour", ... for a timeframe's description.
  String get phrase => switch (this) {
    TrendStep.fifteenMinutes => 'every 15 minutes'.tr,
    TrendStep.hour => 'by hour'.tr,
    TrendStep.day => 'by day'.tr,
    TrendStep.week => 'by week'.tr,
    TrendStep.month => 'by month'.tr,
    TrendStep.year => 'by year'.tr,
  };

  /// The start of the step [t] falls in (weeks start on Monday, like the
  /// database's `date_trunc('week', ...)`).
  DateTime floor(DateTime t) => switch (this) {
    TrendStep.fifteenMinutes => DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute - t.minute % 15,
    ),
    TrendStep.hour => DateTime(t.year, t.month, t.day, t.hour),
    TrendStep.day => DateTime(t.year, t.month, t.day),
    TrendStep.week => DateTime(t.year, t.month, t.day - (t.weekday - 1)),
    TrendStep.month => DateTime(t.year, t.month),
    TrendStep.year => DateTime(t.year),
  };

  /// [t] moved by [n] steps (calendar months and years, not 30/365 days).
  DateTime add(DateTime t, int n) => switch (this) {
    TrendStep.fifteenMinutes => DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute + 15 * n,
    ),
    TrendStep.hour => DateTime(t.year, t.month, t.day, t.hour + n),
    TrendStep.day => DateTime(t.year, t.month, t.day + n),
    TrendStep.week => DateTime(t.year, t.month, t.day + 7 * n),
    TrendStep.month => DateTime(t.year, t.month + n),
    TrendStep.year => DateTime(t.year + n),
  };

  /// Roughly how long one step is, to count how many fit a timeframe.
  Duration get approxLength => switch (this) {
    TrendStep.fifteenMinutes => const Duration(minutes: 15),
    TrendStep.hour => const Duration(hours: 1),
    TrendStep.day => const Duration(days: 1),
    TrendStep.week => const Duration(days: 7),
    TrendStep.month => const Duration(days: 30),
    TrendStep.year => const Duration(days: 365),
  };

  /// A compact x-axis label for the step starting at [t], given how long the
  /// whole timeframe is: "3:15 PM", "3 PM", "Mon" / "Oct 4", "Oct 5",
  /// "Jan" / "Jan 2026", "2026".
  String axisLabel(DateTime t, Duration span) => switch (this) {
    TrendStep.fifteenMinutes => clockLabel(t),
    TrendStep.hour => _hourLabel(t),
    TrendStep.day =>
      span <= const Duration(days: 7) ? _weekdays[t.weekday - 1] : _md(t),
    TrendStep.week => _md(t),
    TrendStep.month =>
      span <= const Duration(days: 366)
          ? _months[t.month - 1].substring(0, 3)
          : '${_months[t.month - 1].substring(0, 3)} ${t.year}',
    TrendStep.year => '${t.year}',
  };

  /// Whether a step is shorter than a day, so a list of them reads best
  /// under day headers.
  bool get withinDay => index <= TrendStep.hour.index;

  /// A row in the readings list: "3:15 PM" / "3:00 PM" (under a day header),
  /// "Mon, Oct 12", "Week of Oct 5", "October 2026", "2026".
  String rowLabel(DateTime t) => withinDay ? clockLabel(t) : fullLabel(t);

  /// The whole step, for a tooltip or a lowest/highest card:
  /// "Oct 12, 3:15 PM", "Oct 12, 3 PM", "Mon, Oct 12", "Week of Oct 5",
  /// "October 2026", "2026".
  String fullLabel(DateTime t) => switch (this) {
    TrendStep.fifteenMinutes => '${_md(t)}, ${clockLabel(t)}',
    TrendStep.hour => '${_md(t)}, ${_hourLabel(t)}',
    TrendStep.day => '${_weekdays[t.weekday - 1]}, ${_md(t)}',
    TrendStep.week => 'Week of {0}'.trf([_md(t)]),
    TrendStep.month => '${_months[t.month - 1]} ${t.year}',
    TrendStep.year => '${t.year}',
  };
}

/// The preset timeframes. Each is a fixed number of [step]s back from now,
/// the current (unfinished) step included.
enum TrendRange { fifteenMinutes, hourly, daily, weekly, monthly, yearly }

extension TrendRangeInfo on TrendRange {
  String get label => switch (this) {
    TrendRange.fifteenMinutes => '15 min'.tr,
    TrendRange.hourly => 'Hourly'.tr,
    TrendRange.daily => 'Daily'.tr,
    TrendRange.weekly => 'Weekly'.tr,
    TrendRange.monthly => 'Monthly'.tr,
    TrendRange.yearly => 'Yearly'.tr,
  };

  TrendStep get step => switch (this) {
    TrendRange.fifteenMinutes => TrendStep.fifteenMinutes,
    TrendRange.hourly => TrendStep.hour,
    TrendRange.daily => TrendStep.day,
    TrendRange.weekly => TrendStep.week,
    TrendRange.monthly => TrendStep.month,
    TrendRange.yearly => TrendStep.year,
  };

  /// How many steps back it shows.
  int get pointCount => switch (this) {
    TrendRange.fifteenMinutes => 8,
    TrendRange.hourly => 24,
    TrendRange.daily => 7,
    TrendRange.weekly => 8,
    TrendRange.monthly => 12,
    TrendRange.yearly => 5,
  };

  /// "Last 2 hours", "Last 24 hours", ...
  String get span => switch (this) {
    TrendRange.fifteenMinutes => 'Last 2 hours'.tr,
    TrendRange.hourly => 'Last 24 hours'.tr,
    TrendRange.daily => 'Last 7 days'.tr,
    TrendRange.weekly => 'Last 8 weeks'.tr,
    TrendRange.monthly => 'Last 12 months'.tr,
    TrendRange.yearly => 'Last 5 years'.tr,
  };

  /// Kept for charts of raw readings (e.g. the dashboard's recent trend).
  String formatTimestamp(DateTime time) =>
      step.axisLabel(time, step.approxLength * pointCount);
}

/// What a trend shows: a preset, or a picked date range grouped by a chosen
/// (or automatic) step.
@immutable
class TrendSelection {
  const TrendSelection.preset(TrendRange this.range)
    : custom = null,
      customStep = null,
      single = false,
      anyStep = false;

  const TrendSelection.dates(
    DateTimeRange this.custom, {
    this.customStep,
    this.single = false,
    this.anyStep = false,
  }) : range = null;

  /// The preset, or null for a custom range.
  final TrendRange? range;

  /// The picked days (end day included), or null for a preset.
  final DateTimeRange? custom;

  /// The custom range's chosen step; null picks one to suit its length.
  final TrendStep? customStep;

  /// A custom range listed as single readings, not grouped (the Devices
  /// tab's "Whole visit"); [customStep] is then ignored.
  final bool single;

  /// Whether [customStep] is honoured whatever the range's length (for paged
  /// lists of rows, unlike a chart that has to stay readable).
  final bool anyStep;

  bool get isCustom => custom != null;

  /// The times shown: from the first step's start to now (or, for a custom
  /// range, the end of its last day, but never later than now).
  DateTimeRange window([DateTime? now]) {
    now ??= DateTime.now();
    final custom = this.custom;
    if (custom != null) {
      final endOfDay = DateTime(
        custom.end.year,
        custom.end.month,
        custom.end.day,
        23,
        59,
        59,
      );
      final start = DateUtils.dateOnly(custom.start);
      final end = endOfDay.isAfter(now) ? now : endOfDay;
      return DateTimeRange(
        start: start,
        end: end.isBefore(start) ? start : end,
      );
    }
    final range = this.range!;
    final step = range.step;
    return DateTimeRange(
      start: step.add(step.floor(now), -(range.pointCount - 1)),
      end: now,
    );
  }

  TrendStep get step {
    final range = this.range;
    if (range != null) return range.step;
    final span = window().duration;
    final chosen = customStep;
    // A step chosen for a different range may not suit this one.
    return chosen != null && (anyStep || stepsFor(span).contains(chosen))
        ? chosen
        : autoStep(span);
  }

  /// The steps a custom range of [span] can sensibly be grouped by: enough
  /// points to see a trend, few enough to read the chart.
  static List<TrendStep> stepsFor(Duration span) => [
    for (final step in TrendStep.values)
      if (_stepCount(span, step) <= 400 && _stepCount(span, step) >= 2) step,
  ];

  static int _stepCount(Duration span, TrendStep step) =>
      (span.inMinutes / step.approxLength.inMinutes).ceil();

  /// A step that gives a readable number of points for a range of [span].
  static TrendStep autoStep(Duration span) {
    if (span <= const Duration(days: 2)) return TrendStep.hour;
    if (span <= const Duration(days: 62)) return TrendStep.day;
    if (span <= const Duration(days: 400)) return TrendStep.week;
    return TrendStep.month;
  }

  /// "Last 24 hours · by hour", "Oct 1 – Oct 11 · by day".
  String get description => single
      ? '$windowLabel · ${'every reading'.tr}'
      : '$windowLabel · ${step.phrase}';

  /// The timeframe alone, for lists of single readings: "Last 24 hours",
  /// "Oct 1 – Oct 11".
  String get windowLabel {
    final custom = this.custom;
    return custom == null
        ? range!.span
        : '${_md(custom.start)} – ${_md(custom.end)}';
  }

  /// The custom range as a button label: "Oct 1 – Oct 11, 2026".
  String? get customLabel {
    final custom = this.custom;
    if (custom == null) return null;
    final sameYear = custom.start.year == custom.end.year;
    return sameYear
        ? '${_md(custom.start)} – ${_md(custom.end)}, ${custom.end.year}'
        : '${_md(custom.start)}, ${custom.start.year} – '
              '${_md(custom.end)}, ${custom.end.year}';
  }

  @override
  bool operator ==(Object other) =>
      other is TrendSelection &&
      other.range == range &&
      other.custom == custom &&
      other.customStep == customStep &&
      other.single == single &&
      other.anyStep == anyStep;

  @override
  int get hashCode => Object.hash(range, custom, customStep, single, anyStep);
}

/// 498124 -> "498,124".
String groupThousands(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "3:15 PM".
String clockLabel(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:${t.minute.toString().padLeft(2, '0')} $suffix';
}

String _hourLabel(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour12 ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Oct 4".
String _md(DateTime t) => '${_months[t.month - 1].substring(0, 3)} ${t.day}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _months = [
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
