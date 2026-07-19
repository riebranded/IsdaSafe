import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/mock_sensor_service.dart';

void main() {
  final service = MockSensorService();

  test('generates a reading for every metric type', () {
    final pond = Pond(id: 'p1', name: 'Pond 1');
    final snapshot = service.generateSnapshot(pond);

    for (final type in MetricType.values) {
      expect(snapshot.readings.containsKey(type), isTrue);
    }
  });

  test('readings stay within the documented realistic bands', () {
    final pond = Pond(id: 'p2', name: 'Pond 2');

    for (var i = 0; i < 20; i++) {
      final snapshot = service.generateSnapshot(pond);
      final r = snapshot.readings;

      expect(r[MetricType.temperature]!.value, inInclusiveRange(20, 34));
      expect(r[MetricType.humidity]!.value, inInclusiveRange(50, 95));
      expect(r[MetricType.ammonia]!.value, inInclusiveRange(0, 0.3));
      expect(r[MetricType.dissolvedOxygen]!.value, inInclusiveRange(1, 9));
      expect(r[MetricType.ph]!.value, inInclusiveRange(5.5, 9.5));
    }
  });

  test('different ponds produce different baselines', () {
    final pondA = Pond(id: 'pond-a', name: 'A');
    final pondB = Pond(id: 'pond-b', name: 'B');

    final snapshotA = service.generateSnapshot(pondA);
    final snapshotB = service.generateSnapshot(pondB);

    final allSame = MetricType.values.every(
      (type) => snapshotA.readings[type]!.value == snapshotB.readings[type]!.value,
    );
    expect(allSame, isFalse);
  });

  test('same pond trends around a stable baseline across refreshes', () {
    final pond = Pond(id: 'pond-stable', name: 'Stable');

    final values = List.generate(
      10,
      (_) => service.generateSnapshot(pond).readings[MetricType.temperature]!.value,
    );

    final spread = values.reduce((a, b) => a > b ? a : b) - values.reduce((a, b) => a < b ? a : b);
    // Jitter is +/-0.6, so repeated samples for one pond should stay tightly clustered.
    expect(spread, lessThan(3));
  });
}
