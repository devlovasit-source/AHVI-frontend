import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myapp/services/location_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late String userId;
  late int gpsCalls;

  LocationContextService service({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<LocationFix> Function()? getPosition,
    LocationProfileWriter? profileWriter,
    Duration freshness = const Duration(minutes: 30),
    Duration timeout = const Duration(milliseconds: 20),
  }) {
    return LocationContextService(
      userIdProvider: () async => userId,
      serviceEnabled: serviceEnabled ?? () async => true,
      checkPermission:
          checkPermission ?? () async => LocationPermission.whileInUse,
      requestPermission:
          requestPermission ?? () async => LocationPermission.whileInUse,
      getPosition:
          getPosition ??
          () async {
            gpsCalls++;
            return LocationFix(
              latitude: 12.9 + gpsCalls,
              longitude: 77.5,
              accuracy: 8,
            );
          },
      labelResolver: (lat, lon) async => 'Bengaluru, IN',
      now: () => now,
      timezone: () => 'Asia/Kolkata',
      profileWriter: profileWriter,
      freshness: freshness,
      timeout: timeout,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 7, 29, 10);
    userId = 'user-a';
    gpsCalls = 0;
  });

  test('returns the canonical contract and fresh cache avoids GPS', () async {
    final subject = service();

    final first = await subject.getLocationContext();
    final cached = await subject.getLocationContext();

    expect(first.keys.toSet(), {
      'lat',
      'lon',
      'timezone',
      'label',
      'captured_at',
      'source',
      'permission',
      'accuracy_m',
    });
    expect(first['source'], 'device');
    expect(first['lat'], 13.9);
    expect(cached['source'], 'cache');
    expect(cached['captured_at'], first['captured_at']);
    expect(gpsCalls, 1);
  });

  test('stale cache refreshes from GPS', () async {
    final subject = service(freshness: const Duration(minutes: 5));
    final first = await subject.getLocationContext();
    now = now.add(const Duration(minutes: 6));

    final refreshed = await subject.getLocationContext();

    expect(gpsCalls, 2);
    expect(refreshed['lat'], isNot(first['lat']));
    expect(refreshed['source'], 'device');
  });

  test('cache is isolated across authenticated users', () async {
    final subject = service();
    final userA = await subject.getLocationContext();
    userId = 'user-b';
    final userB = await subject.getLocationContext();
    userId = 'user-a';
    final userAAgain = await subject.getLocationContext();

    expect(gpsCalls, 2);
    expect(userB['lat'], isNot(userA['lat']));
    expect(userAAgain['lat'], userA['lat']);
    expect(userAAgain['source'], 'cache');
  });

  test('local cache survives profile persistence failure', () async {
    final subject = service(
      profileWriter: (userId, context) async => throw Exception('offline'),
    );
    final first = await subject.getLocationContext();
    final replacement = service(
      getPosition: () async => throw Exception('GPS must not run'),
    );

    final cached = await replacement.getLocationContext();

    expect(cached['lat'], first['lat']);
    expect(cached['source'], 'cache');
  });

  test('disabled, denied, deniedForever, and timeout are controlled', () async {
    final disabled = await service(
      serviceEnabled: () async => false,
    ).getLocationContext();
    final denied = await service(
      checkPermission: () async => LocationPermission.denied,
    ).getLocationContext(requestIfDenied: false);
    final deniedForever = await service(
      checkPermission: () async => LocationPermission.deniedForever,
    ).getLocationContext();
    final timeout = await service(
      getPosition: () => Completer<LocationFix>().future,
      timeout: const Duration(milliseconds: 1),
    ).getLocationContext();

    expect(disabled['permission'], 'disabled');
    expect(denied['permission'], 'denied');
    expect(deniedForever['permission'], 'denied_forever');
    expect(timeout['permission'], 'timeout');
    expect(timeout['source'], 'none');
  });

  test('clear removes one user or every user cache', () async {
    final subject = service();
    await subject.getLocationContext();
    await subject.clear();
    await subject.getLocationContext();
    expect(gpsCalls, 2);

    userId = 'user-b';
    await subject.getLocationContext();
    await subject.clear(allUsers: true);
    userId = 'user-a';
    await subject.getLocationContext();
    expect(gpsCalls, 4);
  });
}
