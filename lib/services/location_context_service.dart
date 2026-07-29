import 'dart:async';
import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracy;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

typedef LocationProfileWriter =
    Future<void> Function(String userId, Map<String, dynamic> locationContext);

/// Resolves and caches the canonical location context used by AHVI requests.
///
/// The deployed Appwrite user profile has no location/context JSON field. The
/// default therefore persists locally only; [profileWriter] is an opt-in seam
/// for a future, schema-supported profile mechanism. Local persistence always
/// completes before that writer is attempted.
class LocationContextService {
  static const Duration defaultFreshness = Duration(minutes: 30);
  static const Duration defaultTimeout = Duration(seconds: 12);
  static const String _keyPrefix = 'ahvi_location_context_v1.';

  final AppwriteService? _appwriteService;
  final Duration freshness;
  final Duration timeout;
  final Future<String?> Function()? _userIdProvider;
  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<LocationFix> Function() _getPosition;
  final Future<String?> Function(double lat, double lon) _labelResolver;
  final DateTime Function() _now;
  final String Function() _timezone;
  final LocationProfileWriter? _profileWriter;
  final Map<String, Future<Map<String, dynamic>>> _inFlight = {};

  LocationContextService({
    AppwriteService? appwriteService,
    this.freshness = defaultFreshness,
    this.timeout = defaultTimeout,
    Future<String?> Function()? userIdProvider,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<LocationFix> Function()? getPosition,
    Future<String?> Function(double lat, double lon)? labelResolver,
    DateTime Function()? now,
    String Function()? timezone,
    LocationProfileWriter? profileWriter,
  }) : _appwriteService = appwriteService,
       _userIdProvider = userIdProvider,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _getPosition = getPosition ?? _defaultPosition,
       _labelResolver = labelResolver ?? _defaultLabel,
       _now = now ?? DateTime.now,
       _timezone = timezone ?? (() => DateTime.now().timeZoneName),
       _profileWriter = profileWriter;

