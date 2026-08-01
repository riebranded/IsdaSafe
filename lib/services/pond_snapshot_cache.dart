import '../models/metric_type.dart';
import '../models/pond.dart';
import '../models/sensor_reading.dart';
import '../models/trend_range.dart';
import 'mock_sensor_service.dart';

/// Simple memoizing cache around [MockSensorService] so a screen can show
/// "at a glance" pond status without re-rolling mock data on every rebuild.
///
/// Not a `ChangeNotifier` — callers own their own widget state and call
/// [refreshAll] from a setState-triggering event handler (pull-to-refresh,
/// a refresh button, etc.).
class PondSnapshotCache {
  PondSnapshotCache({MockSensorService? sensorService})
    : _sensorService = sensorService ?? MockSensorService();

  final MockSensorService _sensorService;
  final Map<String, PondSnapshot> _snapshots = {};

  PondSnapshot snapshotFor(Pond pond) {
    return _snapshots.putIfAbsent(
      pond.id,
      () => _sensorService.generateSnapshot(pond),
    );
  }

  void refreshAll(List<Pond> ponds) {
    for (final pond in ponds) {
      _snapshots[pond.id] = _sensorService.generateSnapshot(pond);
    }
  }

  void discard(String pondId) => _snapshots.remove(pondId);

  /// The Analytics screen's day/week/month/year trend data — a separate,
  /// on-demand series from [snapshotFor]'s fixed recent-history window.
  List<SensorReading> historyForRange(
    Pond pond,
    MetricType type,
    TrendRange range,
  ) => _sensorService.historyForRange(pond, type, range);
}
