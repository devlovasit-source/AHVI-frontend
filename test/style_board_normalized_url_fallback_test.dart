import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

Map<String, dynamic> _direction({String? boardItemNormalizedUrl}) => {
  'title': 'Weekend Edit',
  'board_items': [
    {
      'item_id': 'top-1',
      'name': 'White shirt',
      'role': 'top',
      'source': 'wardrobe',
      'image_url': 'https://test/raw/top.png',
      if (boardItemNormalizedUrl != null)
        'normalized_url': boardItemNormalizedUrl,
    },
  ],
};

StyleBoardItem _boardItemFor(Map<String, dynamic> direction, {
  required Map<String, Map<String, dynamic>> wardrobeById,
}) {
  final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
  final board = styleBoardDataFromOutfitBoardForTesting(
    model,
    direction,
    wardrobeById: wardrobeById,
  );
  return board.items.singleWhere((item) => item.id == 'top-1');
}

void main() {
  test(
    'board_items missing normalized_url falls back to the wardrobe record',
    () {
      final direction = _direction();
      final wardrobeById = {
        'top-1': {
          'item_id': 'top-1',
          'image_url': 'https://test/raw/top.png',
          'normalized_url': 'https://test/catalog/top-processed.png',
        },
      };
      final item = _boardItemFor(direction, wardrobeById: wardrobeById);

      expect(item.normalizedUrl, 'https://test/catalog/top-processed.png');
      expect(
        item.toContractJson()['normalized_url'],
        'https://test/catalog/top-processed.png',
      );
    },
  );

  test(
    'raw-aliased wardrobe normalized_url is rejected by the board-safe '
    'resolver (the field-level fallback does not weaken this check)',
    () {
      // Same object as image_url, only the query string differs -- a
      // signed-URL alias of the raw upload, not a real processed asset.
      final wardrobeRecord = {
        'item_id': 'top-1',
        'image_url': 'https://test/raw/top.png',
        'normalized_url': 'https://test/raw/top.png?sig=abc123',
      };
      final resolved = resolveWardrobeImage(
        const {'item_id': 'top-1', 'source': 'wardrobe'},
        surface: 'style_board_live',
        itemId: 'top-1',
        wardrobeRecord: wardrobeRecord,
      );

      expect(resolved.url, isNot('https://test/raw/top.png?sig=abc123'));

      // Whole-item pipeline: with no other safe candidate, the item is
      // dropped from the rendered board entirely rather than showing the
      // raw alias -- the field-level normalizedUrl fallback never widens
      // what gets displayed.
      final direction = _direction();
      final model = OutfitBoardModel.fromPayload(
        direction,
        editorialCover: const {},
      );
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: {'top-1': wardrobeRecord},
      );
      expect(board.items.where((item) => item.id == 'top-1'), isEmpty);
    },
  );

  test('board_items normalized_url wins over the wardrobe record when present', () {
    final direction = _direction(
      boardItemNormalizedUrl: 'https://test/catalog/board-value.png',
    );
    final wardrobeById = {
      'top-1': {
        'item_id': 'top-1',
        'image_url': 'https://test/raw/top.png',
        'normalized_url': 'https://test/catalog/wardrobe-value.png',
      },
    };
    final item = _boardItemFor(direction, wardrobeById: wardrobeById);

    expect(item.normalizedUrl, 'https://test/catalog/board-value.png');
  });
}
