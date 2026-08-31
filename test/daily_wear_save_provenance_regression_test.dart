import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_renderer.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

const _rawImageUrl = 'https://storage.test/files/e394ecf3-b5ccbbf1.jpg';
const _badMaskedUrl =
    'https://storage.test/files/e394ecf3-b5ccbbf1.jpg?variant=651a8e3e';
const _cleanNormalizedUrl =
    'https://storage.test/files/catalog_e394ecf3-5d8f8133.jpg';

void main() {
  test('Daily Wear save preserves the three-distinct-URL live selection', () {
    final liveItem = StyleBoardItem(
      id: 'e394ecf3-a1be-4db4-a58d-f96275771270',
      role: BoardItemRole.footwear,
      source: 'wardrobe',
      name: 'White Skechers Sneakers',
      imageUrl: _rawImageUrl,
      maskedUrl: _badMaskedUrl,
      normalizedUrl: _cleanNormalizedUrl,
      category: 'footwear',
      raw: {
        'item_id': 'e394ecf3-a1be-4db4-a58d-f96275771270',
        'role': 'footwear',
        'source': 'wardrobe',
        'name': 'White Skechers Sneakers',
        'masked_url': _badMaskedUrl,
        'normalized_url': _cleanNormalizedUrl,
      },
    );
    final live = liveItem.resolveImage(surface: 'style_board');
    expect(live.field, 'normalized_url');
    expect(live.sourceKind, 'catalog_fallback');
    expect(live.url, _cleanNormalizedUrl);
    expect({_rawImageUrl, _badMaskedUrl, _cleanNormalizedUrl}, hasLength(3));

    final saveItems = buildDailyWearSaveItems(
      StyleBoardData(title: 'Daily Wear', items: [liveItem]),
    );
    expect(
      saveItems.single[savedBoardAuthoritativeImageKey],
      isA<ResolvedWardrobeImage>(),
    );
    final handedOff =
        saveItems.single[savedBoardAuthoritativeImageKey]
            as ResolvedWardrobeImage;
    expect(handedOff.url, _cleanNormalizedUrl);
    expect(handedOff.field, 'normalized_url');
    expect(handedOff.sourceKind, 'catalog_fallback');
    final content = buildSavedBoardContent(
      board: const {
        'board_id': 'daily-board-e394',
        'revision': 1,
        'source_policy': 'wardrobe',
      },
      items: saveItems,
      selection: const SavedBoardSelection(bucket: 'everything_else'),
      title: 'Daily Wear',
      originalOccasion: 'daily',
    );
    final compact =
        (jsonDecode(content.outfitItems) as List).single
            as Map<String, dynamic>;

    expect(compact['image_url'], _cleanNormalizedUrl);
    expect(compact['selected_field'], 'normalized_url');
    expect(compact['source_kind'], 'catalog_fallback');
    expect(compact['image_url'], isNot(_badMaskedUrl));

    final payload = buildSavedBoardPayload(
      userId: 'user-1',
      imageUrl: _cleanNormalizedUrl,
      content: content,
    );
    final reopened = expandSavedBoardData(payload);
    final reopenedItem = (reopened['items'] as List).single as Map;
    final rendered = boardDataFromMap(reopened).items.single;
    expect(reopenedItem['image_url'], _cleanNormalizedUrl);
    expect(reopenedItem['selected_field'], 'normalized_url');
    expect(reopenedItem['source_kind'], 'catalog_fallback');
    expect(
      rendered.resolveImage(surface: 'style_board_saved').url,
      _cleanNormalizedUrl,
    );
  });

  test('raw unresolved save callers still use persistence resolution', () {
    final content = buildSavedBoardContent(
      board: const {'board_id': 'raw-board', 'revision': 1},
      items: const [
        {
          'item_id': 'raw-item',
          'role': 'top',
          'source': 'wardrobe',
          'normalized_url': 'https://storage.test/files/catalog_raw.png',
        },
      ],
      selection: const SavedBoardSelection(bucket: 'everything_else'),
      title: 'Raw caller',
      originalOccasion: 'daily',
    );
    final compact =
        (jsonDecode(content.outfitItems) as List).single
            as Map<String, dynamic>;
    expect(compact['image_url'], 'https://storage.test/files/catalog_raw.png');
    expect(compact['selected_field'], 'normalized_url');
    expect(compact['source_kind'], 'catalog_fallback');
  });

  test('inconsistent authoritative provenance is rejected', () {
    final raw = <String, dynamic>{
      'item_id': 'inconsistent-item',
      'role': 'top',
      'normalized_url': _cleanNormalizedUrl,
      savedBoardAuthoritativeImageKey: const ResolvedWardrobeImage(
        url: _cleanNormalizedUrl,
        field: 'normalized_url',
        sourceKind: 'validated_cutout',
        tier: 0,
        expectedTransparent: true,
        validated: true,
        shouldFrame: false,
      ),
    };
    final content = buildSavedBoardContent(
      board: const {'board_id': 'inconsistent-board'},
      items: [raw],
      selection: const SavedBoardSelection(bucket: 'everything_else'),
      title: 'Consistency check',
      originalOccasion: 'daily',
    );
    final compact =
        (jsonDecode(content.outfitItems) as List).single
            as Map<String, dynamic>;
    expect(compact['image_url'], _cleanNormalizedUrl);
    expect(compact['selected_field'], 'normalized_url');
    expect(compact['source_kind'], 'catalog_fallback');
    expect(compact['expected_transparent'], isFalse);
  });
}
