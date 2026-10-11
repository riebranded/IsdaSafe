import '../l10n/tr.dart';
import 'metric_type.dart';
import 'reading_bands.dart';
import 'reading_status.dart';
import 'sensor_reading.dart';

/// Humidity and air temperature never harm fish directly, so they don't
/// decide the pond's status on their own. They describe the weather, and the
/// weather changes the water: these rules turn that into insights attached
/// to the water reading they affect (dissolved oxygen, water temperature,
/// ammonia, pH).
///
/// The thresholds are aquaculture rules of thumb, a starting point to tune
/// against real pond data.
enum WeatherRisk {
  /// Muggy, warm weather: oxygen can crash at night / dawn.
  nightOxygen,

  /// Humid air warmer than the water: the pond can't cool down.
  keepsWarming,

  /// Hot, dry air: fast evaporation concentrates ammonia.
  fastEvaporation,

  /// Humidity jumped and the air cooled: probably rain (pH drop, turnover).
  likelyRain,

  /// Warm, humid weather keeps the toxic share of ammonia high.
  toxicAmmonia,
}

class WeatherInsight {
  const WeatherInsight({
    required this.risk,
    required this.affects,
    required this.title,
    required this.message,
    this.severity = ReadingStatus.normal,
  });

  final WeatherRisk risk;

  /// The water reading this insight is about; shown with it.
  final MetricType affects;
  final String title;
  final String message;

  /// [ReadingStatus.normal] = heads-up only. Warning/critical raise the
  /// pond's status like an out-of-range water reading does.
  final ReadingStatus severity;
}

/// Humid enough to mean overcast, muggy weather.
const muggyHumidity = 85.0;

/// Warm water: holds little oxygen, and the toxic share of ammonia grows.
const warmWaterC = 29.0;

/// Below this the air is dry enough to evaporate the pond quickly.
const dryHumidity = 60.0;

/// In muggy weather, oxygen below this counts as a warning (normally
/// [MetricBands.warningLow] for dissolved oxygen, 4 mg/L), because the night
/// will push it lower.
const muggyOxygenWarning = 5.0;

/// How the air feels, for the humidity card: "Muggy", "Dry" or
/// "Comfortable".
String weatherFeel(double humidity) {
  if (humidity >= muggyHumidity) return 'Muggy'.tr;
  if (humidity < dryHumidity) return 'Dry'.tr;
  return 'Comfortable'.tr;
}

/// Night or about to be: evening onwards until after dawn.
bool _nightAhead(DateTime now) => now.hour >= 16 || now.hour < 7;

