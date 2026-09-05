// Regression proof for STYLE BOARD P0: the first Style board rendered in a
// cold app session must show the complete outfit, not just whichever items
// happened to already have an image on the thin, per-message wardrobe map.
//
// AhviOutfitBoardCard builds one "effective" wardrobe map from two sources
// (its own widget.wardrobeById and AppwriteService.cachedWardrobeItems) via
// private helpers exposed here only for testing:
//   - mergeWardrobeRecordsForTesting: field-level merge of one record
//   - effectiveWardrobeMapForTesting: id-level merge of two wardrobe maps
//   - requiredWardrobeIdsForTesting: ids a direction's board_items reference
//
// These tests cover the data-level contract (the actual new logic); the
// resurrection / raw-image-safety / real-record behaviors that sit on top of
// it are already covered by style_board_normalized_url_fallback_test.dart and
// style_board_p0_target_items_real_data_test.dart and are not re-duplicated
// here.
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';

void main() {
  group('mergeWardrobeRecordsForTesting (field-level richness)', () {
    test('a field missing on the base record is filled from the other', () {
      final merged = mergeWardrobeRecordsForTesting(
        {'item_id': 'top-1', 'image_url': 'https://raw/top.png'},
        {
          'item_id': 'top-1',
          'image_url': 'https://raw/top.png',
          'masked_url': 'https://processed/top.png',
        },
      );
      expect(merged['masked_url'], 'https://processed/top.png');
    });

    test(
      'a richer record cannot be overwritten by a thinner one (F)',
      () {
        final rich = {
          'item_id': 'top-1',
          'image_url': 'https://raw/top.png',
          'masked_url': 'https://processed/top.png',
          'normalized_url': 'https://catalog/top.png',
        };
        final thin = {'item_id': 'top-1', 'image_url': 'https://raw/top.png'};

        // Regardless of which side is "base" vs "other", no populated field
        // from the richer record is ever cleared or blanked.
        final mergedRichBase = mergeWardrobeRecordsForTesting(rich, thin);
        final mergedThinBase = mergeWardrobeRecordsForTesting(thin, rich);
        expect(mergedRichBase['masked_url'], 'https://processed/top.png');
        expect(mergedRichBase['normalized_url'], 'https://catalog/top.png');
        expect(mergedThinBase['masked_url'], 'https://processed/top.png');
        expect(mergedThinBase['normalized_url'], 'https://catalog/top.png');
      },
    );

    test('a blank string field never wins over a populated one', () {
      final merged = mergeWardrobeRecordsForTesting(
        {'item_id': 'top-1', 'masked_url': 'https://processed/top.png'},
        {'item_id': 'top-1', 'masked_url': ''},
      );
      expect(merged['masked_url'], 'https://processed/top.png');
    });
  });

  group('effectiveWardrobeMapForTesting (id-level merge)', () {
    test(
      'A: cold empty widget map + fetched full wardrobe -> complete map',
      () {
        final effective = effectiveWardrobeMapForTesting(const {}, {
          'top-1': {'item_id': 'top-1', 'masked_url': 'https://p/top.png'},
          'bottom-1': {
            'item_id': 'bottom-1',
            'masked_url': 'https://p/bottom.png',
          },
          'shoe-1': {'item_id': 'shoe-1', 'masked_url': 'https://p/shoe.png'},
        });
        expect(effective.keys.toSet(), {'top-1', 'bottom-1', 'shoe-1'});
      },
    );

    test(
      'B: partial widget map (footwear only) + already-full cache -> '
      'complete map, footwear record not dropped',
      () {
        final widgetMap = {
          'shoe-1': {'item_id': 'shoe-1', 'masked_url': 'https://p/shoe.png'},
        };
        final cache = {
          'top-1': {'item_id': 'top-1', 'masked_url': 'https://p/top.png'},
          'bottom-1': {
            'item_id': 'bottom-1',
            'masked_url': 'https://p/bottom.png',
          },
          'shoe-1': {'item_id': 'shoe-1', 'masked_url': 'https://p/shoe.png'},
        };
        final effective = effectiveWardrobeMapForTesting(widgetMap, cache);
        expect(effective.keys.toSet(), {'top-1', 'bottom-1', 'shoe-1'});
        expect(effective['shoe-1']!['masked_url'], 'https://p/shoe.png');
      },
    );

    test(
      'regression: a richer local/cache map is not downgraded by merging in '
      'a partial incoming widget map (didUpdateWidget scenario)',
      () {
        final richLocalCache = {
          'top-1': {'item_id': 'top-1', 'masked_url': 'https://p/top.png'},
          'bottom-1': {
            'item_id': 'bottom-1',
            'masked_url': 'https://p/bottom.png',
          },
          'shoe-1': {'item_id': 'shoe-1', 'masked_url': 'https://p/shoe.png'},
        };
        final incomingPartialWidgetMap = {
          'shoe-1': {'item_id': 'shoe-1', 'masked_url': 'https://p/shoe.png'},
        };
        final effective = effectiveWardrobeMapForTesting(
          richLocalCache,
          incomingPartialWidgetMap,
        );
        expect(effective.keys.toSet(), {'top-1', 'bottom-1', 'shoe-1'});
      },
    );
  });

  group('requiredWardrobeIdsForTesting', () {
    test('extracts stable ids referenced by board_items', () {
      final direction = {
        'title': 'Lunch',
        'board_items': [
          {'item_id': 'top-1', 'role': 'top'},
          {'item_id': 'bottom-1', 'role': 'bottom'},
        ],
      };
      expect(
        requiredWardrobeIdsForTesting(direction),
        {'top-1', 'bottom-1'},
      );
    });
  });

  test(
    'D: Style This -- partial initial map (anchor only) merged with a full '
    'cache renders all 3 items, with exactly 1 (the anchor) locked',
    () {
      const shirtId = 'shirt-1';
      const trousersId = 'trousers-1';
      const sneakersId = 'sneakers-1';
      final direction = {
        'title': 'Style This',
        'scenario': 'style_this',
        'originating_item_id': shirtId,
        'board_items': [
          {
            'item_id': shirtId,
            'name': 'White Printed Shirt',
            'role': 'top',
            'source': 'wardrobe',
            'image_url': 'https://raw/shirt.png',
          },
          {
            'item_id': trousersId,
            'name': 'Navy Blue Trousers',
            'role': 'bottom',
            'source': 'wardrobe',
            'image_url': 'https://raw/trousers.png',
          },
          {
            'item_id': sneakersId,
            'name': 'Sneakers',
            'role': 'footwear',
            'source': 'wardrobe',
            'image_url': 'https://raw/sneakers.png',
          },
        ],
      };
      // Initial map carries only the anchor -- mirrors the ticket's example
      // of a board rendered before the cache fully warmed.
      final initialMap = {
        shirtId: {
          'item_id': shirtId,
          'image_url': 'https://raw/shirt.png',
          'masked_url': 'https://processed/shirt.png',
        },
      };
      final fullCache = {
        shirtId: initialMap[shirtId]!,
        trousersId: {
          'item_id': trousersId,
          'image_url': 'https://raw/trousers.png',
          'masked_url': 'https://processed/trousers.png',
        },
        sneakersId: {
          'item_id': sneakersId,
          'image_url': 'https://raw/sneakers.png',
          'masked_url': 'https://processed/sneakers.png',
        },
      };
      final effective = effectiveWardrobeMapForTesting(initialMap, fullCache);

      final model = OutfitBoardModel.fromPayload(direction, editorialCover: const {});
      final board = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: effective,
      );

      expect(board.items, hasLength(3));
      expect(
        board.items.map((i) => i.role.name).toSet(),
        {'top', 'bottom', 'footwear'},
      );
    },
  );
}
