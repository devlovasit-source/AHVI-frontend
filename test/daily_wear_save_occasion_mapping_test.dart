import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';

void main() {
  group('Daily Wear save-sheet occasion -> canonical bucket mapping', () {
    const expected = {
      'Daily Wear': 'everything_else',
      'Office Fits': 'office_fits',
      'Party Looks': 'party_looks',
      'Vacation & Travel': 'vacation',
      'Occasions & Events': 'occasion',
      'Everything Else': 'everything_else',
    };

    for (final entry in expected.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        final match = dailyWearSaveOccasionOptions.firstWhere(
          (option) => option.$2 == entry.key,
        );
        expect(match.$1, entry.value);
      });
    }

    test('every option bucket is a valid canonical SavedBoardSelection bucket', () {
      for (final option in dailyWearSaveOccasionOptions) {
        expect(savedBoardBuckets.contains(option.$1), isTrue,
            reason: '${option.$1} (${option.$2}) is not a real bucket');
        expect(canonicalSavedBoardBucket(option.$1), option.$1,
            reason: '${option.$1} must already be canonical, not fuzzy-mapped');
      }
    });
  });
}