/// The weather insights for a pond's latest [readings]. [history] (oldest
/// first per metric) enables the ones that need a trend (rain, rising
/// ammonia); without it they're skipped.
List<WeatherInsight> weatherInsights(
  Map<MetricType, SensorReading> readings, {
  Map<MetricType, List<SensorReading>> history = const {},
  DateTime? now,
}) {
  now ??= DateTime.now();
  double? latest(MetricType type) => readings[type]?.value;
  final humidity = latest(MetricType.humidity);
  final air = latest(MetricType.airTemperature);
  final water = latest(MetricType.temperature);
  final oxygen = latest(MetricType.dissolvedOxygen);
  final ph = latest(MetricType.ph);
  final insights = <WeatherInsight>[];
  if (humidity == null) return insights;

  final muggy = humidity >= muggyHumidity;
  final warm = water != null && water >= warmWaterC;

  // 1. Night oxygen crash: overcast + warm water = little photosynthesis and
  //    little oxygen held, and the fish still breathe all night.
  if (muggy && warm) {
    final low = oxygen != null && oxygen < muggyOxygenWarning;
    final night = _nightAhead(now);
    insights.add(
      WeatherInsight(
        risk: WeatherRisk.nightOxygen,
        affects: MetricType.dissolvedOxygen,
        title: 'Oxygen may drop tonight'.tr,
        severity: low ? ReadingStatus.warning : ReadingStatus.normal,
        message: [
          if (low)
            'Oxygen is already {0} and the weather is humid and warm.'.trf([
              MetricType.dissolvedOxygen.format(oxygen),
            ])
          else
            'The weather is humid and warm, so the pond makes and holds less oxygen.'
                .tr,
          night
              ? 'Run the aerators through the night and check oxygen at dawn, when it is lowest.'
                    .tr
              : 'Plan to run the aerators from evening until dawn, and feed less late in the day.'
                    .tr,
        ].join(' '),
      ),
    );
  }

  // 2. The pond can't shed heat when the air is warmer and humid.
  if (humidity >= 80 &&
      air != null &&
      water != null &&
      air >= water + 1 &&
      water >= 27) {
    insights.add(
      WeatherInsight(
        risk: WeatherRisk.keepsWarming,
        affects: MetricType.temperature,
        title: 'Water likely to keep warming'.tr,
        message:
            'The air ({0}) is warmer than the water and humid, so the pond can\'t cool down. Shade it and top up with cooler water before it passes {1}.'
                .trf([
                  MetricType.airTemperature.format(air),
                  MetricType.temperature.format(warmWaterC),
                ]),
      ),
    );
  }

  // 3. Hot, dry air evaporates the pond and concentrates ammonia.
  if (humidity < dryHumidity && air != null && air >= 30) {
    final rising = _rising(history[MetricType.ammonia]);
    insights.add(
      WeatherInsight(
        risk: WeatherRisk.fastEvaporation,
        affects: MetricType.ammonia,
        title: 'Pond water is evaporating fast'.tr,
        message: rising
            ? 'Hot, dry air is lowering the water level, and ammonia is rising as it concentrates. Top up with fresh water rather than only cutting feed.'
                  .tr
            : 'Hot, dry air is lowering the water level, which concentrates ammonia. Check the water level and top it up with fresh water.'
                  .tr,
      ),
    );
  }

  // 4. Rain: humidity jumps to near 100% while the air cools.
  if (_likelyRain(history, now)) {
    insights.add(
      WeatherInsight(
        risk: WeatherRisk.likelyRain,
        affects: MetricType.ph,
        title: "It's probably raining".tr,
        message:
            'Humidity jumped and the air cooled. Rain lowers the pH and can stir up the pond bottom: check pH and dissolved oxygen over the next few hours.'
                .tr,
      ),
    );
  }

  // 5. Warm, humid weather keeps the toxic share of ammonia high.
  final free = latest(MetricType.freeAmmonia);
  if (muggy && free != null && (warm || (ph != null && ph >= 8))) {
    final status = metricBands[MetricType.freeAmmonia]!.statusFor(free);
    if (status != ReadingStatus.normal) {
      insights.add(
        WeatherInsight(
          risk: WeatherRisk.toxicAmmonia,
          affects: MetricType.freeAmmonia,
          title: 'Weather is raising toxic ammonia'.tr,
          severity: status,
          message:
              'Warm, humid weather keeps the water warm, which raises the toxic share of ammonia ({0}). Expect it to stay high until the weather cools: cut feeding and change part of the water.'
                  .trf([MetricType.freeAmmonia.format(free)]),
        ),
      );
    }
  }

  return insights;
}

/// Whether the newest value is clearly above the one about an hour earlier.
bool _rising(List<SensorReading>? history) {
  if (history == null || history.length < 2) return false;
  final newest = history.last;
  final hourAgo = newest.timestamp.subtract(const Duration(hours: 1));
  final earlier = history.lastWhere(
    (r) => !r.timestamp.isAfter(hourAgo),
    orElse: () => history.first,
  );
  if (identical(earlier, newest)) return false;
  return newest.value > earlier.value * 1.1 &&
      newest.value - earlier.value >= 0.01;
}

/// Humidity rose 10+ points to 92%+ within the last 2 hours while the air
/// cooled by 2 °C or more.
bool _likelyRain(Map<MetricType, List<SensorReading>> history, DateTime now) {
  List<SensorReading> recent(MetricType type) {
    final since = now.subtract(const Duration(hours: 2));
    return [
      for (final r in history[type] ?? const <SensorReading>[])
        if (!r.timestamp.isBefore(since)) r,
    ];
  }

  final hum = recent(MetricType.humidity);
  final air = recent(MetricType.airTemperature);
  if (hum.length < 2 || air.length < 2) return false;
  final humNow = hum.last.value;
  final humLow = hum.map((r) => r.value).reduce((a, b) => a < b ? a : b);
  final airNow = air.last.value;
  final airHigh = air.map((r) => r.value).reduce((a, b) => a > b ? a : b);
  return humNow >= 92 && humNow - humLow >= 10 && airHigh - airNow >= 2;
}

/// The worst [WeatherInsight.severity] in [insights].
ReadingStatus worstSeverity(Iterable<WeatherInsight> insights) {
  var worst = ReadingStatus.normal;
  for (final insight in insights) {
    if (insight.severity.index > worst.index) worst = insight.severity;
  }
  return worst;
}
