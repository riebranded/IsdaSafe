import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/trend_range.dart';
import '../providers/pond_provider.dart';
import '../services/pond_snapshot_cache.dart';
import '../services/readings_pager.dart';
import '../services/trend_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/individual_trend_chart.dart';
import '../widgets/pair_device_prompt.dart';
import '../widgets/metric_detail_view.dart';
import '../widgets/reading_history_table.dart';
import '../widgets/timeframe_picker.dart';
import '../l10n/tr.dart';

/// A pond selector plus that pond's per-metric trends and raw reading
/// history — lets a farmer switch between ponds without leaving Analytics.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.cache});

  final PondSnapshotCache cache;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String? _selectedId;
  var _selection = const TrendSelection.preset(TrendRange.hourly);

  /// Where clearing a custom range goes back to.
  var _lastPreset = TrendRange.hourly;

  /// The shown pond's trend (every metric at once) and "Individual readings"
  /// (fetched a page at a time) for [_selection]; replaced when the pond or
  /// the timeframe changes.
  TrendController? _trend;
  ReadingsPager? _pager;
  Object? _key;

  void _load(Pond pond) {
    final key = (pond.id, _selection);
    if (key == _key) return;
    _key = key;
    _trend?.dispose();
    _pager?.dispose();
    final trend = _trend = TrendController(pond, _selection);
    _pager = ReadingsPager.forTrend(trend);
  }

  @override
  void dispose() {
    _trend?.dispose();
    _pager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ponds = context.watch<PondProvider>().ponds;

    if (ponds.isEmpty) {
      return Center(
        child: Text(
          'Add a pond to see its trends here.'.tr,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final selected = ponds.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () => ponds.first,
    );
    _load(selected);
    final trend = _trend!;
    final snapshot = widget.cache.snapshotFor(selected);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<String>(
              // Rebuilt when the shown pond changes (or is renamed) so its
              // text follows.
              key: ValueKey((selected.id, selected.name)),
              width: constraints.maxWidth < 360 ? constraints.maxWidth : 320,
              label: Text('Pond'.tr),
              leadingIcon: const Icon(Icons.water_drop_outlined),
              initialSelection: selected.id,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                for (final pond in ponds)
                  DropdownMenuEntry(value: pond.id, label: pond.name),
              ],
              onSelected: (id) {
                if (id != null) setState(() => _selectedId = id);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TimeframePicker(
            selection: _selection,
            lastPreset: _lastPreset,
            onChanged: (selection) => setState(() {
              _selection = selection;
              if (selection.range case final range?) _lastPreset = range;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (snapshot == null)
            PairDevicePrompt(pond: selected)
          else ...[
            Text('Individual trends'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ListenableBuilder(
              listenable: trend,
              builder: (context, _) {
                if (trend.loading) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final step = trend.step;
                final span = trend.window.duration;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (trend.partial) ...[
                      Text(
                        'Only the latest readings could be loaded, so this '
                                'may not cover the whole timeframe.'
                            .tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    for (final type in MetricType.primary) ...[
                      IndividualTrendChart(
                        type: type,
                        history: [
                          for (final p in trend.pointsFor(type))
                            p.asReading(type),
                        ],
                        band: [
                          for (final p in trend.pointsFor(type))
                            (min: p.min, max: p.max),
                        ],
                        latest: snapshot.reading(type),
                        timeFormat: (t) => step.axisLabel(t, span),
                        tooltipTimeFormat: step.fullLabel,
                        onTap: () => showMetricDetail(
                          context,
                          pond: selected,
                          type: type,
                          cache: widget.cache,
                          initialRange: _lastPreset,
                          initialSelection: _selection,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                );
              },
            ),
            Text('Individual readings'.tr, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ReadingHistoryTable(key: ValueKey(_key), pager: _pager),
          ],
        ],
      ),
    );
  }
}
