import '../models/pond.dart';
import '../models/sensor_reading.dart';
import 'usb_sensor/pond_readings_store.dart';
import 'usb_sensor/usb_sensor_hub.dart';

/// What every screen reads pond readings through.
///
/// A pond only has readings once an IsdaSafe device is paired to it (see
/// [PondReadingsStore]): until then [snapshotFor] returns null and screens
/// show a "Pair a device" prompt instead. A paired pond shows the readings its
/// device uploaded, overlaid with live USB readings when the device is
/// plugged into this computer ([UsbSensorHub]). Metrics the device has never
/// sent (e.g. while the pH/ammonia probe is disconnected) are left out, and
/// screens show "No reading yet" for them.
///
/// Not a `ChangeNotifier` — callers own their own widget state and call
/// [refreshAll] from a setState-triggering event handler (pull-to-refresh,
/// a refresh button, etc.).
class PondSnapshotCache {
  /// Combines the stored and live readings for [pond]; null when the pond has
  /// no device or no readings yet. Shared with `DashboardProvider`.
  static PondSnapshot? compose(Pond pond) {
    final store = PondReadingsStore.instance;
    final state = store.stateFor(pond.id);
    if (state == PondDataState.loading || state == PondDataState.unpaired) {
      return null;
    }
    final stored = store.snapshotFor(pond);
    return UsbSensorHub.instance.liveSnapshotFor(pond, fallback: stored) ??
        stored;
  }

  /// [pond]'s readings, or null when it has none to show (no paired device,
  /// no readings yet, or still loading — see [PondReadingsStore.stateFor]).
  PondSnapshot? snapshotFor(Pond pond) => compose(pond);

  void refreshAll(List<Pond> ponds) => PondReadingsStore.instance.refresh();

  void discard(String pondId) {}
}
