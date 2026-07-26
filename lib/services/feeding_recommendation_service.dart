import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/feeding_recommendation.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import 'prediction_api_config.dart';

/// Everything [DashboardProvider] needs to turn a pond's current readings
/// plus a species into a feeding plan and water-quality advisory, factored
/// out so it can be unit tested against a fake instead of a real network call.
abstract class FeedingRecommendationService {
  Future<FeedingRecommendation> recommend({
    required String species,
    required Map<MetricType, SensorReading> readings,
  });
}

/// Calls the Render-hosted `isdasafe-server` FastAPI service
/// (`POST /feeding-recommendation`), which asks Gemini for a feeding plan
/// and water-quality advisory given a species and current readings. Like
/// [HttpSpeciesRecommendationService], this hits a free-tier Render
/// instance, so a request after inactivity can take up to ~50s to wake up.
class HttpFeedingRecommendationService implements FeedingRecommendationService {
  HttpFeedingRecommendationService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = resolvePredictionApiBaseUrl(baseUrl);

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<FeedingRecommendation> recommend({
    required String species,
    required Map<MetricType, SensorReading> readings,
  }) async {
    final body = jsonEncode({
      'ammonia': readings[MetricType.ammonia]!.value,
      'dissolved_oxygen': readings[MetricType.dissolvedOxygen]!.value,
      'ph': readings[MetricType.ph]!.value,
      'temperature': readings[MetricType.temperature]!.value,
      'species': species,
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/feeding-recommendation'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw Exception('The server is waking up — please try again in a moment.');
    }

    if (response.statusCode != 200) {
      throw Exception('Feeding recommendation request failed (${response.statusCode}): ${response.body}');
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedingRecommendation(
        species: species,
        feedingTime: json['feeding_time'] as String,
        feedingFrequency: json['feeding_frequency'] as String,
        feedingAmount: json['feeding_amount'] as String,
        waterQualityRecommendations: (json['water_quality_recommendations'] as List).cast<String>(),
        possibleRisks: (json['possible_risks'] as List).cast<String>(),
      );
    } catch (_) {
      throw Exception('Received an unexpected response from the feeding recommendation server.');
    }
  }
}
