// Regression proof for STYLE BOARD P0: confirms, against the *real* Appwrite
// records captured for the two named target items (Black Long Sleeve Shirt,
// Light Blue Jeans), that they resolve to a board-ready image through the
// actual (unmodified) resolver -- not a re-implementation of its logic.
//
// Do NOT weaken resolveWardrobeImage()/_toStyleBoardData() to make this pass.
// If this test ever needs the resolver relaxed to go green, the resolver is
// not the problem -- the wardrobe record's processed asset is.
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';

// Captured verbatim from the live `outfits` collection (user
// 69e6096616923db26940) via the Appwrite REST API on 2026-09-05. Only fields
// the resolver reads are kept.
const _blackLongSleeveShirt = {
  r'$id': '6288c40c-a15c-4ac4-a127-4509e6bd24a4',
  'name': 'Black Long Sleeve Shirt',
  'category': 'Tops',
  'image_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/catalog_6288c40c-a15c-4ac4-a127-4509e6bd24a4.png',
  'normalized_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/wardrobe_6288c40c-a15c-4ac4-a127-4509e6bd24a4_style_this_v1.png',
  'masked_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/wardrobe_6288c40c-a15c-4ac4-a127-4509e6bd24a4_style_this_v1.png',
};

const _lightBlueJeans = {
  r'$id': '9e45b2c2-ede4-49bc-8087-e99b8d79cb35',
  'name': 'Light Blue Jeans',
  'category': 'Bottoms',
  'image_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/catalog_9e45b2c2-ede4-49bc-8087-e99b8d79cb35.png',
  'normalized_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/wardrobe_9e45b2c2-ede4-49bc-8087-e99b8d79cb35_style_this_v1.png',
  'masked_url':
      'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/wardrobe_9e45b2c2-ede4-49bc-8087-e99b8d79cb35_style_this_v1.png',
};

Map<String, dynamic> _thinBoardItem(Map<String, dynamic> record, String role) => {
  'item_id': record[r'$id'],
  'name': record['name'],
  'role': role,
  'source': 'wardrobe',
  // Mirrors what the backend's board_items payload carries for a wardrobe
  // item: identity + the raw upload only, no processed fields -- the
  // frontend is expected to hydrate those from the wardrobe cache.
  'image_url': record['image_url'],
};

void main() {
  test(
    'Black Long Sleeve Shirt (real wardrobe record) resolves board-ready, '
    'processed asset distinct from raw',
    () {
      final direction = {
        'title': 'Lunch',
        'board_items': [_thinBoardItem(_blackLongSleeveShirt, 'top')],
      };
      final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: {_blackLongSleeveShirt[r'$id'] as String: _blackLongSleeveShirt},
      );

      expect(board.items, hasLength(1));
      final item = board.items.single;
      expect(item.displayImageUrl, isNotEmpty);
      expect(item.displayImageUrl, isNot(_blackLongSleeveShirt['image_url']));
    },
  );

  test(
    'Light Blue Jeans (real wardrobe record) resolves board-ready, '
    'processed asset distinct from raw',
    () {
      final direction = {
        'title': 'Lunch',
        'board_items': [_thinBoardItem(_lightBlueJeans, 'bottom')],
      };
      final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: {_lightBlueJeans[r'$id'] as String: _lightBlueJeans},
      );

      expect(board.items, hasLength(1));
      final item = board.items.single;
      expect(item.displayImageUrl, isNotEmpty);
      expect(item.displayImageUrl, isNot(_lightBlueJeans['image_url']));
    },
  );

  test(
    'both target items together render a complete TOP+BOTTOM board when the '
    'wardrobe cache is populated (the exact scenario the P0 ticket names)',
    () {
      final direction = {
        'title': 'Lunch',
        'board_items': [
          _thinBoardItem(_blackLongSleeveShirt, 'top'),
          _thinBoardItem(_lightBlueJeans, 'bottom'),
        ],
      };
      final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: {
          _blackLongSleeveShirt[r'$id'] as String: _blackLongSleeveShirt,
          _lightBlueJeans[r'$id'] as String: _lightBlueJeans,
        },
      );

      expect(
        board.items.map((i) => i.role.name).toSet(),
        {'top', 'bottom'},
      );
    },
  );

  test(
    'without the wardrobe cache (cold-cache scenario), the same real items '
    'are dropped -- proves the gap is cache population, not the resolver',
    () {
      final direction = {
        'title': 'Lunch',
        'board_items': [
          _thinBoardItem(_blackLongSleeveShirt, 'top'),
          _thinBoardItem(_lightBlueJeans, 'bottom'),
        ],
      };
      final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: const {},
      );

      expect(board.items, isEmpty);
    },
  );
}
