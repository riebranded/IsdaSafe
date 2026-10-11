import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/free_ammonia.dart';
import '../../models/metric_type.dart';
import '../../models/pond.dart';
import '../../models/reading_bands.dart';
import '../../models/sensor_reading.dart';

/// One row of `sensor_readings`: whatever the device managed to read at
/// [time] (sensors that failed are absent).
typedef StoredReading = ({DateTime time, Map<MetricType, double> values});

/// Where paired devices and their uploaded readings come from.
abstract class PondReadingsSource {
  /// Pond ID -> device ID, for the signed-in account's paired devices.
  Future<Map<String, String>> devicesByPond();

  /// The pond's most recent readings, newest first.
  Future<List<StoredReading>> recentReadings(String pondId, {int limit = 200});
}

class SupabasePondReadingsSource implements PondReadingsSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// `sensor_readings` column per metric. The app's temperature is WATER
  /// temperature; `air_temperature` is shown alongside humidity. (Free
  /// ammonia isn't stored: it's worked out from these, see
  /// `withFreeAmmonia`.)
  static const _columns = {
    MetricType.dissolvedOxygen: 'dissolved_oxygen',
    MetricType.ph: 'ph',
    MetricType.ammonia: 'ammonia',
    MetricType.temperature: 'water_temperature',
    MetricType.humidity: 'humidity',
    MetricType.airTemperature: 'air_temperature',
  };

  @override
  Future<Map<String, String>> devicesByPond() async {
    final rows = await _client
        .from('devices')
        .select('id, pond_id')
        .not('pond_id', 'is', null);
    return {
      for (final row in rows) row['pond_id'] as String: row['id'] as String,
    };
  }

  @override
  Future<List<StoredReading>> recentReadings(
    String pondId, {
    int limit = 200,
  }) async {
    final rows = await _client
        .from('sensor_readings')
        .select('created_at, ${_columns.values.join(', ')}')
        .eq('pond_id', pondId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final row in rows)
        (
          time: DateTime.parse(row['created_at'] as String).toLocal(),
          values: {
            for (final entry in _columns.entries)
              if (row[entry.value] case final num value)
                entry.key: value.toDouble(),
          },
        ),
    ];
  }
}

/// Whether a pond has data to show.
enum PondDataState {
  /// Paired devices haven't been loaded yet.
  loading,

  /// No device paired: the pond shows no readings, only a "Pair a device"
  /// prompt.
  unpaired,

  /// Paired, but the device hasn't uploaded (or sent over USB) a reading yet.
  waiting,

  /// Has readings.
  ready,
}

/// Whether a paired device is reaching the server, judged by its uploads.
enum DeviceConnection {
  /// Uploaded within [PondReadingsStore.offlineAfterFor].
  online,

  /// Has uploaded before, but not within [PondReadingsStore.offlineAfterFor].
  offline,

  /// Paired, but no upload yet.
  neverConnected,
}

/// Which ponds have a paired IsdaSafe device, and the readings those devices
/// uploaded. App-wide singleton; screens listen to it and rebuild when it
/// reloads (every [refreshInterval] while [start]ed).
class PondReadingsStore extends ChangeNotifier {
  PondReadingsStore({PondReadingsSource? source})
    : _injected = source,
      _pairAll = false;

  /// For tests of screens unrelated to pairing: every pond counts as paired
  /// and has one healthy reading per metric. Never loads anything.
  @visibleForTesting
  PondReadingsStore.everyPondPaired() : _injected = null, _pairAll = true {
    _loaded = true;
  }

  static PondReadingsStore instance = PondReadingsStore();

  static const refreshInterval = Duration(minutes: 1);

  /// Shortest wait before calling a device offline: three missed uploads at
  /// the firmware's usual once a minute (`UPLOAD_INTERVAL_MS`).
  static const minOfflineAfter = Duration(minutes: 3);

  final PondReadingsSource? _injected;
  final bool _pairAll;
  // Created lazily so building the store never touches Supabase (tests).
  PondReadingsSource get _source =>
      _injected ?? (_supabase ??= SupabasePondReadingsSource());
  SupabasePondReadingsSource? _supabase;

  bool _loaded = false;
  Map<String, String> _devices = {};
  final Map<String, Map<MetricType, List<SensorReading>>> _history = {};
  final Map<String, DateTime> _lastUpload = {};
  final Map<String, Duration> _uploadGap = {};
  Timer? _timer;
  Future<void>? _inFlight;

  bool get loaded => _loaded;
  String? deviceFor(String pondId) =>
      _pairAll ? 'TEST00000000' : _devices[pondId];

  PondDataState stateFor(String pondId) {
    if (_pairAll) return PondDataState.ready;
    if (!_loaded) return PondDataState.loading;
    if (!_devices.containsKey(pondId)) return PondDataState.unpaired;
    final history = _history[pondId];
    if (history == null || history.values.every((list) => list.isEmpty)) {
      return PondDataState.waiting;
    }
    return PondDataState.ready;
  }

  /// When [pondId]'s device last uploaded a reading (even one where every
  /// sensor failed), or null if it never has.
  DateTime? lastUploadFor(String pondId) =>
      _pairAll ? DateTime.now() : _lastUpload[pondId];

