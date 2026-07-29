// User/date cache isolation for BackendService.getTodayWorkout.
//
// Exercises the scoped cache key, logout/user-switch invalidation, and the
// stale-in-flight rejection — all without real HTTP or Appwrite.
// Coordination behaviour (single-flight, no-auto-retry) is covered separately
// in workout_today_coordination_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/backend_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test\n'
          'EXPO_PUBLIC_APPWRITE_PROJECT_ID=proj\n'
          'EXPO_PUBLIC_BACKEND_API_URL=https://api.test/',
      isOptional: true,
    );
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

  BackendService _scoped({
    required String userId,
    required String date,
    required Map<String, dynamic> Function() response,
  }) {
    final b = BackendService();
    b.debugCurrentUserIdProvider = () async => userId;
    b.debugLocalDateProvider = () => date;
    b.debugTodayWorkoutFetcher = () async => response();
    return b;
  }

  group('workout cache isolation', () {
    test('same user+date reuses cache', () async {
      int fetches = 0;
      final b = _scoped(
        userId: 'user-A',
        date: '2024-01-15',
        response: () {
          fetches++;
          return {'today_workout': {'id': 'w1'}};
        },
      );

      await b.getTodayWorkout();
      await b.getTodayWorkout();

      expect(fetches, 1, reason: 'second call should hit cache');
    });

    test('different user does not reuse cache', () async {
      int fetches = 0;
      final b = BackendService();
      b.debugLocalDateProvider = () => '2024-01-15';
      b.debugTodayWorkoutFetcher = () async {
        fetches++;
        return {'today_workout': {'id': 'w$fetches'}};
      };

      b.debugCurrentUserIdProvider = () async => 'user-A';
      await b.getTodayWorkout();
      expect(fetches, 1);

      b.debugCurrentUserIdProvider = () async => 'user-B';
      final r = await b.getTodayWorkout();
      expect(fetches, 2, reason: 'user-B must not see user-A cache');
      expect((r['today_workout'] as Map)['id'], 'w2');
    });

    test('next local date does not reuse cache', () async {
      int fetches = 0;
      final b = BackendService();
      b.debugCurrentUserIdProvider = () async => 'user-A';
      b.debugTodayWorkoutFetcher = () async {
        fetches++;
        return {'today_workout': {'id': 'w$fetches'}};
      };

      b.debugLocalDateProvider = () => '2024-01-15';
      await b.getTodayWorkout();
      expect(fetches, 1);

      b.debugLocalDateProvider = () => '2024-01-16';
      await b.getTodayWorkout();
      expect(fetches, 2, reason: 'next day must not see previous day cache');
    });

    test('logout clears cache', () async {
      int fetches = 0;
      final b = _scoped(
        userId: 'user-A',
        date: '2024-01-15',
        response: () {
          fetches++;
          return {'today_workout': {'id': 'w1'}};
        },
      );

      await b.getTodayWorkout();
      expect(fetches, 1);

      b.clearTodayWorkoutCache(); // mirrors what AppwriteService.clearUserCache triggers
      await b.getTodayWorkout();
      expect(fetches, 2, reason: 'post-logout call must not hit cache');
    });

    test('user switching clears cache', () async {
      int fetches = 0;
      final b = BackendService();
      b.debugLocalDateProvider = () => '2024-01-15';
      b.debugTodayWorkoutFetcher = () async {
        fetches++;
        return {'today_workout': {'id': 'w$fetches'}};
      };

      b.debugCurrentUserIdProvider = () async => 'user-A';
      await b.getTodayWorkout();

      // Simulate user switch: auth fires clearTodayWorkoutCache, new user set
      b.clearTodayWorkoutCache();
      b.debugCurrentUserIdProvider = () async => 'user-B';
      await b.getTodayWorkout();

      expect(fetches, 2, reason: 'user-B must fetch fresh after switch');
    });

    test('concurrent same-user requests remain deduplicated', () async {
      int fetches = 0;
      final gate = Completer<Map<String, dynamic>>();
      final b = BackendService();
      b.debugCurrentUserIdProvider = () async => 'user-A';
      b.debugLocalDateProvider = () => '2024-01-15';
      b.debugTodayWorkoutFetcher = () {
        fetches++;
        return gate.future;
      };

      final f1 = b.getTodayWorkout();
      final f2 = b.getTodayWorkout();

      gate.complete({'today_workout': {'id': 'w1'}});
      final results = await Future.wait([f1, f2]);

      expect(fetches, 1, reason: 'concurrent same-user calls share one in-flight');
      expect(results[0], equals(results[1]));
    });

    test('stale in-flight cannot repopulate cache after logout', () async {
      bool fetcherStarted = false;
      final dataGate = Completer<Map<String, dynamic>>();
      final b = BackendService();
      b.debugCurrentUserIdProvider = () async => 'user-A';
      b.debugLocalDateProvider = () => '2024-01-15';
      b.debugTodayWorkoutFetcher = () {
        fetcherStarted = true;
        return dataGate.future;
      };

      // Start the call. Because debugCurrentUserIdProvider is async, the
      // function body suspends at `await` before reaching the fetcher — so
      // the fetcher (and therefore the in-flight slot) hasn't started yet.
      final staleFuture = b.getTodayWorkout();

      // Pump the event loop until the fetcher is called and the in-flight
      // slot is live, so the subsequent clear actually races a real in-flight.
      while (!fetcherStarted) {
        await Future(() {});
      }

      // In-flight is live. Simulate logout before it completes.
      b.clearTodayWorkoutCache();

      dataGate.complete({'today_workout': {'id': 'stale-data'}});
      await staleFuture; // caller gets the result; that is expected

      // Cache must be empty — the stale result must not have written to it
      int freshFetches = 0;
      b.debugTodayWorkoutFetcher = () async {
        freshFetches++;
        return {'today_workout': {'id': 'fresh-data'}};
      };
      final fresh = await b.getTodayWorkout();

      expect(
        (fresh['today_workout'] as Map)['id'],
        'fresh-data',
        reason: 'stale in-flight must not populate cache after logout',
      );
      expect(freshFetches, 1);
    });
  });
}
