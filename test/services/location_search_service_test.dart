import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isdasafev2/services/location_search_service.dart';

void main() {
  test(
    'Google Places: sends key, field mask and PH bounds; parses places',
    () async {
      late http.Request sent;
      final service = GooglePlacesLocationSearchService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'places': [
                {
                  'displayName': {'text': 'Sitio Palaisdaan'},
                  'formattedAddress': 'Calumpit, Bulacan, Philippines',
                  'location': {'latitude': 14.9, 'longitude': 120.76},
                },
                {
                  'displayName': {'text': 'No location'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final results = await service.search(' Palaisdaan ');

      expect(sent.headers['X-Goog-Api-Key'], 'test-key');
      expect(sent.headers['X-Goog-FieldMask'], contains('places.location'));
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['textQuery'], 'Palaisdaan');
      expect(body['regionCode'], 'PH');
      expect(body['locationRestriction'], isNotNull);
      expect(results.length, 1);
      expect(results.single.title, 'Sitio Palaisdaan');
      expect(results.single.subtitle, 'Calumpit, Bulacan, Philippines');
      expect(results.single.latitude, 14.9);
    },
  );

  test('Google Places: an API error is reported to the caller', () async {
    final service = GooglePlacesLocationSearchService(
      apiKey: 'bad',
      client: MockClient((_) async => http.Response('{}', 403)),
    );
    await expectLater(
      service.search('Calamba'),
      throwsA(isA<LocationSearchException>()),
    );
  });

  test('very short queries do not hit the network', () async {
    var called = false;
    final service = GooglePlacesLocationSearchService(
      apiKey: 'k',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    expect(await service.search('a'), isEmpty);
    expect(called, isFalse);
  });

  test('429 is reported as a busy search', () async {
    final service = GooglePlacesLocationSearchService(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('{}', 429)),
    );
    await expectLater(
      service.search('Calamba'),
      throwsA(isA<LocationSearchException>()),
    );
  });
}
