// Regression tests for Home card copy readability (Prep & Plan + Move).
//
// _getWorkoutDescription() is library-private to lib/home.dart and reads
// through Provider.of<HomeCardSummaryProvider>, so — matching the existing
// convention in test/daily_wear_weather_location_test.dart and
// test/home_weather_fabrication_test.dart — the Move fix is a source-level
// regression assertion. The Prep & Plan fix is plain localization-asset copy
// and is asserted directly. Widget-level behavior for the shared
// HomeRoutineCarousel context field is covered in
// test/home_routine_carousel_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PREP_COPY_COMPLETE', () {
    final enStrings = jsonDecode(
      File('assets/lang/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('prep_card_desc is the approved short, complete phrase', () {
      expect(enStrings['prep_card_desc'], 'Meals, outfits & schedule — planned for you');
    });

    test('prep_card_desc no longer contains the truncation-prone long sentence', () {
      expect(enStrings['prep_card_desc'], isNot(contains('all in one place')));
    });

    test('prep_card_desc is short enough for a 2-line ellipsis-free render '
        'in the narrow (35%-width) Prep & Plan text column', () {
      // The column renders at ~8.5-9pt in a flex:35 card slice; the
      // previous 58-char sentence truncated to "...Schedule- al...". The
      // replacement is comfortably shorter.
      expect((enStrings['prep_card_desc'] as String).length, lessThan(50));
    });
  });

  group('MOVE_COPY_COMPLETE', () {
    final source = File('lib/home.dart').readAsStringSync();

    String extractMethod(String signature, String nextSignature) {
      final start = source.indexOf(signature);
      if (start < 0) throw StateError('$signature not found');
      final end = source.indexOf(nextSignature, start);
      if (end <= start) {
        throw StateError('$nextSignature not found after $signature');
      }
      return source.substring(start, end);
    }

    final workoutDescription = extractMethod(
      'String _getWorkoutDescription() {',
      'String _getWorkoutStatus() {',
    );

    test('the provider subtitle is rendered in full, not hard-cut to 17 chars + "..."', () {
      expect(workoutDescription, isNot(contains('substring(0, 17)')));
      expect(workoutDescription, isNot(contains("sub.length > 20")));
    });

    test('the workout-label fallback branch is also no longer hard-cut', () {
      expect(workoutDescription, isNot(contains('displayLabel.length > 20')));
    });

    test('the short static fallback ("7-min stretch") is untouched — no new hardcoded workout copy', () {
      expect(workoutDescription, contains("AppLocalizations.t(context, 'routine_move_desc')"));
    });
  });
}
