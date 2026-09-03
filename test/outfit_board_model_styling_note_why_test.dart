import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/services/style_mutation_contract.dart';

void main() {
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

  test(
    'fresh styling_note reaches OutfitBoardModel.intelligenceText (WHY IT WORKS)',
    () {
      final retained = retainBoardNarrative([mutationBoard()], previousBoard);
      final model = OutfitBoardModel.fromPayload(
        retained.single,
        editorialCover: const {},
      );

      expect(model.intelligenceText, contains('Pink T-Shirt'));
      expect(model.intelligenceText, isNot(contains('Red Floral Kurta')));
      // styling_note must not also render as the Styling Tip row.
      expect(model.stylingTip, isNot(contains('Pink T-Shirt')));
    },
  );
}
