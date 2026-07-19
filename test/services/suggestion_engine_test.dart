import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/fish_species.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/sensor_reading.dart';
import 'package:isdasafev2/models/species_match.dart';
import 'package:isdasafev2/services/suggestion_engine.dart';

void main() {
  final engine = SuggestionEngine();

  const species = FishSpecies(
    name: 'Test Fish',
    localName: 'Test Fish',
    tempRange: MetricRange(25, 30),
    phRange: MetricRange(7, 8),
    doRange: MetricRange(4, 8),
    ammoniaRange: MetricRange(0, 0.05),
  );

  Map<MetricType, SensorReading> readingsFor({
    double temp = 27,
    double humidity = 70,
    double ammonia = 0.02,
    double dissolvedOxygen = 6,
    double ph = 7.5,
  }) {
    final now = DateTime.now();
    return {
      MetricType.temperature: SensorReading(type: MetricType.temperature, value: temp, timestamp: now),
      MetricType.humidity: SensorReading(type: MetricType.humidity, value: humidity, timestamp: now),
      MetricType.ammonia: SensorReading(type: MetricType.ammonia, value: ammonia, timestamp: now),
      MetricType.dissolvedOxygen:
          SensorReading(type: MetricType.dissolvedOxygen, value: dissolvedOxygen, timestamp: now),
      MetricType.ph: SensorReading(type: MetricType.ph, value: ph, timestamp: now),
    };
  }

  test('all metrics in range yields suitable', () {
    final results = engine.evaluate(readingsFor(), [species]);
    expect(results.single.verdict, MatchVerdict.suitable);
  });

  test('one metric out of range yields marginal', () {
    final results = engine.evaluate(readingsFor(ammonia: 0.2), [species]);
    expect(results.single.verdict, MatchVerdict.marginal);
  });

  test('two or more metrics out of range yields unsuitable', () {
    final results = engine.evaluate(readingsFor(ammonia: 0.2, temp: 15), [species]);
    expect(results.single.verdict, MatchVerdict.unsuitable);
  });

  test('results are sorted suitable before marginal before unsuitable', () {
    const badSpecies = FishSpecies(
      name: 'Picky Fish',
      localName: 'Picky Fish',
      tempRange: MetricRange(0, 1),
      phRange: MetricRange(0, 1),
      doRange: MetricRange(0, 1),
      ammoniaRange: MetricRange(0, 0.001),
    );

    final results = engine.evaluate(readingsFor(), [badSpecies, species]);
    expect(results.first.species.name, 'Test Fish');
    expect(results.last.species.name, 'Picky Fish');
  });

  test('humidity is not consulted by the suggestion engine', () {
    final low = engine.evaluate(readingsFor(humidity: 10), [species]);
    final high = engine.evaluate(readingsFor(humidity: 99), [species]);

    expect(low.single.verdict, MatchVerdict.suitable);
    expect(high.single.verdict, MatchVerdict.suitable);
    expect(low.single.details.any((d) => d.type == MetricType.humidity), isFalse);
  });
}
