import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isdasafev2/models/fish_species.dart';
import 'package:isdasafev2/models/free_ammonia.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/reading_bands.dart';
import 'package:isdasafev2/models/reading_status.dart';
import 'package:isdasafev2/models/sensor_reading.dart';
import 'package:isdasafev2/services/fish_species_catalog.dart';
import 'package:isdasafev2/services/species_recommendation_service.dart';

Map<MetricType, SensorReading> _readings(Map<MetricType, double> values) {
  final now = DateTime(2026, 10, 11, 9);
  return {
    for (final e in withFreeAmmonia(values).entries)
      e.key: SensorReading(type: e.key, value: e.value, timestamp: now),
  };
}

void main() {
  // Total ammonia 0.10 mg/L is over its own warning limit, but at pH 7 and
  // 27 °C only ~0.0007 mg/L of it is free NH3: harmless.
  final cool = {
    MetricType.temperature: 27.0,
    MetricType.ph: 7.0,
    MetricType.dissolvedOxygen: 6.0,
    MetricType.ammonia: 0.10,
  };
  // More alkaline water: a much bigger share of the ammonia is free NH3.
  final alkaline = {...cool, MetricType.ph: 8.4};

  test('pond status judges free ammonia, not total ammonia', () {
    expect(overallStatus(_readings(cool)), ReadingStatus.normal);

    final readings = _readings({...alkaline, MetricType.ammonia: 1.0});
    expect(
      readings[MetricType.freeAmmonia]!.value,
      greaterThan(metricBands[MetricType.freeAmmonia]!.warningHigh!),
    );
    expect(overallStatus(readings), isNot(ReadingStatus.normal));
  });

  test('species fit compares free ammonia with the species range', () {
    final tilapia = FishSpeciesCatalog.byName('Tilapia')!;
    expect(tilapia.fitFor(_readings(cool)).level, Suitability.suitable);

    final fit = tilapia.fitFor(_readings({...alkaline, MetricType.ammonia: 2}));
    expect(fit.issues, contains('${MetricType.freeAmmonia.label} too high'));
  });

  test('the AI species model is sent free ammonia', () async {
    late Map<String, dynamic> sent;
    final service = HttpSpeciesRecommendationService(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"suitable_species": "Nile tilapia"}', 200);
      }),
    );

    final readings = _readings(alkaline);
    await service.recommend(readings);
    expect(sent['ammonia'], readings[MetricType.freeAmmonia]!.value);

    // Readings without the derived value still send free ammonia.
    await service.recommend({...readings}..remove(MetricType.freeAmmonia));
    expect(
      sent['ammonia'],
      closeTo(readings[MetricType.freeAmmonia]!.value, 1e-12),
    );
  });
}
