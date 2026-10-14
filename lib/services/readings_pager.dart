import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/free_ammonia.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import 'trend_service.dart';
import 'usb_sensor/pond_readings_store.dart';

/// Where a timeframe's readings are fetched from, a page at a time.
abstract class ReadingsPageSource {
  /// Readings from [start] to [end], newest first, skipping the newest
  /// [offset] and returning at most [limit].
  Future<List<StoredReading>> page(
    String pondId,
    DateTime start,
    DateTime end, {
    required int offset,
    required int limit,
  });
}

/// The `sensor_readings` table: only the requested page is downloaded.
class SupabaseReadingsPageSource implements ReadingsPageSource {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<StoredReading>> page(
    String pondId,
    DateTime start,
    DateTime end, {
    required int offset,
    required int limit,
  }) async {
    final columns = SupabasePondReadingsSource.columns;
    final rows = await _client
        .from('sensor_readings')
        .select('created_at, ${columns.values.join(', ')}')
        .eq('pond_id', pondId)
        .gte('created_at', start.toUtc().toIso8601String())
        .lte('created_at', end.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return [
      for (final row in rows)
        (
          time: DateTime.parse(row['created_at'] as String).toLocal(),
          values: {
            for (final entry in columns.entries)
              if (row[entry.value] case final num value)
                entry.key: value.toDouble(),
          },
        ),
    ];
  }
}

/// The complete readings (every sensor reported a value) of one device
/// stay ([DeviceStay]), whichever account it was under, so a past location's
/// readings can be listed even after its pond was moved, deleted or belonged
/// to someone else. The database checks the signed-in user owns or owned the
/// device; the pond ID and window passed to [page] are ignored (the stay
/// defines them).
class StayReadingsPageSource implements ReadingsPageSource {
  StayReadingsPageSource(this.stayId);

  final int stayId;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<StoredReading>> page(
    String pondId,
    DateTime start,
    DateTime end, {
    required int offset,
    required int limit,
  }) async {
    final columns = SupabasePondReadingsSource.columns;
    final rows = await _client.rpc(
      'device_stay_readings',
      params: {'p_stay_id': stayId, 'p_offset': offset, 'p_limit': limit},
    );
    return [
      for (final row in rows as List)
        (
          time: DateTime.parse(row['created_at'] as String).toLocal(),
          values: {
            for (final entry in columns.entries)
              if (row[entry.value] case final num value)
                entry.key: value.toDouble(),
          },
        ),
    ];
  }
}

/// Readings already in memory (per metric, oldest first), paged the same way.
class MemoryReadingsPageSource implements ReadingsPageSource {
  MemoryReadingsPageSource(Map<MetricType, List<SensorReading>> history)
    : _rows = _toRows(history);

  final List<StoredReading> _rows;

  static List<StoredReading> _toRows(
    Map<MetricType, List<SensorReading>> history,
  ) {
    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final entry in history.entries) {
      for (final reading in entry.value) {
        (byTime[reading.timestamp] ??= {})[entry.key] = reading.value;
      }
    }
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final t in times) (time: t, values: byTime[t]!)];
  }

  bool _inside(StoredReading r, DateTime start, DateTime end) =>
      !r.time.isBefore(start) && !r.time.isAfter(end);

  @override
  Future<List<StoredReading>> page(
    String pondId,
    DateTime start,
    DateTime end, {
    required int offset,
    required int limit,
  }) async => _rows
      .where((r) => _inside(r, start, end))
      .skip(offset)
      .take(limit)
      .toList();
}

/// A trend's steps as rows (each metric's average over the step), so the
/// readings list matches the chart: one row per 15 minutes, hour, day, ...
/// The steps are already loaded for the chart; they're only built into rows
/// a page at a time.
class TrendReadingsPageSource implements ReadingsPageSource {
  TrendReadingsPageSource(this.trend);

  final TrendController trend;
  List<StoredReading>? _rows;

  Future<List<StoredReading>> _all() async {
    if (_rows case final rows?) return rows;
    final series = await trend.loaded;
    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final entry in series.entries) {
      for (final point in entry.value) {
        (byTime[point.time] ??= {})[entry.key] = point.avg;
      }
    }
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));
    return _rows = [for (final t in times) (time: t, values: byTime[t]!)];
  }

  @override
  Future<List<StoredReading>> page(
    String pondId,
    DateTime start,
    DateTime end, {
    required int offset,
    required int limit,
  }) async => (await _all()).skip(offset).take(limit).toList();
}

/// One timeframe's readings for one pond, fetched a page at a time: rows
/// are only downloaded when [loadMore] is called, i.e. when the list is
/// opened and each time it's scrolled to its end.
class ReadingsPager extends ChangeNotifier {
  ReadingsPager({
    required this.pondId,
    required this.start,
    required this.end,
    required this._source,
    this.step,
    this.pageSize = 20,
  });

  /// [trend]'s steps, newest first: the same timeframe and grouping as its
  /// chart.
  factory ReadingsPager.forTrend(TrendController trend) => ReadingsPager(
    pondId: trend.pond.id,
    start: trend.window.start,
    end: trend.window.end,
    step: trend.step,
    source: TrendReadingsPageSource(trend),
  );

  final String pondId;
  final DateTime start;
  final DateTime end;

  /// What each row covers (its average); null when rows are single readings.
  final TrendStep? step;
  final int pageSize;
  final ReadingsPageSource _source;

  final List<StoredReading> _rows = [];
  bool _loading = false;
  bool _exhausted = false;
  String? _error;
  bool _disposed = false;

  /// Loaded so far, newest first, each with its free ammonia worked out.
  List<StoredReading> get rows => _rows;

  bool get loading => _loading;
  String? get error => _error;

  /// Whether there may be more to load: until a page comes back short.
  bool get hasMore => !_exhausted;

  /// For [LazyLoadFooter]: a page's worth while there may be more.
  int get remaining => _exhausted ? 0 : pageSize;

  /// Fetches the next page. Ignored while a page is loading or when there's
  /// nothing left.
  Future<void> loadMore() async {
    if (_loading || remaining <= 0) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await _source.page(
        pondId,
        start,
        end,
        offset: _rows.length,
        limit: pageSize,
      );
      _rows.addAll([
        for (final row in page)
          (
            time: row.time,
            // A step's average free ammonia comes with it.
            values: row.values.containsKey(MetricType.freeAmmonia)
                ? row.values
                : withFreeAmmonia(row.values),
          ),
      ]);
      if (page.length < pageSize) _exhausted = true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      debugPrint('ReadingsPager: page failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