  /// How long [pondId]'s device may go without uploading before it counts
  /// as offline: three of its usual gaps between uploads, so a device that
  /// deep-sleeps between readings isn't called offline while it sleeps.
  Duration offlineAfterFor(String pondId) {
    final gap = _uploadGap[pondId];
    if (gap == null || gap * 3 < minOfflineAfter) return minOfflineAfter;
    return gap * 3;
  }

  /// Whether [pondId]'s device is online, or null when it has no device.
  DeviceConnection? connectionFor(String pondId, {DateTime? now}) {
    if (deviceFor(pondId) == null) return null;
    final last = lastUploadFor(pondId);
    if (last == null) return DeviceConnection.neverConnected;
    return (now ?? DateTime.now()).difference(last) <= offlineAfterFor(pondId)
        ? DeviceConnection.online
        : DeviceConnection.offline;
  }

  /// The median gap between the newest uploads in [times] (oldest first),
  /// or null with fewer than two. The median ignores one-off outages.
  static Duration? _typicalGap(List<DateTime> times) {
    final recent = times.length > 11 ? times.sublist(times.length - 11) : times;
    final gaps = [
      for (var i = 1; i < recent.length; i++)
        recent[i].difference(recent[i - 1]),
    ]..sort();
    return gaps.isEmpty ? null : gaps[gaps.length ~/ 2];
  }

  /// [pondId]'s uploaded readings per metric, oldest first. Metrics the
  /// device never sent (e.g. a failed probe) have empty lists.
  Map<MetricType, List<SensorReading>> historyFor(String pondId) =>
      _history[pondId] ??
      (_pairAll
          ? _history.putIfAbsent(pondId, _healthyReadings)
          : {
              for (final type in MetricType.values)
                type: const <SensorReading>[],
            });

  /// [everyPondPaired]'s readings: each metric in the middle of its healthy
  /// band.
  static Map<MetricType, List<SensorReading>> _healthyReadings() {
    final now = DateTime.now();
    return {
      for (final type in MetricType.values)
        type: [
          SensorReading(
            type: type,
            value: switch (metricBands[type]!) {
              final b =>
                ((b.warningLow ?? b.displayMin) +
                        (b.warningHigh ?? b.displayMax)) /
                    2,
            },
            timestamp: now,
          ),
        ],
    };
  }

  /// Loads now, then keeps reloading every [refreshInterval].
  void start() {
    if (_pairAll) return;
    _timer ??= Timer.periodic(refreshInterval, (_) => refresh());
    unawaited(refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reloads paired devices and their readings. Concurrent calls share one
  /// load.
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _load() async {
    if (_pairAll) return;
    try {
      final devices = await _source.devicesByPond();
      final histories = <String, Map<MetricType, List<SensorReading>>>{};
      final lastUploads = <String, DateTime>{};
      final uploadGaps = <String, Duration>{};
      for (final pondId in devices.keys) {
        final rows = [
          // Oldest first; each row also gets its free ammonia worked out.
          for (final row in (await _source.recentReadings(pondId)).reversed)
            (time: row.time, values: withFreeAmmonia(row.values)),
        ];
        if (rows.isNotEmpty) lastUploads[pondId] = rows.last.time;
        if (_typicalGap([for (final row in rows) row.time]) case final gap?) {
          uploadGaps[pondId] = gap;
        }
        histories[pondId] = {
          for (final type in MetricType.values)
            type: [
              for (final row in rows)
                if (row.values[type] case final double value)
                  SensorReading(type: type, value: value, timestamp: row.time),
            ],
        };
      }
      _devices = devices;
      _history
        ..clear()
        ..addAll(histories);
      _lastUpload
        ..clear()
        ..addAll(lastUploads);
      _uploadGap
        ..clear()
        ..addAll(uploadGaps);
      _loaded = true;
      debugPrint(
        '[USB] paired ponds: ${devices.length}, readings loaded for '
        '${histories.values.where((h) => h.values.any((l) => l.isNotEmpty)).length}',
      );
    } catch (e) {
      // Keep showing what we had; an unreachable server shouldn't wipe the
      // dashboard. Before the first success, treat every pond as unpaired.
      debugPrint('[USB] loading paired devices failed: $e');
      _loaded = true;
    }
    notifyListeners();
  }

  /// Records a just-paired device without waiting for the next reload.
  void setDevice(String pondId, String deviceId) {
    _devices = {..._devices, pondId: deviceId};
    _loaded = true;
    notifyListeners();
    unawaited(refresh());
  }

  void removeDevice(String pondId) {
    _devices = {..._devices}..remove(pondId);
    _history.remove(pondId);
    _lastUpload.remove(pondId);
    _uploadGap.remove(pondId);
    notifyListeners();
  }

  /// Every reading [pond]'s device uploaded, as a snapshot of the metrics it
  /// has sent (ones it never sent are left out). Null when the pond has no
  /// paired device or no readings yet.
  PondSnapshot? snapshotFor(Pond pond) {
    if (stateFor(pond.id) != PondDataState.ready) return null;
    final history = historyFor(pond.id);
    return PondSnapshot(
      pond: pond,
      readings: {
        for (final type in MetricType.values)
          if (history[type]!.isNotEmpty) type: history[type]!.last,
      },
      history: {
        for (final type in MetricType.values)
          if (history[type]!.isNotEmpty)
            // Trend widgets need two points to draw a line.
            type: history[type]!.length == 1
                ? [history[type]!.first, history[type]!.first]
                : history[type]!,
      },
    );
  }
}
