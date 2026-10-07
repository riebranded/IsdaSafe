import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isdasafev2/services/location_search_service.dart';

void main() {
  test(
    'parses Nominatim results and limits the search to the Philippines',
    () async {
      late Uri requested;
      final service = NominatimLocationSearchService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode([
              {
                'lat': '14.2117',
                'lon': '121.1653',
                'display_name': 'Calamba, Laguna, Philippines',
              },
              {'lat': null, 'lon': '1', 'display_name': 'Broken row'},
            ]),
            200,
          );
        }),
      );

      final results = await service.search('  Calamba ');

      expect(requested.queryParameters['q'], 'Calamba');
      expect(requested.queryParameters['countrycodes'], 'ph');
      expect(results.length, 1);
      expect(results.single.title, 'Calamba');
      expect(results.single.subtitle, 'Laguna, Philippines');
      expect(results.single.latitude, 14.2117);
      expect(results.single.longitude, 121.1653);
    },
  );

  test('very short queries do not hit the network', () async {
    var called = false;
    final service = NominatimLocationSearchService(
      client: MockClient((_) async {
        called = true;
        return http.Response('[]', 200);
      }),
    );

    expect(await service.search(' a '), isEmpty);
    expect(called, isFalse);
  });

  test('turns HTTP and network failures into user-facing messages', () async {
    final busy = NominatimLocationSearchService(
      client: MockClient((_) async => http.Response('', 429)),
    );
    await expectLater(
      busy.search('Calamba'),
      throwsA(isA<LocationSearchException>()),
    );

    final offline = NominatimLocationSearchService(
      client: MockClient((_) async => throw http.ClientException('no network')),
    );
    await expectLater(
      offline.search('Calamba'),
      throwsA(isA<LocationSearchException>()),
    );
  });

  test(
    'Photon: parses features, merges repeated name parts and drops duplicates',
    () async {
      late Uri requested;
      Map<String, dynamic> feature(
        String name,
        String city,
        double lon,
        double lat,
      ) => {
        'geometry': {
          'coordinates': [lon, lat],
        },
        'properties': {
          'name': name,
          'city': city,
          'state': 'Laguna',
          'country': 'Philippines',
        },
      };
      final service = PhotonLocationSearchService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'features': [
                feature('Calamba', 'Calamba', 121.1653, 14.2117),
                // Same place listed twice by OSM -> shown once.
                feature('Calamba', 'Calamba', 121.1661, 14.2119),
                feature('Calamba', 'Guihulngan', 123.0, 10.1),
              ],
            }),
            200,
          );
        }),
      );

      final results = await service.search('Calamba');

      expect(requested.path, '/api/');
      expect(requested.queryParameters['bbox'], isNotNull);
      expect(results.length, 2);
      // "Calamba, Calamba, Laguna" collapses the repeated part.
      expect(results.first.displayName, 'Calamba, Laguna, Philippines');
      expect(results.first.latitude, 14.2117);
      expect(results.first.longitude, 121.1653);
    },
  );

  test(
    'Fallback: uses the second service only when the first fails or is empty',
    () async {
      const place = PlaceResult(
        displayName: 'Dagupan, Pangasinan',
        latitude: 16.04,
        longitude: 120.33,
      );
      final empty = _StubSearch(const []);
      final broken = _StubSearch(null);
      final good = _StubSearch(const [place]);

      expect(
        await FallbackLocationSearchService(
          primary: good,
          fallback: broken,
        ).search('x'),
        [place],
      );
      expect(broken.calls, 0);
      expect(
        await FallbackLocationSearchService(
          primary: empty,
          fallback: good,
        ).search('x'),
        [place],
      );
      expect(
        await FallbackLocationSearchService(
          primary: broken,
          fallback: good,
        ).search('x'),
        [place],
      );
      // Primary cleanly empty + fallback broken: just "nothing found", not an error.
      expect(
        await FallbackLocationSearchService(
          primary: empty,
          fallback: broken,
        ).search('x'),
        isEmpty,
      );
      // Both broken: the error surfaces.
      await expectLater(
        FallbackLocationSearchService(
          primary: broken,
          fallback: _StubSearch(null),
        ).search('x'),
        throwsA(isA<LocationSearchException>()),
      );
    },
  );
}

/// Returns [results], or throws if [results] is null.
class _StubSearch implements LocationSearchService {
  _StubSearch(this.results);

  final List<PlaceResult>? results;
  int calls = 0;

  @override
  Future<List<PlaceResult>> search(String query) async {
    calls++;
    final r = results;
    if (r == null) throw const LocationSearchException('down');
    return r;
  }
}
