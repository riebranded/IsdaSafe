import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/language_provider.dart';
import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';

/// How long a pond's water-quality recommendations and risks stay valid.
const Duration waterAdviceTtl = Duration(minutes: 15);

/// A pond's saved AI advice, kept on the `ponds` row in three JSON columns:
///  * `feeding_schedules` - the feeding plan, regenerated once a day;
///  * `water_advice` - water-quality recommendations, every 15 min;
///  * `possible_risks` - the possible risks, every 15 min.
/// All are keyed by language, then species.
class PondAdvice {
  PondAdvice({
    Map<String, dynamic>? schedules,
    Map<String, dynamic>? advice,
    Map<String, dynamic>? risks,
    this.language,
  }) : _schedules = _copy(schedules),
       _advice = _copy(advice),
       _risks = _copy(risks);

  /// Language code the entries are read from / written to; defaults to the
  /// app's current language.
  final String? language;
  final Map<String, dynamic> _schedules;
  final Map<String, dynamic> _advice;
  final Map<String, dynamic> _risks;

  String get _lang => language ?? LanguageProvider.current.code;

  static Map<String, dynamic> _copy(Map<String, dynamic>? m) => {
    for (final e in (m ?? const {}).entries)
      e.key: e.value is Map
          ? Map<String, dynamic>.from(e.value as Map)
          : e.value,
  };

  Map<String, dynamic>? _entry(Map<String, dynamic> column, String species) {
    final byLang = column[_lang];
    if (byLang is! Map) return null;
    final entry = byLang[species];
    return entry is Map ? Map<String, dynamic>.from(entry) : null;
  }

  static DateTime? _time(Map<String, dynamic>? entry) {
    final raw = entry?['generated_at'];
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  /// Today's feeding plan for [species] (device-local day), or null. Also
  /// null when it was made for a different [biomassKg] than the pond's
  /// current one, since the feeding amount depends on it.
  ({String time, String frequency, String amount})? scheduleFor(
    String species, {
    double? biomassKg,
    DateTime? now,
  }) {
    final entry = _entry(_schedules, species);
    final at = _time(entry);
    final today = now ?? DateTime.now();
    if (entry == null ||
        at == null ||
        at.year != today.year ||
        at.month != today.month ||
        at.day != today.day) {
      return null;
    }
    final savedBiomass = (entry['biomass_kg'] as num?)?.toDouble();
    if (savedBiomass != biomassKg) return null;
    final time = entry['feeding_time'];
    final frequency = entry['feeding_frequency'];
    final amount = entry['feeding_amount'];
    if (time is! String || frequency is! String || amount is! String) {
      return null;
    }
    return (time: time, frequency: frequency, amount: amount);
  }

  /// Water-quality recommendations and risks for [species], both generated within
  /// the last [waterAdviceTtl], or null.
  ({List<String> recommendations, List<String> risks})? adviceFor(
    String species, {
    DateTime? now,
  }) {
    final adviceEntry = _entry(_advice, species);
    final riskEntry = _entry(_risks, species);
    final current = now ?? DateTime.now();
    for (final entry in [adviceEntry, riskEntry]) {
      final at = _time(entry);
      if (at == null || current.difference(at) >= waterAdviceTtl) return null;
    }
    final recs = adviceEntry!['water_quality_recommendations'];
    final risks = riskEntry!['possible_risks'];
    if (recs is! List || risks is! List) return null;
    return (recommendations: recs.cast<String>(), risks: risks.cast<String>());
  }

  /// Records a fresh model answer. The feeding plan is only replaced when
  /// [replaceSchedule] is true (i.e. today's is missing); the water advice is
  /// always replaced.
  void put(
    String species,
    FeedingRecommendation r,
    Map<MetricType, SensorReading> readings, {
    required bool replaceSchedule,
    double? biomassKg,
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    if (replaceSchedule) {
      _schedules[_lang] = {
        ...Map<String, dynamic>.from((_schedules[_lang] as Map?) ?? const {}),
        species: {
          'feeding_time': r.feedingTime,
          'feeding_frequency': r.feedingFrequency,
          'feeding_amount': r.feedingAmount,
          'biomass_kg': biomassKg,
          'generated_at': stamp,
          'readings': {
            'temperature': readings[MetricType.temperature]?.value,
            'ph': readings[MetricType.ph]?.value,
            'dissolved_oxygen': readings[MetricType.dissolvedOxygen]?.value,
            'ammonia': readings[MetricType.ammonia]?.value,
          },
        },
      };
    }
    _advice[_lang] = {
      ...Map<String, dynamic>.from((_advice[_lang] as Map?) ?? const {}),
      species: {
        'water_quality_recommendations': r.waterQualityRecommendations,
        'generated_at': stamp,
      },
    };
    _risks[_lang] = {
      ...Map<String, dynamic>.from((_risks[_lang] as Map?) ?? const {}),
      species: {'possible_risks': r.possibleRisks, 'generated_at': stamp},
    };
  }

  Map<String, dynamic> get schedulesJson => _schedules;
  Map<String, dynamic> get adviceJson => _advice;
  Map<String, dynamic> get risksJson => _risks;
}

/// Reads and writes a pond's saved advice.
abstract class FeedingScheduleStore {
  /// The pond's saved advice; empty if there is none or it can't be read.
  Future<PondAdvice> load(String pondId);

  /// Writes [advice] back to the pond. Failures are swallowed: the advice is
  /// still shown, it just isn't reused next time.
  Future<void> save(String pondId, PondAdvice advice);
}

class SupabaseFeedingScheduleStore implements FeedingScheduleStore {
  SupabaseFeedingScheduleStore({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  @override
  Future<PondAdvice> load(String pondId) async {
    try {
      final row = await _db
          .from('ponds')
          .select('feeding_schedules, water_advice, possible_risks')
          .eq('id', pondId)
          .maybeSingle();
      return PondAdvice(
        schedules: (row?['feeding_schedules'] as Map?)?.cast<String, dynamic>(),
        advice: (row?['water_advice'] as Map?)?.cast<String, dynamic>(),
        risks: (row?['possible_risks'] as Map?)?.cast<String, dynamic>(),
      );
    } catch (e) {
      debugPrint('FeedingScheduleStore: load error $e');
      return PondAdvice();
    }
  }

  @override
  Future<void> save(String pondId, PondAdvice advice) async {
    try {
      await _db
          .from('ponds')
          .update({
            'feeding_schedules': advice.schedulesJson,
            'water_advice': advice.adviceJson,
            'possible_risks': advice.risksJson,
          })
          .eq('id', pondId);
    } catch (e) {
      debugPrint('FeedingScheduleStore: save error $e');
    }
  }
}
