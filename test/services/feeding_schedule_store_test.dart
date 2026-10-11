import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/models/feeding_recommendation.dart';
import 'package:isdasafev2/services/feeding_schedule_store.dart';

void main() {
  final now = DateTime(2026, 10, 11, 9);
  const plan = FeedingRecommendation(
    species: 'Tilapia',
    feedingTime: '7 AM and 4 PM',
    feedingFrequency: 'Twice a day',
    feedingAmount: '3.6 kg a day (3% of 120 kg), 1.8 kg per feeding',
    waterQualityRecommendations: [],
    possibleRisks: [],
  );

  test("today's schedule is reused only for the same biomass", () {
    final advice = PondAdvice(language: 'en')
      ..put(
        'Tilapia',
        plan,
        const {},
        replaceSchedule: true,
        biomassKg: 120,
        now: now,
      );

    expect(advice.scheduleFor('Tilapia', biomassKg: 120, now: now), isNotNull);
    // The owner changed the biomass: the amount must be worked out again.
    expect(advice.scheduleFor('Tilapia', biomassKg: 200, now: now), isNull);
    expect(advice.scheduleFor('Tilapia', now: now), isNull);
  });

  test('a schedule made without biomass is reused until one is given', () {
    final advice = PondAdvice(language: 'en')
      ..put('Tilapia', plan, const {}, replaceSchedule: true, now: now);

    expect(advice.scheduleFor('Tilapia', now: now), isNotNull);
    expect(advice.scheduleFor('Tilapia', biomassKg: 120, now: now), isNull);
  });
}
