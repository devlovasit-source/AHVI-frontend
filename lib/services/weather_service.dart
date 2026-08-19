import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherResult {
  final double temperature;
  final double apparentTemperature;
  final int weatherCode;
  final bool isDay;
  final double latitude;
  final double longitude;

  const WeatherResult({
    required this.temperature,
    required this.apparentTemperature,
    required this.weatherCode,
    required this.isDay,
    required this.latitude,
    required this.longitude,
  });
}

class WeatherService {
  static const String _openMeteoUrl =
      'https://api.open-meteo.com/v1/forecast';

  static Future<Position?> _getPosition() async {
    try {
      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Weather: location permission unavailable');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (e) {
      debugPrint('Weather location error: $e');
      return null;
    }
  }

  static Future<WeatherResult?> fetchWeather() async {
    try {
      final position = await _getPosition();

      if (position == null) {
        return null;
      }

      final latitude = position.latitude;
      final longitude = position.longitude;

      final uri = Uri.parse(_openMeteoUrl).replace(
        queryParameters: {
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
          'current':
              'temperature_2m,apparent_temperature,weather_code,is_day',
          'temperature_unit': 'celsius',
          'timezone': 'auto',
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint(
          'Weather API failed: ${response.statusCode}',
        );
        return null;
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      final current =
          data['current'] as Map<String, dynamic>?;

      if (current == null) {
        return null;
      }

      return WeatherResult(
        temperature:
            (current['temperature_2m'] as num).toDouble(),
        apparentTemperature:
            (current['apparent_temperature'] as num).toDouble(),
        weatherCode:
            (current['weather_code'] as num).toInt(),
        isDay: current['is_day'] == 1,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('Weather fetch error: $e');
      return null;
    }
  }

  static String getDescription(int code) {
    if (code == 0) return 'Clear';

    if (code == 1 || code == 2) {
      return 'Partly Cloudy';
    }

    if (code == 3) {
      return 'Overcast';
    }

    if ([45, 48].contains(code)) {
      return 'Foggy';
    }

    if ([51, 53, 55, 56, 57].contains(code)) {
      return 'Drizzle';
    }

    if ([61, 63, 65, 66, 67].contains(code)) {
      return 'Rainy';
    }

    if ([71, 73, 75, 77, 85, 86].contains(code)) {
      return 'Snowy';
    }

    if ([80, 81, 82].contains(code)) {
      return 'Showers';
    }

    if ([95, 96, 99].contains(code)) {
      return 'Thunderstorm';
    }

    return 'Partly Cloudy';
  }

  static String getIcon(int code) {
    if (code == 0) return '☀️';
    if ([1, 2, 3].contains(code)) return '☁️';
    if ([45, 48].contains(code)) return '🌫️';
    if ([51, 53, 55, 56, 57].contains(code)) return '🌦️';
    if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) {
      return '🌧️';
    }
    if ([95, 96, 99].contains(code)) return '⛈️';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return '❄️';

    return '☁️';
  }
}