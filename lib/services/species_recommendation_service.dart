import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/free_ammonia.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/species_recommendation.dart';
import 'prediction_api_config.dart';

/// Everything [DashboardProvider] needs to turn a pond's current readings
/// into an AI-recommended fish species, factored out so it can be unit
/// tested against a fake instead of a real network call.
abstract class SpeciesRecommendationService {
  Future<SpeciesRecommendation> recommend(
    Map<MetricType, SensorReading> readings,
  );
}

/// Calls the Render-hosted `isdasafe-server` FastAPI service
/// (`POST /predict`), which runs a trained RandomForestClassifier over
/// free ammonia/dissolved-oxygen/pH/temperature and returns the recommended
/// species. The model was trained on free (un-ionised) NH3, so that's what's
/// sent as `ammonia`, not the sensor's total ammonia. The service is on Render's free tier, so a request after a
/// period of inactivity can take up to ~50s while the instance wakes up —
/// callers should surface a suitably patient loading state.
class HttpSpeciesRecommendationService implements SpeciesRecommendationService {
  HttpSpeciesRecommendationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = resolvePredictionApiBaseUrl(baseUrl);

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<SpeciesRecommendation> recommend(
    Map<MetricType, SensorReading> readings,
  ) async {
    final ph = readings[MetricType.ph]!.value;
    final temperature = readings[MetricType.temperature]!.value;
    final body = jsonEncode({
      'ammonia':
          readings[MetricType.freeAmmonia]?.value ??
          freeAmmonia(
            totalAmmonia: readings[MetricType.ammonia]!.value,
            ph: ph,
            tempC: temperature,
          ),
      'dissolved_oxygen': readings[MetricType.dissolvedOxygen]!.value,
      'ph': ph,
      'temperature': temperature,
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw Exception(
        'The server is waking up — please try again in a moment.',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Prediction request failed (${response.statusCode}): ${response.body}',
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return SpeciesRecommendation(
        species: json['suitable_species'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
    } catch (_) {
      throw Exception(
        'Received an unexpected response from the prediction server.',
      );
    }
  }
}
