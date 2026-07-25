// Behavioural tests for the today-workout request coordination that fixes the
// Samsung Fitness P0 (repeated /api/workouts/today calls + request storm).
//
// These drive BackendService directly through its `debugTodayWorkoutFetcher`
// seam so the cache / single-flight / no-auto-retry logic is exercised without
// real HTTP or Appwrite. The widget-lifecycle guarantees (mounted checks,
// dispose logging, no context-after-dispose) are asserted in
// workout_today_lifecycle_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/backend_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // BackendService reads Env.backendApiUrl and constructs the AppwriteService
    // singleton (which reads the Appwrite env) at construction time.
    dotenv.loadFromString(
      envString: 'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test\n'
          'EXPO_PUBLIC_APPWRITE_PROJECT_ID=proj\n'
          'EXPO_PUBLIC_BACKEND_API_URL=https://api.test/',
      isOptional: true,
    );

    // Appwrite's ClientIO.init() calls getApplicationDocumentsDirectory() and
    // PackageInfo.fromPlatform() during Client construction; mock those plugin
    // channels so the singleton builds cleanly in the test binding.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'ahvi_test',
        'packageName': 'com.ahvi.test',
        'version': '1.0.0',
        'buildNumber': '1',
      },
    );
  });

  group('BackendService.getTodayWorkout coordination', () {
    late BackendService backend;
    late int fetchCount;

    setUp(() {
      backend = BackendService();
      fetchCount = 0;
    });

    test('repeated rebuild-driven calls trigger exactly one fetch then cache',
        () async {
      backend.debugTodayWorkoutFetcher = () async {
        fetchCount++;
        return {
          'today_workout': {'id': 'w1', 'title': 'Leg Day'},
        };
      };

      final r1 = await backend.getTodayWorkout();
      final r2 = await backend.getTodayWorkout();
      final r3 = await backend.getTodayWorkout();

      expect(fetchCount, 1, reason: 'rebuilds must not add HTTP requests');
      expect((r1['today_workout'] as Map)['id'], 'w1');
      expect(r2, equals(r1));
      expect(r3, equals(r1));
    });

    test('home + fitness concurrent callers share one in-flight request',
        () async {
      final gate = Completer<Map<String, dynamic>>();
      backend.debugTodayWorkoutFetcher = () {
        fetchCount++;
        return gate.future;
      };

      // Both consumers ask before the first response returns.
      final home = backend.getTodayWorkout();
      final fitness = backend.getTodayWorkout();
      expect(fetchCount, 1, reason: 'no request storm across screens');

      gate.complete({
        'today_workout': {'id': 'w2', 'title': 'HIIT'},
      });
      final results = await Future.wait([home, fitness]);

      expect(results[0], equals(results[1]));
      expect(fetchCount, 1);
    });

    test('a failed (empty) result is not cached and never auto-retries',
        () async {
      backend.debugTodayWorkoutFetcher = () async {
        fetchCount++;
        return <String, dynamic>{}; // models a 404/500 collapsed to {}
      };

      final r = await backend.getTodayWorkout();
      expect(r, isEmpty);
      expect(fetchCount, 1,
          reason: 'a single call performs exactly one fetch, no retry loop');

      // A later call performs exactly one more fetch — one per explicit call,
      // never a multiplying automatic retry.
      await backend.getTodayWorkout();
      expect(fetchCount, 2);
    });

    test('explicit retry (forceRefresh / clearCache) refetches after success',
        () async {
      backend.debugTodayWorkoutFetcher = () async {
        fetchCount++;
        return {
          'today_workout': {'id': 'w$fetchCount'},
        };
      };

      await backend.getTodayWorkout(); // fetch 1, cached
      await backend.getTodayWorkout(); // served from cache
      expect(fetchCount, 1);

      final forced = await backend.getTodayWorkout(forceRefresh: true);
      expect(fetchCount, 2);
      expect((forced['today_workout'] as Map)['id'], 'w2');

      backend.clearTodayWorkoutCache();
      await backend.getTodayWorkout();
      expect(fetchCount, 3);
    });

    test('a 200 result is returned to the caller so the workout renders',
        () async {
      backend.debugTodayWorkoutFetcher = () async => {
            'today_workout': {
              'id': 'w9',
              'title': 'Yoga Flow',
              'duration_minutes': 20,
            },
          };

      final r = await backend.getTodayWorkout();
      expect((r['today_workout'] as Map)['title'], 'Yoga Flow');
    });
  });
}
