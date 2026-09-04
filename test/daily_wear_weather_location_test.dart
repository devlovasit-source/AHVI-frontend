import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';

void main() {
  group('DailyWear weather coordinate resolution', () {
    test('uses real device coordinates when location lookup succeeds', () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => {
          'lat': 17.3850,
          'lon': 78.4867,
          'permission': 'granted',
          'source': 'device',
        },
      );

      expect(coords.lat, 17.3850);
      expect(coords.lon, 78.4867);
    });

    test('falls back to default coordinates when permission is denied', () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => {
          'lat': null,
          'lon': null,
          'permission': 'denied',
          'source': 'none',
        },
      );

      expect(coords.lat, 16.5062);
      expect(coords.lon, 80.648);
    });

    test('falls back to default coordinates when permission is denied forever',
        () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => {
          'lat': null,
          'lon': null,
          'permission': 'denied_forever',
          'source': 'none',
        },
      );

      expect(coords.lat, 16.5062);
      expect(coords.lon, 80.648);
    });

    test('falls back to default coordinates when the location service is disabled',
        () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => {
          'lat': null,
          'lon': null,
          'permission': 'disabled',
          'source': 'none',
        },
      );

      expect(coords.lat, 16.5062);
      expect(coords.lon, 80.648);
    });

    test('falls back to default coordinates when location lookup throws', () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => throw Exception('geolocator unavailable'),
      );

      expect(coords.lat, 16.5062);
      expect(coords.lon, 80.648);
    });

    test('falls back to default coordinates when location lookup times out',
        () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async {
          await Future<void>.delayed(const Duration(seconds: 20));
          return {'lat': 1.0, 'lon': 1.0};
        },
      );

      expect(coords.lat, 16.5062);
      expect(coords.lon, 80.648);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('honors custom fallback coordinates', () async {
      final coords = await DailyWearScreen.resolveWeatherCoordinates(
        locationLookup: () async => {'lat': null, 'lon': null},
        fallbackLat: 1.23,
        fallbackLon: 4.56,
      );

      expect(coords.lat, 1.23);
      expect(coords.lon, 4.56);
    });
  });

  group('DailyWear weather routing (regression: canonical backend, no fabrication)', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();

    String extractMethod(String signature, String nextSignature) {
      final start = source.indexOf(signature);
      if (start < 0) throw StateError('$signature not found');
      final end = source.indexOf(nextSignature, start);
      if (end <= start) {
        throw StateError('$nextSignature not found after $signature');
      }
      return source.substring(start, end);
    }

    final fetchWeather = extractMethod(
      'Future<void> _fetchWeather() async {',
      'void _applyWeatherUnavailable() {',
    );

    test('E. _fetchWeather uses BackendService().getCurrentWeather(), the canonical Home-shared path', () {
      expect(fetchWeather, contains('BackendService().getCurrentWeather()'));
      expect(fetchWeather, contains('mapDailyWearWeather(weather)'));
    });

    test('E. no mounted DailyWear path calls api.open-meteo.com directly', () {
      expect(source, isNot(contains('api.open-meteo.com')));
    });

    test('D. provider/backend exception no longer produces a fabricated baseTemps reading', () {
      expect(fetchWeather, isNot(contains('baseTemps')));
      expect(fetchWeather, isNot(contains('DateTime.now().hour')));
      expect(fetchWeather, contains('_applyWeatherUnavailable();'));
    });

    test('F. no hardcoded Hyderabad coordinates reintroduced anywhere in the file', () {
      expect(source, isNot(contains('17.385')));
      expect(source, isNot(contains('78.486')));
      expect(source, isNot(contains('78.4867')));
    });

    test('F. resolveWeatherCoordinates (device-location work from 1480b64) is preserved', () {
      expect(source, contains('static Future<({double lat, double lon})> resolveWeatherCoordinates'));
      expect(source, contains('LocationContextService().getLocationContext()'));
    });
  });

  group('mapDailyWearWeather (regression: honest mapping, no fabrication)', () {
    test('A. available backend response with a real temperature/code maps through unchanged', () {
      final mapped = mapDailyWearWeather(const {
        'status': 'available',
        'temperature_c': 24.6,
        'raw': {'code': 3, 'apparent_temperature': 23.9},
      });
      expect(mapped.temp, 25); // 24.6 rounds to 25
      expect(mapped.feel, 24);
      expect(mapped.code, 3);
    });

    test('feels-like degrades to actual temperature when the backend omits it', () {
      final mapped = mapDailyWearWeather(const {
        'status': 'available',
        'temperature_c': 18.2,
        'raw': {'code': 1},
      });
      expect(mapped.temp, 18);
      expect(mapped.feel, 18);
    });

    test('B. backend status=unavailable throws instead of returning any temperature', () {
      expect(
        () => mapDailyWearWeather(const {
          'status': 'unavailable',
          'reason': 'weather_location_missing',
        }),
        throwsStateError,
      );
    });

    test('C. missing temperature throws instead of fabricating a value', () {
      expect(
        () => mapDailyWearWeather(const {
          'status': 'available',
          'raw': {'code': 1},
        }),
        throwsStateError,
      );
    });

    test('C. missing weather code throws instead of defaulting to a fake condition', () {
      expect(
        () => mapDailyWearWeather(const {
          'status': 'available',
          'temperature_c': 22.0,
          'raw': <String, dynamic>{},
        }),
        throwsStateError,
      );
    });
  });
}
