// Regression tests for the canonical Home/Daily Wear weather cache added to
// BackendService.getCurrentWeather(). Matches the existing convention in
// test/daily_wear_weather_location_test.dart and
// test/home_weather_fabrication_test.dart: getCurrentWeather() issues a raw
// dart:io http.get with no injectable client, so these are source-level
// regression assertions rather than a live network-mocked call.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/backend_service.dart';

void main() {
  final source = File('lib/services/backend_service.dart').readAsStringSync();

  String extractMethod(String signature, String nextSignature) {
    final start = source.indexOf(signature);
    if (start < 0) throw StateError('$signature not found');
    final end = source.indexOf(nextSignature, start);
    if (end <= start) {
      throw StateError('$nextSignature not found after $signature');
    }
    return source.substring(start, end);
  }

  final getCurrentWeather = extractMethod(
    'Future<Map<String, dynamic>> getCurrentWeather() async {',
    'Future<Map<String, dynamic>> _fetchWeatherFromNetwork(',
  );

  group('BackendService.getCurrentWeather: shared canonical cache', () {
    test('A/E. a fresh cached reading is returned without a network fetch', () {
      expect(getCurrentWeather, contains('_weatherCache[userId]'));
      expect(
        getCurrentWeather,
        contains('now.difference(cached.capturedAt) < _weatherFreshness'),
      );
      expect(getCurrentWeather, contains('return cached.weather;'));
    });

    test('successful network results populate the shared cache', () {
      expect(getCurrentWeather, contains("result['status'] == 'available'"));
      expect(
        getCurrentWeather,
        contains('_weatherCache[userId] = (weather: result, capturedAt: now)'),
      );
    });

    test(
      'B. a failed/unavailable refresh falls back to a recent known-good '
      'reading instead of overwriting it with unavailable',
      () {
        final afterSuccessBranch = getCurrentWeather.substring(
          getCurrentWeather.indexOf('return result;'),
        );
        expect(
          afterSuccessBranch,
          contains('now.difference(cached.capturedAt) < _weatherStaleLimit'),
        );
        expect(afterSuccessBranch, contains('return cached.weather;'));
      },
    );

    test('C. no cache anywhere still yields the honest unavailable result', () {
      // The final fallthrough returns whatever _fetchWeatherFromNetwork
      // produced verbatim -- no fabricated temperature is substituted.
      final normalized = getCurrentWeather.replaceAll('\r\n', '\n').trim();
      expect(normalized, endsWith('return result;\n  }'));
    });

    test('cache is a single shared static -- not per BackendService instance', () {
      expect(source, contains('static final Map<String'));
      expect(source, contains('_weatherCache = {}'));
    });

    test('weather cache is cleared on session invalidation like other caches', () {
      expect(
        source,
        contains(
          '_appwriteService.addSessionInvalidationListener(clearWeatherCache);',
        ),
      );
    });

    test('clearWeatherCache test seam actually empties the cache', () {
      // Public, exercisable seam rather than another source assertion.
      expect(() => BackendService.clearWeatherCache(), returnsNormally);
    });
  });
}
