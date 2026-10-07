import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// Searches Komoot's public Photon geocoder (OpenStreetMap data), limited to a
/// box around the Philippines. Unlike Nominatim it matches partial and
/// misspelled names ("Sta Maria", "Dagupn") and ranks fuzzy hits, so a short
/// query returns a useful list instead of one exact match. No API key; like
/// Nominatim it expects light, user-triggered use (one request per search).
class PhotonLocationSearchService implements LocationSearchService {
  PhotonLocationSearchService({
    http.Client? client,
    this.baseUrl = 'https://photon.komoot.io',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  // west, south, east, north — keeps results inside the Philippines.
  static const _philippinesBox = '116.9,4.5,126.7,21.2';

  @override
  Future<List<PlaceResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final uri = Uri.parse('$baseUrl/api/').replace(
      queryParameters: {
        'q': trimmed,
        'limit': '8',
        'lang': 'en',
        'bbox': _philippinesBox,
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 429) {
        throw const LocationSearchException(
          'Search is busy right now. Please try again in a moment.',
        );
      }
      if (response.statusCode != 200) {
        throw const LocationSearchException(
          "Couldn't search for places right now. Please try again.",
        );
      }
      final data = jsonDecode(response.body);
      final features = data is Map ? data['features'] : null;
      if (features is! List) return const [];

      final results = <PlaceResult>[];
      final seen = <String>{};
      for (final feature in features) {
        if (feature is! Map) continue;
        final coords = (feature['geometry'] as Map?)?['coordinates'];
        final props = feature['properties'];
        if (coords is! List || coords.length < 2 || props is! Map) continue;

        // "Calamba, Calamba, Laguna" -> "Calamba, Laguna": drop repeated parts.
        final parts = <String>[];
        for (final key in [
          'name',
          'street',
          'district',
          'city',
          'county',
          'state',
          'country',
        ]) {
          final value = props[key];
          if (value is String &&
              value.trim().isNotEmpty &&
              !parts.contains(value.trim())) {
            parts.add(value.trim());
          }
        }
        if (parts.isEmpty) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        // Photon often lists the same place several times (one per OSM object);
        // keep one per name within ~1 km.
        final key =
            '${parts.join(',')}|${lat.toStringAsFixed(2)}|${lon.toStringAsFixed(2)}';
        if (!seen.add(key)) continue;
        results.add(
          PlaceResult(
            displayName: parts.join(', '),
            latitude: lat,
            longitude: lon,
          ),
        );
      }
      return results;
    } on LocationSearchException {
      rethrow;
    } on TimeoutException {
      throw const LocationSearchException(
        'The search timed out. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('PhotonLocationSearchService: $e');
      throw const LocationSearchException(
        "Couldn't reach the search service. Check your connection and try again.",
      );
    }
  }
}

/// Asks [primary] first and only falls back to [fallback] if it fails or finds
/// nothing, so one flaky or overloaded free geocoder doesn't leave the user
/// with an empty search.
class FallbackLocationSearchService implements LocationSearchService {
  const FallbackLocationSearchService({
    required this.primary,
    required this.fallback,
  });

  final LocationSearchService primary;
  final LocationSearchService fallback;

  @override
  Future<List<PlaceResult>> search(String query) async {
    LocationSearchException? primaryError;
    try {
      final results = await primary.search(query);
      if (results.isNotEmpty) return results;
    } on LocationSearchException catch (e) {
      primaryError = e;
    }
    try {
      return await fallback.search(query);
    } on LocationSearchException {
      // The primary answered "nothing found" cleanly; only surface an error if
      // neither service could answer at all.
      if (primaryError == null) return const [];
      rethrow;
    }
  }
}

/// Searches OpenStreetMap's public Nominatim geocoder, limited to the
/// Philippines. It needs no API key. Its usage policy allows light,
/// user-triggered searches like this one (one request per search, never per
/// keystroke); if search volume grows, point [baseUrl] at a self-hosted
/// instance or swap this class for a Google Geocoding-backed one.
class NominatimLocationSearchService implements LocationSearchService {
  NominatimLocationSearchService({
    http.Client? client,
    this.baseUrl = 'https://nominatim.openstreetmap.org',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<List<PlaceResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: {
        'q': trimmed,
        'format': 'jsonv2',
        'limit': '8',
        'countrycodes': 'ph',
        'accept-language': 'en',
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 429) {
        throw const LocationSearchException(
          'Search is busy right now. Please try again in a moment.',
        );
      }
      if (response.statusCode != 200) {
        throw const LocationSearchException(
          "Couldn't search for places right now. Please try again.",
        );
      }
      final data = jsonDecode(response.body);
      if (data is! List) return const [];
      return [
        for (final row in data)
          if (row is Map &&
              row['lat'] != null &&
              row['lon'] != null &&
              row['display_name'] is String)
            PlaceResult(
              displayName: row['display_name'] as String,
              latitude: double.parse('${row['lat']}'),
              longitude: double.parse('${row['lon']}'),
            ),
      ];
    } on LocationSearchException {
      rethrow;
    } on TimeoutException {
      throw const LocationSearchException(
        'The search timed out. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('NominatimLocationSearchService: $e');
      throw const LocationSearchException(
        "Couldn't reach the search service. Check your connection and try again.",
      );
    }
  }
}
