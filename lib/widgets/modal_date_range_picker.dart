import 'package:flutter/material.dart';
import '../l10n/tr.dart';

/// Picks a date range with two modal calendar dialogs (start, then end).
///
/// Flutter's `showDateRangePicker` always takes over the whole screen in
/// calendar mode; the single-date picker stays a centered modal, so the range
/// is built from two of them. Returns null if either is dismissed.
Future<DateTimeRange?> showModalDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  Set<DateTime>? days,
}) async {
  final now = DateTime.now();
  // With [days] (the days that have readings), only those can be picked.
  final sorted = days == null ? null : (days.toList()..sort());
  final firstDate = sorted?.first ?? DateTime(now.year - 2);
  final lastDate = sorted?.last ?? now;
  bool selectable(DateTime d) =>
      days == null || days.contains(DateUtils.dateOnly(d));

  /// [want], or the nearest pickable day (not before [from]).
  DateTime nearest(DateTime want, DateTime from) {
    final w = DateUtils.dateOnly(want);
    if (sorted == null) return w.isBefore(from) ? from : w;
    final options = sorted.where((d) => !d.isBefore(from)).toList();
    options.sort(
      (a, b) => (a.difference(w).inHours.abs()).compareTo(
        b.difference(w).inHours.abs(),
      ),
    );
    return options.first;
  }

  final fallbackStart = now.subtract(const Duration(days: 7));

  final start = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    selectableDayPredicate: selectable,
    initialDate: nearest(initial?.start ?? fallbackStart, firstDate),
    helpText: 'Select start date'.tr,
  );
  if (start == null || !context.mounted) return null;

  final initialEnd = initial?.end ?? now;
  final end = await showDatePicker(
    context: context,
    firstDate: start,
    lastDate: lastDate,
    selectableDayPredicate: selectable,
    initialDate: nearest(initialEnd, start),
    helpText: 'Select end date'.tr,
  );
  if (end == null) return null;

  return DateTimeRange(start: start, end: end);
}
