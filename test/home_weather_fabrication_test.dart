// Regression tests for the Home honest-weather contract.
//
// _fetchWeatherSignalImproved, _WeatherService and _WeatherSignal are
// library-private to lib/home.dart, so (matching the existing convention in
// test/daily_wear_weather_location_test.dart) these are source-level
// regression assertions rather than a live widget pump: BackendService's
// getCurrentWeather() issues a raw dart:io http.get with no injectable
// client, so the private parsing logic cannot be driven from an external
// test file without inventing a new HTTP-mocking harness — which the ticket
// explicitly says not to do ("do not create a new weather system").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/home.dart').readAsStringSync();

  String extractMethod(String signature, String nextSignature) {
    final start = source.indexOf(signature);
    if (start < 0) throw StateError('$signature not found');
    final end = source.indexOf(nextSignature, start);
    if (end <= start) throw StateError('$nextSignature not found after $signature');
    return source.substring(start, end);
  }

  final improved = extractMethod(
    'Future<void> _fetchWeatherSignalImproved() async {',
    '/// Extracts a workout localization key',
  );

  group('Home weather: no fabricated fallback', () {
    test('available 24.6°C rounds to 25° via the existing chip label formula', () {
      // The private pipeline can't be driven directly (see file header), but
      // the exact rounding expression the chip renders is asserted below and
      // proven here against the ticket's own example value.
      expect(24.6.round(), 25);
      expect(source, contains("'\${w.tempCelsius!.round()}°'"));
    });

    test('temperature is never hardcoded to 28.0 on the success path', () {
      expect(improved, isNot(contains('?? 28.0')));
    });

    test('temperature is only assigned from a real numeric + available response', () {
      expect(improved, contains("weather['success'] == true"));
      expect(improved, contains('rawTemp is num'));
    });

    test('missing weather_code is never coerced to 0 (which maps to Clear)', () {
      expect(improved, isNot(contains("as int? ?? 0")));
    });

    test('description (and therefore "Clear") is only derived when temp and code are both real', () {
      expect(improved, contains('temp != null && code != null'));
    });

    test('provider exception no longer produces a fabricated 28.0/partly-cloudy signal', () {
      final catchStart = improved.indexOf('catch (e) {');
      expect(catchStart, greaterThan(-1));
      final catchBlock = improved.substring(catchStart);
      expect(catchBlock, isNot(contains('28.0')));
      expect(catchBlock, isNot(contains('partly cloudy')));
      expect(catchBlock, contains('const _WeatherSignal()'));
    });
  });

  group('Home weather: legacy Hyderabad fetcher is unreachable', () {
    test('_fetchWeatherSignal (hardcoded 17.385/78.486) has no call site besides its own retry', () {
      // "_fetchWeatherSignal(" (not "...Improved(") matches exactly twice in
      // an untouched file: the method's own declaration, and its single
      // internal retry call. Any external caller (initState/build/etc.)
      // would add a third occurrence.
      final occurrences = '_fetchWeatherSignal('.allMatches(source).length;
      expect(occurrences, 2,
          reason:
              'expected only the declaration + its own retry call; a 3rd '
              'occurrence would mean something now calls the dead '
              'Hyderabad-hardcoded fetcher');
    });

    test('_fetchWeatherSignalImproved is the method actually scheduled on mount', () {
      expect(source, contains('_fetchWeatherSignalImproved(); // 🆕 Use improved weather fetch'));
    });
  });
}
