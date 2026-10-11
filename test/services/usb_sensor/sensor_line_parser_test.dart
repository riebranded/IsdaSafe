import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/services/usb_sensor/sensor_line_parser.dart';

import '../../support/fake_serial_link.dart';

void main() {
  test('parses the firmware summary line', () {
    final parsed = parseSensorLine(kSampleSensorLine)!;
    expect(parsed.values, {
      MetricType.dissolvedOxygen: 6.12,
      MetricType.ph: 7.05,
      MetricType.ammonia: 0.03,
      MetricType.temperature: 27.4, // WaterT
      MetricType.airTemperature: 29.1, // AirT
      MetricType.humidity: 78,
    });
    expect(parsed.deviceId, 'A1B2C3D4E5F6');
  });

  test('leaves out sensors that printed nan', () {
    final parsed = parseSensorLine(
      'DO=5.80 mg/L  pH=nan  NH3=nan mg/L  WaterT=nanC  AirT=29.1C  Hum=78%',
    )!;
    expect(parsed.values.keys, {
      MetricType.dissolvedOxygen,
      MetricType.airTemperature,
      MetricType.humidity,
    });
    expect(parsed.deviceId, isNull);
  });

  test('ignores debug and status lines', () {
    for (final line in [
      'RS485 reading: Ammonia=0.03 mg/L  pH=7.05  WaterT=27.4 C',
      '[DEBUG] RS485 values outside sensor range (NH3=0.01 pH=7.00 T=27.0)',
      'Server upload: HTTP 200',
      '',
    ]) {
      expect(parseSensorLine(line), isNull, reason: line);
    }
  });

  test('FreeNH3 is not mistaken for the total ammonia', () {
    final parsed = parseSensorLine(
      'DO=8.15 mg/L  pH=6.97  NH3=22.19 mg/L  FreeNH3=0.185 mg/L  WaterT=28.8C  AirT=29.3C  Hum=82%  ID=6C383B124B00',
    )!;
    expect(parsed.values[MetricType.ammonia], 22.19);
    expect(parsed.values.containsKey(MetricType.freeAmmonia), isFalse);
  });

  test('normalizes the device ID to upper case', () {
    final parsed = parseSensorLine(
      'DO=6.1 mg/L  pH=7.0  NH3=0.0 mg/L  WaterT=27.0C  AirT=29.0C  Hum=70%  ID=a1b2c3d4e5f6',
    )!;
    expect(parsed.deviceId, 'A1B2C3D4E5F6');
  });
}
