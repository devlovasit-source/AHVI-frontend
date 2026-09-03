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

  group('DailyWear weather request wiring + fallback (regression)', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();

    test('_fetchWeather resolves coordinates via DailyWearScreen.resolveWeatherCoordinates',
        () {
      expect(source, contains('DailyWearScreen.resolveWeatherCoordinates()'));
      expect(source, contains("'?latitude=\${coords.lat}&longitude=\${coords.lon}'"));
    });

    test('open-meteo request failure fallback (existing degradation) is untouched',
        () {
      final fetchWeather = source.substring(
        source.indexOf('Future<void> _fetchWeather()'),
        source.indexOf('void _applyWeather('),
      );
      expect(fetchWeather, contains('catch (_) {'));
      expect(fetchWeather, contains('baseTemps'));
      expect(fetchWeather, contains('_applyWeather(t, feel, code);'));
    });
  });
}
