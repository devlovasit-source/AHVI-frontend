import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/style_mutation_contract.dart';

void main() {
  const previous = <String, dynamic>{
    'board_id': 'board-1',
    'title': 'Curated Weekend Edit',
    'why_it_works': 'The balanced palette keeps the look intentional.',
    'styling_tip': 'Cuff the sleeves once for a cleaner finish.',
  };

  test('missing narrative is retained for a single-board mutation', () {
    final result = retainBoardNarrative([
      {'board_id': 'new-mutation-id', 'board_items': const []},
    ], previous);

    expect(result.single['title'], previous['title']);
    expect(result.single['why_it_works'], previous['why_it_works']);
    expect(result.single['styling_tip'], previous['styling_tip']);
  });

  test('missing title retains curated title over a generic archetype echo', () {
    final result = retainBoardNarrative([
      {
        'board_id': 'board-1',
        'style_archetype': 'Elevated Essentials',
      },
    ], previous);

    expect(result.single['title'], 'Curated Weekend Edit');
    expect(result.single['style_archetype'], 'Elevated Essentials');
  });

  test('missing why retains the previous rationale', () {
    final result = retainBoardNarrative([
      {'board_id': 'board-1', 'title': 'Fresh Title'},
    ], previous);
    expect(result.single['why_it_works'], previous['why_it_works']);
  });

  test('missing tip retains the previous styling tip', () {
    final result = retainBoardNarrative([
      {'board_id': 'board-1', 'title': 'Fresh Title', 'why_it_works': 'Fresh why'},
    ], previous);
    expect(result.single['styling_tip'], previous['styling_tip']);
  });

  test('fresh narrative values win per semantic group', () {
    final result = retainBoardNarrative([
      {
        'board_id': 'board-1',
        'title': 'Fresh Title',
        'explanation': 'Fresh explanation',
        'style_tip': 'Fresh tip',
      },
    ], previous);

    expect(result.single['title'], 'Fresh Title');
    expect(result.single['explanation'], 'Fresh explanation');
    expect(result.single.containsKey('why_it_works'), isFalse);
    expect(result.single['style_tip'], 'Fresh tip');
    expect(result.single.containsKey('styling_tip'), isFalse);
  });

  test('multi-board responses retain only the matching board narrative', () {
    final result = retainBoardNarrative([
      {'board_id': 'board-1'},
      {'board_id': 'board-2'},
      {'board_id': ''},
    ], previous);

    expect(result[0]['title'], previous['title']);
    expect(result[1].containsKey('title'), isFalse);
    expect(result[2].containsKey('title'), isFalse);
    expect(result[2].containsKey('styling_tip'), isFalse);
  });

  test('style_strategy without a title does not block title retention', () {
    final result = retainBoardNarrative([
      {'board_id': 'board-1', 'style_strategy': <String, dynamic>{}},
    ], previous);
    expect(result.single['title'], previous['title']);
  });

  group('styling_note as WHY narrative (P0.16 mutation fixture)', () {
    const previousBoard = <String, dynamic>{
      'board_id': 'board-1',
      'title': 'Smart Casual Edit',
      'why_it_works':
          'Red Floral Kurta complements Dark Green Blazer, keeping the '
          'Smart Casual direction polished and easy.',
      'styling_tip': 'Roll the sleeves once for an easy finish.',
    };

    Map<String, dynamic> mutationBoard() => {
      'board_id': 'board-1',
      'board_items': const [
        {'name': 'Pink T-Shirt', 'role': 'top'},
        {'name': 'Dark Green Blazer', 'role': 'outerwear'},
      ],
      'changed_slots': const ['top'],
      'styling_note':
          'Pink T-Shirt complements Dark Green Blazer, keeping the Smart '
          'Casual direction polished and easy.',
    };

    test('fresh styling_note wins over stale why_it_works', () {
      final result = retainBoardNarrative([mutationBoard()], previousBoard);
      final merged = result.single;

      // 1 & 2: the fresh reasoning surfaces and the stale item name is gone.
      expect(merged['styling_note'], contains('Pink T-Shirt'));
      expect(merged['styling_note'], isNot(contains('Red Floral Kurta')));

      // 3: stale why_it_works must not be restored over the fresh styling_note.
      expect(merged.containsKey('why_it_works'), isFalse);

      // 4: styling_note must not also populate styling_tip.
      expect(merged['styling_tip'], previousBoard['styling_tip']);
      expect(merged['styling_tip'], isNot(contains('Pink T-Shirt')));
    });

    test(
      'genuine styling_tip still retains independently alongside fresh why',
      () {
        final board = mutationBoard();
        final result = retainBoardNarrative([board], previousBoard);
        // 5: previous styling_tip persists untouched since mutation sent none.
        expect(result.single['styling_tip'], previousBoard['styling_tip']);
      },
    );

    test('mutation with no fresh why/reasoning field keeps prior why intact', () {
      final result = retainBoardNarrative([
        {
          'board_id': 'board-1',
          'board_items': const [
            {'name': 'Pink T-Shirt', 'role': 'top'},
          ],
        },
      ], previousBoard);
      expect(result.single['why_it_works'], previousBoard['why_it_works']);
    });

    test('fresh explanation still counts as fresh WHY narrative', () {
      final result = retainBoardNarrative([
        {'board_id': 'board-1', 'explanation': 'Fresh explanation text'},
      ], previousBoard);
      expect(result.single['explanation'], 'Fresh explanation text');
      expect(result.single.containsKey('why_it_works'), isFalse);
    });

    test('fresh styling_tip still counts as Styling Tip', () {
      final result = retainBoardNarrative([
        {'board_id': 'board-1', 'styling_tip': 'Fresh tip text'},
      ], previousBoard);
      expect(result.single['styling_tip'], 'Fresh tip text');
      expect(result.single['why_it_works'], previousBoard['why_it_works']);
    });

    test('title retention is unchanged by the styling_note regrouping', () {
      final result = retainBoardNarrative([mutationBoard()], previousBoard);
      expect(result.single['title'], previousBoard['title']);
    });

    test('multi-board narrative isolation remains intact', () {
      final result = retainBoardNarrative([
        mutationBoard(),
        {'board_id': 'board-2'},
      ], previousBoard);
      expect(result[0]['styling_note'], contains('Pink T-Shirt'));
      expect(result[1].containsKey('styling_note'), isFalse);
      expect(result[1].containsKey('why_it_works'), isFalse);
    });
  });
}
