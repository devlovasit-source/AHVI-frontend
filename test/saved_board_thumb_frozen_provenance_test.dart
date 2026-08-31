import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/saved_board_thumb.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

const _frozenUrl = 'https://example.test/frozen-catalog-fallback.png';
const _liveChangedMaskedUrl = 'https://example.test/live-changed-masked.png';

void main() {
  // Regression for the saved-board thumbnail grid resolving a frozen item's
  // image against the item's *current* live wardrobeById data instead of
  // its own saved provenance -- a later wardrobe edit/reprocess could
  // silently change what an already-saved board's thumbnail shows. Mirrors
  // the equivalent fix already covered for SavedBoardCard._itemsForBoard in
  // saved_board_persistence_test.dart's reopen-parity coverage.
  testWidgets(
    'SavedBoardThumb renders frozen image provenance, not the live wardrobe override',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            extensions: [AppThemeTokens.light(_accent)],
          ),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: SavedBoardThumb(
                source: {
                  'title': 'Frozen Provenance Test',
                  'occasion': 'Work',
                  'items': [
                    {
                      // At save time no cutout existed for this item, so it
                      // was frozen as a plain catalog_fallback (tier 3).
                      'item_id': 'item-under-test',
                      'name': 'Shirt',
                      'role': 'top',
                      'image_url': _frozenUrl,
                      'selected_field': 'normalized_url',
                      'source_kind': 'catalog_fallback',
                      'expected_transparent': false,
                    },
                    {
                      'item_id': 'bottom-1',
                      'name': 'Trousers',
                      'role': 'bottom',
                      'normalized_url': 'https://example.test/catalog_bottom.png',
                    },
                  ],
                },
                // The wardrobe item has since been reprocessed and now has
                // a masked cutout (tier 1) it didn't have at save time. A
                // frozen board must not pick this up.
                wardrobeById: {
                  'item-under-test': {
                    'item_id': 'item-under-test',
                    'masked_url': _liveChangedMaskedUrl,
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final grid = tester.widget<AhviUnifiedOutfitGrid>(
        find.byType(AhviUnifiedOutfitGrid),
      );
      final item = grid.items.firstWhere((i) => i.id == 'item-under-test');

      expect(item.resolvedImageUrl, _frozenUrl);
      expect(item.sourceKind, 'catalog_fallback');
      expect(item.resolvedImageUrl, isNot(_liveChangedMaskedUrl));
      expect(tester.takeException(), isNull);
    },
  );
}
