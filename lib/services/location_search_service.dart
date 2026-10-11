import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// One place returned by a location search.
class PlaceResult {
  const PlaceResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  /// Full, comma-separated address, e.g. "Calamba, Laguna, Calabarzon, Philippines".
  final String displayName;
  final double latitude;
  final double longitude;

  /// First part of [displayName] — the place's own name.
  String get title => displayName.split(',').first.trim();

  /// The rest of [displayName] (province, region, ...), or empty.
  String get subtitle {
    final parts = displayName.split(',');
    return parts.length < 2
        ? ''
        : parts.skip(1).map((p) => p.trim()).join(', ');
  }
}

/// Thrown when a search can't be completed; [message] is safe to show.
class LocationSearchException implements Exception {
  const LocationSearchException(this.message);
  final String message;

  @override
  String toString() => 'LocationSearchException: $message';
}

/// Turns a typed place name into coordinates. Abstract so the add-pond dialog
/// can be tested without the network.
abstract class LocationSearchService {
  /// Returns up to a handful of matches (empty if nothing was found); throws
  /// [LocationSearchException] if the search itself fails.
  Future<List<PlaceResult>> search(String query);
}

/// Searches Google Places (Places API (New) "Text Search"), restricted to the
/// Philippines. It needs an API key with billing enabled — see
/// `GOOGLE_PLACES_KEY` in `.env`. Restrict that key to the Places API (and, for
/// the web build, to the site's HTTP referrers) in Google Cloud.
class GooglePlacesLocationSearchService implements LocationSearchService {
  GooglePlacesLocationSearchService({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = 'https://places.googleapis.com',
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;
  final String baseUrl;

  @override
  Future<List<PlaceResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/v1/places:searchText'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              // Only ask for what's shown: the name, address and position.
              'X-Goog-FieldMask':
                  'places.displayName,places.formattedAddress,places.location',
            },
            body: jsonEncode({
              'textQuery': trimmed,
              'regionCode': 'PH',
              'languageCode': 'en',
              'pageSize': 8,
              // Bounding box around the Philippines.
              'locationRestriction': {
                'rectangle': {
                  'low': {'latitude': 4.5, 'longitude': 116.9},
                  'high': {'latitude': 21.2, 'longitude': 126.7},
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 429) {
        throw const LocationSearchException(
          'Search is busy right now. Please try again in a moment.',
        );
      }
      if (response.statusCode != 200) {
        debugPrint(
          'GooglePlacesLocationSearchService: ${response.statusCode} ${response.body}',
        );
        throw const LocationSearchException(
          "Couldn't search for places right now. Please try again.",
        );
      }
      final data = jsonDecode(response.body);
      final places = data is Map ? data['places'] : null;
      if (places is! List) return const [];

      final results = <PlaceResult>[];
      for (final place in places) {
        if (place is! Map) continue;
        final location = place['location'];
        if (location is! Map ||
            location['latitude'] is! num ||
            location['longitude'] is! num) {
          continue;
        }
        final name = (place['displayName'] as Map?)?['text'];
        final address = place['formattedAddress'];
        // "Name, address" so [PlaceResult.title] is the place's own name.
        final parts = <String>[
          if (name is String && name.trim().isNotEmpty) name.trim(),
          if (address is String &&
              address.trim().isNotEmpty &&
              address.trim() != name)
            address.trim(),
        ];
        if (parts.isEmpty) continue;
        results.add(
          PlaceResult(
            displayName: parts.join(', '),
            latitude: (location['latitude'] as num).toDouble(),
            longitude: (location['longitude'] as num).toDouble(),
          ),
        );
      }
      debugPrint(
        'LocationSearch: "$trimmed" -> Google Places (${results.length} results)',
      );
      return results;
    } on LocationSearchException {
      rethrow;
    } on TimeoutException {
      throw const LocationSearchException(
        'The search timed out. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('GooglePlacesLocationSearchService: $e');
      throw const LocationSearchException(
        "Couldn't reach the search service. Check your connection and try again.",
      );
    }
  }
}

/// A search that always fails with [message]; used when no Google key is set,
/// so the dialog shows a clear error instead of silently using another source.
class UnavailableLocationSearchService implements LocationSearchService {
  const UnavailableLocationSearchService(this.message);
  final String message;

  @override
  Future<List<PlaceResult>> search(String query) async =>
      throw LocationSearchException(message);
}

/// The app's place search: Google Places API (New) only, using
/// `GOOGLE_PLACES_KEY` (or, on web, `ISDASAFE_WEB_MAPS_KEY`).
LocationSearchService createDefaultLocationSearch() {
  String? key;
  try {
    key = dotenv.env['GOOGLE_PLACES_KEY'];
    // The web Maps key can serve Places too, if it allows the Places API (New).
    // The Android key can't: it's tied to the app's signature, which a plain
    // HTTP request doesn't carry.
    if ((key == null || key.isEmpty) && kIsWeb) {
      key = dotenv.env['ISDASAFE_WEB_MAPS_KEY'];
    }
  } catch (_) {
    key = null; // dotenv not loaded (tests)
  }
  if (key == null || key.isEmpty) {
    debugPrint(
      'LocationSearch: no GOOGLE_PLACES_KEY set -> place search unavailable',
    );
    return const UnavailableLocationSearchService(
      "Couldn't search for places right now. Please try again.",
    );
  }
  return GooglePlacesLocationSearchService(apiKey: key);
}
