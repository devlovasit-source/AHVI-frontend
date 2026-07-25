// Source-contract tests for the Fitness today-workout lifecycle fix.
//
// _WorkoutStudioScreenState lives in a single-line (minified) source file, so
// instantiating the full widget in a harness is impractical and brittle. These
// tests instead assert the concrete lifecycle guarantees as source contracts:
// providers resolved before any await, a mounted-check after every await, a
// dispose() that logs and touches no context, and a controlled non-retrying
// failure path. The runtime behaviour of the request coordination is proven
// separately in workout_today_coordination_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Returns the brace-matched body of the method whose signature contains
/// [marker] (searching from [from]). The body brace is located AFTER the
/// parameter list's closing `)`, so a named-parameter brace like
/// `({bool x = false})` does not confuse the matcher. Uses plain exceptions
/// (not `expect`) so it can be called at group-collection scope.
String _methodBody(String source, String marker, {int from = 0}) {
  final start = source.indexOf(marker, from);
  if (start < 0) throw StateError('marker not found: $marker');
  // Paren-match the parameter list.
  final paren = source.indexOf('(', start);
  var pd = 0;
  var afterParams = -1;
  for (var i = paren; i < source.length; i++) {
    if (source[i] == '(') pd++;
    if (source[i] == ')') {
      pd--;
      if (pd == 0) {
        afterParams = i + 1;
        break;
      }
    }
  }
  if (afterParams < 0) throw StateError('no param list for $marker');
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('unbalanced braces for $marker');
}

void main() {
  final fitness = _read('lib/fitness_page.dart');
  final backend = _read('lib/services/backend_service.dart');
  final home = _read('lib/home.dart');

  group('fitness_page _loadTodayWorkout lifecycle safety', () {
    final body = _methodBody(fitness, 'Future<void> _loadTodayWorkout() async');

    test('skips with a logged reason when already unmounted', () {
      expect(body, contains("if (!mounted) {"));
      expect(body,
          contains("AHVI_WORKOUT_TODAY_SKIPPED reason=unmounted"));
    });

    test('resolves both providers before the first await', () {
      final backendResolve = body.indexOf(
          'Provider.of<BackendService>(context, listen: false)');
      final appwriteResolve = body.indexOf(
          'Provider.of<AppwriteService>(context, listen: false)');
      final firstAwait = body.indexOf('await appwrite.refreshCurrentUserProfile');
      expect(appwriteResolve, isNonNegative);
      expect(backendResolve, isNonNegative);
      expect(appwriteResolve, lessThan(firstAwait),
          reason: 'context must be read before awaiting');
      expect(backendResolve, lessThan(firstAwait),
          reason: 'context must be read before awaiting');
    });

    test('checks mounted after every await', () {
      // Both network awaits are immediately followed by a mounted guard.
      expect(
        body,
        contains(RegExp(
            r'await appwrite\.refreshCurrentUserProfile\(\);\s*if \(!mounted\) return;')),
      );
      expect(
        body,
        contains(RegExp(
            r'await backend\.getTodayWorkout\(\);\s*if \(!mounted\) return;')),
      );
    });

    test('failure path is controlled: loading=false, loaded=true, no retry', () {
      final catchStart = body.indexOf('catch (e)');
      expect(catchStart, isNonNegative);
      final catchBody = body.substring(catchStart);
      expect(catchBody, contains('_todayWorkoutLoading = false'));
      expect(catchBody, contains('_todayWorkoutLoaded = true'));
      // The failure path never re-invokes the loader (no automatic retry).
      expect(catchBody, isNot(contains('_loadTodayWorkout(')));
    });

    test('an explicit user retry entry point exists', () {
      expect(fitness, contains('void _retryTodayWorkout()'));
      expect(fitness, contains('clearTodayWorkoutCache()'));
    });
  });

  group('fitness_page dispose', () {
    // Scope to the workout-state dispose: find the dispose() that precedes the
    // DISPOSED marker (the file has several State classes with dispose()).
    final disposedAt = fitness.indexOf('AHVI_WORKOUT_TODAY_DISPOSED');
    final disposeStart = fitness.lastIndexOf('void dispose()', disposedAt);
    final body = _methodBody(fitness, 'void dispose()', from: disposeStart);

    test('logs the disposed marker and calls super', () {
      expect(body, contains('AHVI_WORKOUT_TODAY_DISPOSED'));
      expect(body, contains('super.dispose()'));
    });

    test('never touches context, setState or navigation in dispose', () {
      expect(body, isNot(contains('setState')));
      expect(body, isNot(contains('Provider.of')));
      expect(body, isNot(contains('ScaffoldMessenger')));
      expect(body, isNot(contains('Navigator')));
      // debugPrint is a bare string log — the only allowed context here is none.
    });
  });

  group('backend_service getTodayWorkout contract', () {
    final get = _methodBody(
        backend, 'Future<Map<String, dynamic>> getTodayWorkout(');
    final fetch = _methodBody(
        backend, 'Future<Map<String, dynamic>> _fetchTodayWorkout()');

    test('single-flight and session cache fields exist', () {
      expect(backend, contains('Future<Map<String, dynamic>>? _todayWorkoutInFlight'));
      expect(backend, contains('Map<String, dynamic>? _todayWorkoutCache'));
    });

    test('emits cached and already_loading skip logs', () {
      expect(get, contains('AHVI_WORKOUT_TODAY_SKIPPED reason=cached'));
      expect(get, contains('AHVI_WORKOUT_TODAY_SKIPPED reason=already_loading'));
    });

    test('emits request/auth/status logs', () {
      expect(fetch, contains('AHVI_WORKOUT_TODAY_REQUEST endpoint='));
      expect(fetch, contains('AHVI_WORKOUT_TODAY_AUTH authorization='));
      expect(fetch, contains('AHVI_WORKOUT_TODAY_STATUS status='));
    });

    test('never logs the Authorization token', () {
      // The auth log is a boolean only; the bearer token is never interpolated
      // into any debugPrint.
      expect(fetch, contains(r'AHVI_WORKOUT_TODAY_AUTH authorization=$hasAuth'));
      for (final line in fetch.split('\n')) {
        if (line.contains('debugPrint')) {
          expect(line.toLowerCase().contains('bearer'), isFalse);
          expect(line.contains(r'$token'), isFalse);
        }
      }
    });

    test('normalizes trailing slashes once and hits the exact route', () {
      expect(fetch, contains(r"baseUrl.replaceAll(RegExp(r'/+$'), '')"));
      expect(fetch, contains(r"'$root/api/workouts/today'"));
      expect(backend, isNot(contains('/api/workout/today'))); // no typo variant
    });

    test('non-2xx returns an empty map (controlled empty state, no retry)', () {
      expect(fetch, contains('return <String, dynamic>{}'));
      // No retry/backoff loop inside the fetch.
      expect(fetch, isNot(contains('while (')));
      expect(fetch, isNot(contains('for (')));
    });
  });

  group('cross-screen coordination', () {
    test('home.dart routes its workout request through the shared service', () {
      expect(home, contains('backend.getTodayWorkout()'),
          reason: 'home must share BackendService coordination, not fetch alone');
    });
  });
}
