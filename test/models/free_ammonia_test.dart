import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/models/free_ammonia.dart';
import 'package:isdasafev2/models/metric_type.dart';

void main() {
  test("matches the firmware's FreeNH3 for the same reading", () {
    // From the device's serial output:
    // NH3=22.19 mg/L  FreeNH3=0.185 mg/L  pH=6.97  WaterT=28.8C
    final value = freeAmmonia(totalAmmonia: 22.19, ph: 6.97, tempC: 28.8);
    expect(value, closeTo(0.185, 0.001));
  });

  test('rises with pH and temperature', () {
    final base = freeAmmonia(totalAmmonia: 1, ph: 7, tempC: 25);
    expect(freeAmmonia(totalAmmonia: 1, ph: 8, tempC: 25), greaterThan(base));
    expect(freeAmmonia(totalAmmonia: 1, ph: 7, tempC: 32), greaterThan(base));
  });

  test('withFreeAmmonia needs ammonia, pH and water temperature', () {
    final full = withFreeAmmonia({
      MetricType.ammonia: 22.19,
      MetricType.ph: 6.97,
      MetricType.temperature: 28.8,
      MetricType.humidity: 82,
    });
    expect(full[MetricType.freeAmmonia], closeTo(0.185, 0.001));
    expect(full[MetricType.humidity], 82);

    final partial = withFreeAmmonia({
      MetricType.ammonia: 22.19,
      MetricType.temperature: 28.8,
    });
    expect(partial.containsKey(MetricType.freeAmmonia), isFalse);
  });
}
