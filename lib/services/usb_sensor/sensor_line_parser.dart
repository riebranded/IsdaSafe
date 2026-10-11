import '../../models/metric_type.dart';

/// The firmware's per-cycle summary keys (see `runReadingCycle()` in the
/// ESP32 sketch), mapped to the app's metrics. The app's temperature metric is
/// WATER temperature (`WaterT`); `AirT` is the air around the device. The
/// firmware's `FreeNH3` isn't read: the app works it out the same way (see
/// `withFreeAmmonia`), including for uploaded readings.
const Map<String, MetricType> _keys = {
  'DO': MetricType.dissolvedOxygen,
  'pH': MetricType.ph,
  'NH3': MetricType.ammonia,
  'WaterT': MetricType.temperature,
  'AirT': MetricType.airTemperature,
  'Hum': MetricType.humidity,
};

final _pair = RegExp(
  r'(?:^|\s)(DO|pH|NH3|WaterT|AirT|Hum)=(\S+?)(?:mg/L|C|%)?(?=\s|$)',
);

/// The ESP32's factory-burned chip ID, 12 hex digits, e.g. `ID=A1B2C3D4E5F6`.
final _deviceId = RegExp(r'(?:^|\s)ID=([0-9A-Fa-f]{12})(?=\s|$)');

/// One summary line: the values the device read, and its ID (null with
/// firmware that doesn't print one yet).
typedef SensorLine = ({Map<MetricType, double> values, String? deviceId});

/// Parses one line of the IsdaSafe device's USB serial output, e.g.
///
/// `DO=6.12 mg/L  pH=7.05  NH3=0.03 mg/L  WaterT=27.4C  AirT=29.1C  Hum=78%  ID=A1B2C3D4E5F6`
///
/// Returns null for every other line the firmware prints (pin config, WiFi
/// and RS485 debug output, ...). A sensor that failed to read prints `nan`
/// and is simply left out of the result, so callers can tell which metrics
/// the device is and isn't detecting.
SensorLine? parseSensorLine(String line) {
  // Only the summary line carries both of these; the RS485 debug lines
  // mention NH3=/pH= too but never DO=.
  if (!line.contains('DO=') || !line.contains('WaterT=')) return null;

  final values = <MetricType, double>{};
  for (final match in _pair.allMatches(line)) {
    final type = _keys[match.group(1)];
    if (type == null) continue;
    final value = double.tryParse(match.group(2)!);
    if (value == null || value.isNaN || value.isInfinite) continue;
    values[type] = value;
  }
  final id = _deviceId.firstMatch(line)?.group(1)?.toUpperCase();
  return (values: values, deviceId: id);
}
