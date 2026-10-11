import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/reading_bands.dart';
import 'package:isdasafev2/models/reading_status.dart';
import 'package:isdasafev2/models/sensor_reading.dart';
import 'package:isdasafev2/models/weather_context.dart';

final _now = DateTime(2026, 10, 11, 14); // 2 PM

Map<MetricType, SensorReading> _readings(Map<MetricType, double> values) => {
  for (final e in values.entries)
    e.key: SensorReading(type: e.key, value: e.value, timestamp: _now),
};

/// [values] spread evenly over the [span] up to [_now], oldest first.
List<SensorReading> _series(
  MetricType type,
  List<double> values, {
  Duration span = const Duration(hours: 1),
}) => [
  for (final (i, v) in values.indexed)
    SensorReading(
      type: type,
      value: v,
      timestamp: _now.subtract(
        span * ((values.length - 1 - i) / (values.length - 1)),
      ),
    ),
];

Set<WeatherRisk> _risks(
  Map<MetricType, double> values, {
  Map<MetricType, List<SensorReading>> history = const {},
  DateTime? now,
}) => {
  for (final i in weatherInsights(
    _readings(values),
    history: history,
    now: now ?? _now,
  ))
    i.risk,
};

void main() {
  group('pond status', () {
    test('humidity alone never changes it', () {
      final healthyWater = {
        MetricType.temperature: 27.0,
        MetricType.dissolvedOxygen: 6.5,
        MetricType.ph: 7.2,
        MetricType.ammonia: 0.01,
      };
      for (final humidity in [20.0, 86.0, 99.0]) {
        expect(
          overallStatus(
            _readings({...healthyWater, MetricType.humidity: humidity}),
          ),
          ReadingStatus.normal,
          reason: 'humidity $humidity',
        );
      }
    });

    test('borderline oxygen counts as a warning in muggy, warm weather', () {
      final water = {
        MetricType.temperature: 29.0, // warm, but within its own range
        MetricType.dissolvedOxygen: 4.6, // fine on its own (limit 4)
        MetricType.ph: 7.2,
      };
      expect(
        overallStatus(_readings({...water, MetricType.humidity: 70})),
        ReadingStatus.normal,
      );
      expect(
        overallStatus(_readings({...water, MetricType.humidity: 90})),
        ReadingStatus.warning,
      );
    });
  });

  test('muggy, warm weather warns about oxygen at night', () {
    final values = {
      MetricType.humidity: 90.0,
      MetricType.temperature: 30.0,
      MetricType.dissolvedOxygen: 6.0,
    };
    final insight = weatherInsights(_readings(values), now: _now).single;
    expect(insight.risk, WeatherRisk.nightOxygen);
    expect(insight.affects, MetricType.dissolvedOxygen);
    expect(insight.severity, ReadingStatus.normal); // oxygen is still fine
    expect(insight.message, contains('evening'));

    final evening = weatherInsights(
      _readings(values),
      now: DateTime(2026, 10, 11, 19),
    ).single;
    expect(evening.message, contains('through the night'));

    // Not muggy, or not warm: nothing.
    expect(_risks({...values, MetricType.humidity: 75}), isEmpty);
    expect(_risks({...values, MetricType.temperature: 26}), isEmpty);
  });

  test('humid air warmer than the water keeps it warming', () {
    expect(
      _risks({
        MetricType.humidity: 82,
        MetricType.airTemperature: 31,
        MetricType.temperature: 28,
      }),
      {WeatherRisk.keepsWarming},
    );
    // Air cooler than the water: it can cool down.
    expect(
      _risks({
        MetricType.humidity: 82,
        MetricType.airTemperature: 27,
        MetricType.temperature: 28,
      }),
      isEmpty,
    );
  });

  test('hot, dry air flags evaporation, more urgently with rising ammonia', () {
    final values = {
      MetricType.humidity: 50.0,
      MetricType.airTemperature: 33.0,
      MetricType.ammonia: 0.06,
    };
    final steady = weatherInsights(_readings(values), now: _now).single;
    expect(steady.risk, WeatherRisk.fastEvaporation);
    expect(steady.message, isNot(contains('rising')));

    final rising = weatherInsights(
      _readings(values),
      history: {
        MetricType.ammonia: _series(MetricType.ammonia, [0.03, 0.04, 0.06]),
      },
      now: _now,
    ).single;
    expect(rising.message, contains('rising'));
  });

  test('a humidity jump while the air cools means rain', () {
    expect(
      _risks(
        {MetricType.humidity: 96, MetricType.airTemperature: 26},
        history: {
          MetricType.humidity: _series(MetricType.humidity, [78, 85, 96]),
          MetricType.airTemperature: _series(MetricType.airTemperature, [
            30,
            28,
            26,
          ]),
        },
      ),
      {WeatherRisk.likelyRain},
    );
    // Humid all along: no jump, no rain.
    expect(
      _risks(
        {MetricType.humidity: 96, MetricType.airTemperature: 26},
        history: {
          MetricType.humidity: _series(MetricType.humidity, [94, 95, 96]),
          MetricType.airTemperature: _series(MetricType.airTemperature, [
            30,
            28,
            26,
          ]),
        },
      ),
      isEmpty,
    );
  });

  test('muggy weather explains high toxic ammonia', () {
    final insights = weatherInsights(
      _readings({
        MetricType.humidity: 90,
        MetricType.temperature: 30,
        MetricType.dissolvedOxygen: 6,
        MetricType.freeAmmonia: 0.06,
      }),
      now: _now,
    );
    final toxic = insights.firstWhere(
      (i) => i.risk == WeatherRisk.toxicAmmonia,
    );
    expect(toxic.affects, MetricType.freeAmmonia);
    expect(toxic.severity, ReadingStatus.critical);
  });

  test('weatherFeel describes the air', () {
    expect(weatherFeel(90), 'Muggy');
    expect(weatherFeel(70), 'Comfortable');
    expect(weatherFeel(50), 'Dry');
  });
}
