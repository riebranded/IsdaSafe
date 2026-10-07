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
}) async {
  final now = DateTime.now();
  final firstDate = DateTime(now.year - 2);
  final fallbackStart = now.subtract(const Duration(days: 7));

  final start = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: now,
    initialDate: initial?.start ?? fallbackStart,
    helpText: 'Select start date'.tr,
  );
  if (start == null || !context.mounted) return null;

  final initialEnd = initial?.end ?? now;
  final end = await showDatePicker(
    context: context,
    firstDate: start,
    lastDate: now,
    initialDate: initialEnd.isBefore(start) ? start : initialEnd,
    helpText: 'Select end date'.tr,
  );
  if (end == null) return null;

  return DateTimeRange(start: start, end: end);
}
