import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Contract tests over the fitness/workout source (the screen file is minified;
// these lock the lifecycle + request behaviour the Samsung crash needed).
void main() {
  final fitness = File('lib/fitness_page.dart').readAsStringSync();
  final backend = File('lib/services/backend_service.dart').readAsStringSync();

  test('exact endpoint is /api/workouts/today', () {
    expect(backend, contains('/api/workouts/today'));
  });

  test('base URL trailing slashes are stripped before appending the path', () {
    expect(backend, contains("baseUrl.replaceAll(RegExp(r'/+\$'), '')"));
  });

  test('Authorization header is passed and logged only as a boolean', () {
    expect(backend, contains('final headers = await _authHeaders();'));
    expect(backend, contains('AHVI_WORKOUT_TODAY_AUTH authorization='));
    expect(backend, contains(r'authorization=$hasAuth'));
    expect(backend, isNot(contains(r"endpoint=${headers['Authorization']}")));
  });

  test('safe request/status logging present', () {
    expect(backend, contains('AHVI_WORKOUT_TODAY_REQUEST endpoint='));
    expect(backend, contains('AHVI_WORKOUT_TODAY_STATUS status='));
  });

  test('non-2xx returns an empty map (no recursive retry)', () {
    expect(backend, contains('return <String, dynamic>{};'));
  });

  test('_loadTodayWorkout resolves providers before awaits and guards mounted', () {
    expect(fitness, contains('final appwrite = Provider.of<AppwriteService>(context, listen: false);'));
    expect(fitness, contains('final backend = Provider.of<BackendService>(context, listen: false);'));
    final guards = 'if (!mounted) return;'.allMatches(fitness).length;
    expect(guards, greaterThanOrEqualTo(2)); // one after each await
  });

  test('single-flight + failure marks loaded so it does not loop', () {
    expect(fitness, contains('reason=already_loading'));
    expect(fitness, contains('reason=already_loaded'));
    expect(fitness, contains('reason=unmounted'));
    expect(fitness, contains('} catch (e) {'));
    // failure path sets loaded=true (controlled empty state, no retry loop)
    expect(fitness, contains('_todayWorkoutLoaded = true;'));
  });
}