  Future<Map<String, dynamic>> getLocationContext({
    String? userId,
    bool forceRefresh = false,
    bool requestIfDenied = true,
  }) async {
    final resolvedUserId = (userId ?? await _resolveUserId())?.trim() ?? '';
    if (resolvedUserId.isEmpty) {
      return _emptyContext(permission: 'unauthenticated');
    }

    final cached = await _read(resolvedUserId);
    if (!forceRefresh && cached != null && _isFresh(cached)) {
      return {...cached, 'source': 'cache'};
    }

    final existing = _inFlight[resolvedUserId];
    if (existing != null) return existing;

    final refresh = _refresh(
      resolvedUserId,
      cached,
      requestIfDenied: requestIfDenied,
    );
    _inFlight[resolvedUserId] = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_inFlight[resolvedUserId], refresh)) {
        _inFlight.remove(resolvedUserId);
      }
    }
  }

  Future<void> clear({String? userId, bool allUsers = false}) async {
    final prefs = await _preferencesProvider();
    if (allUsers) {
      await Future.wait(
        prefs
            .getKeys()
            .where((key) => key.startsWith(_keyPrefix))
            .map(prefs.remove),
      );
      _inFlight.clear();
      return;
    }

    final resolvedUserId = (userId ?? await _resolveUserId())?.trim() ?? '';
    if (resolvedUserId.isEmpty) return;
    await prefs.remove(_cacheKey(resolvedUserId));
    _inFlight.remove(resolvedUserId);
  }

  Future<Map<String, dynamic>> _refresh(
    String userId,
    Map<String, dynamic>? stale, {
    required bool requestIfDenied,
  }) async {
    try {
      if (!await _serviceEnabled()) {
        return _controlledFailure('disabled', stale);
      }

      var permission = await _checkPermission();
      if (permission == LocationPermission.denied && requestIfDenied) {
        permission = await _requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return _controlledFailure('denied_forever', stale);
      }
      if (permission == LocationPermission.denied) {
        return _controlledFailure('denied', stale);
      }

      final fix = await _getPosition().timeout(timeout);
      String? label;
      try {
        label = await _labelResolver(
          fix.latitude,
          fix.longitude,
        ).timeout(timeout);
      } catch (_) {
        // Coordinates are still valid when reverse geocoding is unavailable.
      }
      final context = <String, dynamic>{
        'lat': _weatherPrecision(fix.latitude),
        'lon': _weatherPrecision(fix.longitude),
        'timezone': _resolvedTimezone(),
        'label': (label == null || label.trim().isEmpty)
            ? '${fix.latitude.toStringAsFixed(4)}, ${fix.longitude.toStringAsFixed(4)}'
            : label.trim(),
        'captured_at': _now().toUtc().toIso8601String(),
        'source': 'device',
        'permission': 'granted',
        'accuracy_m': fix.accuracy,
      };

      final prefs = await _preferencesProvider();
      await prefs.setString(_cacheKey(userId), jsonEncode(context));
      try {
        await _profileWriter?.call(userId, context);
      } catch (_) {
        // The canonical local cache must survive optional profile sync failure.
      }
      return context;
    } on TimeoutException {
      return _controlledFailure('timeout', stale);
    } catch (_) {
      return _controlledFailure('unavailable', stale);
    }
  }

  Future<String?> _resolveUserId() async {
    if (_userIdProvider != null) return _userIdProvider();
    final appwrite = _appwriteService ?? AppwriteService();
    return (await appwrite.getCurrentUser())?.$id;
  }

  Future<Map<String, dynamic>?> _read(String userId) async {
    final prefs = await _preferencesProvider();
    final raw = prefs.getString(_cacheKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final value = Map<String, dynamic>.from(decoded);
      return _isCanonical(value) ? value : null;
    } catch (_) {
      return null;
    }
  }

  bool _isFresh(Map<String, dynamic> context) {
    final capturedAt = DateTime.tryParse(context['captured_at'].toString());
    return capturedAt != null && _now().difference(capturedAt) < freshness;
  }

  bool _isCanonical(Map<String, dynamic> value) {
    const keys = {
      'lat',
      'lon',
      'timezone',
      'label',
      'captured_at',
      'source',
      'permission',
      'accuracy_m',
    };
    return value.keys.toSet().containsAll(keys) &&
        value['lat'] is num &&
        value['lon'] is num &&
        DateTime.tryParse(value['captured_at'].toString()) != null;
  }

  Map<String, dynamic> _controlledFailure(
    String permission,
    Map<String, dynamic>? stale,
  ) {
    if (stale != null) {
      return {...stale, 'source': 'stale_cache', 'permission': permission};
    }
    return _emptyContext(permission: permission);
  }

  Map<String, dynamic> _emptyContext({required String permission}) => {
    'lat': null,
    'lon': null,
    'timezone': _resolvedTimezone(),
    'label': '',
    'captured_at': _now().toUtc().toIso8601String(),
    'source': 'none',
    'permission': permission,
    'accuracy_m': null,
  };

  String _resolvedTimezone() {
    final value = _timezone().trim();
    return value.isEmpty ? 'UTC' : value;
  }

  double _weatherPrecision(double value) =>
      double.parse(value.toStringAsFixed(3));

  String _cacheKey(String userId) =>
      '$_keyPrefix${base64Url.encode(utf8.encode(userId))}';

  static Future<LocationFix> _defaultPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  static Future<String?> _defaultLabel(double lat, double lon) async {
    final places = await placemarkFromCoordinates(lat, lon);
    if (places.isEmpty) return null;
    final place = places.first;
    final locality =
        <String?>[
              place.locality,
              place.subAdministrativeArea,
              place.administrativeArea,
            ]
            .whereType<String>()
            .map((part) => part.trim())
            .firstWhere((part) => part.isNotEmpty, orElse: () => '');
    final country = (place.isoCountryCode ?? '').trim().toUpperCase();
    if (locality.isEmpty) return country.isEmpty ? null : country;
    return country.isEmpty ? locality : '$locality, $country';
  }
}
