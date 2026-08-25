import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';

void main() {
  group('mapDailyWearWeather', () {
    test('actual temperature parses from the canonical temperature_c field', () {
      final mapped = mapDailyWearWeather({
        'status': 'available',
        'temperature_c': 28.4,
        'raw': {'code': 2},
      });
      expect(mapped.temp, 28);
    });

    test('weather code parses from raw.code', () {
      final mapped = mapDailyWearWeather({
        'status': 'available',
        'temperature_c': 28,
        'raw': {'code': 61},
      });
      expect(mapped.code, 61);
    });

    test(
      'absent apparent_temperature does not crash and falls back to actual temperature',
      () {
        final mapped = mapDailyWearWeather({
          'status': 'available',
          'temperature_c': 30,
          'raw': {'code': 0}, // no apparent_temperature key at all
        });
        expect(mapped.feel, 30);
      },
    );

    test('absent feels_like_c falls back to actual temperature', () {
      final mapped = mapDailyWearWeather({
        'status': 'available',
        'temperature_c': 19,
        // no feels_like_c at the top level either
        'raw': {'code': 3},
      });
      expect(mapped.feel, 19);
    });

    test('a genuine apparent_temperature, when present, is used as feel', () {
      final mapped = mapDailyWearWeather({
        'status': 'available',
        'temperature_c': 25,
        'raw': {'code': 0, 'apparent_temperature': 31},
      });
      expect(mapped.temp, 25);
      expect(mapped.feel, 31);
    });

    test(
      'a malformed (non-numeric) feels-like value degrades safely to actual temperature',
      () {
        final mapped = mapDailyWearWeather({
          'status': 'available',
          'temperature_c': 24,
          'raw': {'code': 1, 'apparent_temperature': 'n/a'},
        });
        expect(mapped.feel, 24);
      },
    );

    test('unavailable status throws instead of fabricating a reading', () {
      expect(
        () => mapDailyWearWeather({
          'status': 'unavailable',
          'reason': 'weather_location_missing',
        }),
        throwsStateError,
      );
    });

    test('malformed temperature throws instead of fabricating a reading', () {
      expect(
        () => mapDailyWearWeather({
          'status': 'available',
          'temperature_c': 'not-a-number',
          'raw': {'code': 0},
        }),
        throwsStateError,
      );
    });

    test('missing weather code throws instead of fabricating a reading', () {
      expect(
        () => mapDailyWearWeather({
          'status': 'available',
          'temperature_c': 22,
          'raw': <String, dynamic>{},
        }),
        throwsStateError,
      );
    });
  });

  test('DailyWear routes weather through BackendService, not direct HTTP', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('BackendService().getCurrentWeather()'));
    expect(source, isNot(contains('api.open-meteo.com')));
    expect(source, isNot(contains("package:http/http.dart")));
  });
}
