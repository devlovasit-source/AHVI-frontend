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
}
