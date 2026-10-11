import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/trend_range.dart';
import '../theme/app_spacing.dart';

/// The preset timeframes (15 min, Hourly, Week, Month, Year) and a "Custom"
/// button for a picked date range, shared by the Analytics page and a
/// reading's detail view. Picking a preset clears the custom range.
///
/// On wide screens they share one line (presets scrolling if needed, custom
/// on the right). On phones the presets fill the width and the custom button
/// gets its own line below, so they never overlap.
class TimeframePicker extends StatelessWidget {
  const TimeframePicker({
    super.key,
    required this.range,
    required this.custom,
    required this.customLabel,
    required this.onRange,
    required this.onCustom,
    this.onClearCustom,
  });

  final TrendRange range;

  /// The custom range in use, or null for [range].
  final DateTimeRange? custom;

  /// How [custom] is shown on its button, e.g. "10/1/2026 – 10/11/2026".
  final String? customLabel;
  final ValueChanged<TrendRange> onRange;
  final VoidCallback onCustom;

  /// Adds a clear button next to the custom button while a custom range is
  /// in use.
  final VoidCallback? onClearCustom;

  /// Below this width the presets and the custom button don't fit on one
  /// line (five presets plus "Custom", or a date range, on a phone).
  static const oneLineMinWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < oneLineMinWidth;
        final presets = SegmentedButton<TrendRange>(
          emptySelectionAllowed: true,
          // The checkmark costs each segment width a phone doesn't have.
          showSelectedIcon: !narrow,
          expandedInsets: narrow ? EdgeInsets.zero : null,
          segments: [
            for (final r in TrendRange.values)
              ButtonSegment(
                value: r,
                label: Text(r.label, maxLines: 1, softWrap: false),
              ),
          ],
          selected: custom == null ? {range} : {},
          onSelectionChanged: (ranges) {
            if (ranges.isNotEmpty) onRange(ranges.first);
          },
        );
        // A single-segment SegmentedButton so it matches the presets' height
        // and shape (and looks selected while a custom range is in use).
        final customButton = SegmentedButton<bool>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          expandedInsets: narrow ? EdgeInsets.zero : null,
          segments: [
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                customLabel ?? 'Custom'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: custom == null ? {} : {true},
          onSelectionChanged: (_) => onCustom(),
        );
        final clear = custom != null && onClearCustom != null
            ? IconButton(
                onPressed: onClearCustom,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear custom timeframe'.tr,
                visualDensity: VisualDensity.compact,
              )
            : null;

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              presets,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: customButton),
                  ?clear,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: presets,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            customButton,
            ?clear,
          ],
        );
      },
    );
  }
}
