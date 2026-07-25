import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/reading_bands.dart';

void main() {
  group('riskOf — temperature (two-sided bands)', () {
    final bands = metricBands[MetricType.temperature]!;

    test('is 0 throughout the normal band', () {
      expect(bands.riskOf(25), 0);
      expect(bands.riskOf(27), 0);
      expect(bands.riskOf(29), 0);
    });

    test('scales linearly toward the low critical threshold', () {
      expect(bands.riskOf(23.5), closeTo(0.5, 1e-9));
      expect(bands.riskOf(22), 1);
    });

    test('scales linearly toward the high critical threshold', () {
      expect(bands.riskOf(30.5), closeTo(0.5, 1e-9));
      expect(bands.riskOf(32), 1);
    });

    test('clamps at 1 beyond the critical threshold', () {
      expect(bands.riskOf(18), 1);
      expect(bands.riskOf(36), 1);
    });
  });

  group('riskOf — ammonia (high-only critical)', () {
    final bands = metricBands[MetricType.ammonia]!;

    test('is 0 for low/zero values (no low-side risk)', () {
      expect(bands.riskOf(0), 0);
      expect(bands.riskOf(0.02), 0);
      expect(bands.riskOf(0.05), 0);
    });

    test('rises toward the high critical threshold', () {
      expect(bands.riskOf(0.10), closeTo(0.5, 1e-9));
      expect(bands.riskOf(0.15), 1);
    });

    test('clamps at 1 beyond the critical threshold', () {
      expect(bands.riskOf(0.3), 1);
    });
  });

  group('riskOf — dissolved oxygen (low-only critical)', () {
    final bands = metricBands[MetricType.dissolvedOxygen]!;

    test('is 0 for high values (no high-side risk)', () {
      expect(bands.riskOf(9), 0);
      expect(bands.riskOf(6), 0);
      expect(bands.riskOf(4), 0);
    });

    test('rises toward the low critical threshold', () {
      expect(bands.riskOf(3), closeTo(0.5, 1e-9));
      expect(bands.riskOf(2), 1);
    });

    test('clamps at 1 beyond the critical threshold', () {
      expect(bands.riskOf(0), 1);
    });
  });
}
