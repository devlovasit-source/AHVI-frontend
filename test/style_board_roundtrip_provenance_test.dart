// Regression: a rendered board must survive being re-parsed from its own
// published payload.
//
// _toStyleBoardData rewrites image_url to the SELECTED processed asset and
// preserves the true upload in original_image_url:
//     ..['image_url'] = selectedImage
//     if (originalImage != selectedImage) 'original_image_url': originalImage
// That payload is republished through _currentDirection -> board_items and
// re-parsed on the next rebuild. On that second pass image_url IS the mask,
// so any safety check treating image_url as provenance concludes the mask is
// a fabricated alias of the raw upload and drops the item.
//
// Observed on a physical Samsung SM-S928B, same item 12ms apart:
//   09:26:24.517 masked=d732a2ce normalized=none     image_url=2ccfe546 -> masked_url OK
//   09:26:24.529 masked=d732a2ce normalized=none     image_url=d732a2ce -> none/missing
//   board renders 3 (top,bottom,footwear) then collapses to 1 (bottom)
//
// The frozen-candidate path already solves this with isFrozenOriginalAlias,
// which reads original_image_url/raw_url/preview_url and deliberately NOT
// image_url. Raw-image safety is unchanged: a mask aliasing the genuine
// upload is still rejected, because the upload is still in original_image_url.
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

const _r2 = 'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev';

// Real records from the live `outfits` collection (user 69e6096616923db26940).
const _shirt = {
  'item_id': '6288c40c-a15c-4ac4-a127-4509e6bd24a4',
  'name': 'Black Long Sleeve Shirt',
  'category': 'Tops',
  'image_url': '$_r2/catalog_6288c40c-a15c-4ac4-a127-4509e6bd24a4.png',
  'normalized_url':
      '$_r2/wardrobe_6288c40c-a15c-4ac4-a127-4509e6bd24a4_style_this_v1.png',
  'masked_url':
      '$_r2/wardrobe_6288c40c-a15c-4ac4-a127-4509e6bd24a4_style_this_v1.png',
};
const _jeans = {
  'item_id': '9e45b2c2-ede4-49bc-8087-e99b8d79cb35',
  'name': 'Light Blue Jeans',
  'category': 'Bottoms',
  'image_url': '$_r2/catalog_9e45b2c2-ede4-49bc-8087-e99b8d79cb35.png',
  'normalized_url':
      '$_r2/wardrobe_9e45b2c2-ede4-49bc-8087-e99b8d79cb35_style_this_v1.png',
  'masked_url':
      '$_r2/wardrobe_9e45b2c2-ede4-49bc-8087-e99b8d79cb35_style_this_v1.png',
};
const _sneakers = {
  'item_id': 'e394ecf3-a1be-4db4-a58d-f96275771270',
  'name': 'White Skechers Sneakers',
  'category': 'Footwear',
  'image_url':
      'https://pub-9ca6234baa424e56882e953c97ffbe14.r2.dev/raw_e394ecf3-a1be-4db4-a58d-f96275771270.png',
  'normalized_url': '$_r2/catalog_e394ecf3-a1be-4db4-a58d-f96275771270.png',
  'masked_url': '$_r2/wardrobe_e394ecf3-a1be-4db4-a58d-f96275771270.png',
};

Map<String, dynamic> _boardItem(Map<String, dynamic> r, String role) => {
  'item_id': r['item_id'],
  'name': r['name'],
  'role': role,
  'source': 'wardrobe',
  'image_url': r['image_url'],
};

Map<String, Map<String, dynamic>> get _wardrobe => {
  _shirt['item_id'] as String: Map<String, dynamic>.from(_shirt),
  _jeans['item_id'] as String: Map<String, dynamic>.from(_jeans),
  _sneakers['item_id'] as String: Map<String, dynamic>.from(_sneakers),
};

Map<String, dynamic> _direction() => {
  'title': 'Style This',
  'scenario': 'style_this',
  'source_policy': 'wardrobe',
  'board_items': [
    _boardItem(_shirt, 'top'),
    _boardItem(_jeans, 'bottom'),
    _boardItem(_sneakers, 'footwear'),
  ],
};

int _renderCount(Map<String, dynamic> direction) {
  final model = OutfitBoardModel.fromPayload(
    direction,
    editorialCover: const {},
  );
  return styleBoardDataFromOutfitBoardForTesting(
    model,
    direction,
    wardrobeById: _wardrobe,
  ).items.length;
}

void main() {
  test('first parse renders all three garments', () {
    expect(_renderCount(_direction()), 3);
  });

  test(
    're-parsing the board from its own published payload still renders three '
    '(image_url now holds the selected asset, not the upload)',
    () {
      final direction = _direction();
      final model = OutfitBoardModel.fromPayload(
        direction,
        editorialCover: const {},
      );
      final first = styleBoardDataFromOutfitBoardForTesting(
        model,
        direction,
        wardrobeById: _wardrobe,
      );
      expect(first.items, hasLength(3));

      // Exactly what _currentDirection republishes to board_items.
      final republished = {
        ...direction,
        'board_items': first.items
            .map((i) => i.toContractJson())
            .toList(growable: false),
      };

      expect(
        _renderCount(republished),
        3,
        reason:
            'a board that rendered must not lose items when rebuilt from its '
            'own payload -- this is the 3 -> 1 collapse seen on device',
      );
    },
  );

  test(
    'frozen snapshot whose mask IS the upload stays rejected -- the '
    'image_url exemption must not become a way onto the board',
    () {
      // Regression for a hole introduced while fixing the round trip: once
      // image_url stopped vetoing the mask on frozen snapshots, a payload
      // whose mask genuinely aliases the upload briefly resolved to the raw
      // photo. original_image_url / raw_url remain authoritative.
      final resolved = resolveWardrobeImage(
        const {
          'item_id': 'unsafe-frozen',
          'source': 'wardrobe',
          'image_url': 'https://test/raw/selfie.png',
          'masked_url': 'https://test/raw/selfie.png',
          'original_image_url': 'https://test/raw/selfie.png',
          'selected_field': 'image_url',
          'source_kind': 'original',
        },
        surface: 'style_board_live',
        itemId: 'unsafe-frozen',
      );
      expect(resolved.url, isNull);
      expect(resolved.sourceKind, 'missing');
    },
  );

  test(
    'a mask that aliases the GENUINE upload is still rejected on a board '
    'surface (raw-image safety must not be weakened by the fix)',
    () {
      final resolved = resolveWardrobeImage(
        const {
          'item_id': 'unsafe-1',
          'source': 'wardrobe',
          // Frozen-snapshot shape: image_url is the selected asset and the
          // real upload is preserved in original_image_url -- and here the
          // "mask" is that very upload.
          'image_url': 'https://test/raw/selfie.png',
          'original_image_url': 'https://test/raw/selfie.png',
          'masked_url': 'https://test/raw/selfie.png?sig=abc',
          'selected_field': 'masked_url',
          'source_kind': 'legacy_masked_cutout',
          'expected_transparent': true,
        },
        surface: 'style_board_live',
        itemId: 'unsafe-1',
      );
      expect(resolved.url, isNot('https://test/raw/selfie.png'));
      expect(resolved.url, isNot('https://test/raw/selfie.png?sig=abc'));
    },
  );
}
