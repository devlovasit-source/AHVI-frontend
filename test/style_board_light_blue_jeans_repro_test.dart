// Regression: an empty-string normalizedUrl/maskedUrl parameter must not
// blank out the real URL sitting further down the fallback chain.
//
// resolveWardrobeImage built its candidates with `_clean(maskedUrl ??
// raw['masked_url'])`. `??` only short-circuits on null, so the EMPTY STRING
// that StyleBoardItem uses as the default for maskedUrl/normalizedUrl (when
// the board payload omits those fields) won the chain and `_clean('')`
// collapsed it to null -- the genuine masked_url in `raw` was never read.
// The item then produced ZERO board-safe candidates and was silently dropped
// from the rendered board.
//
// Captured from a physical Samsung SM-S928B on 2026-09-06: "Light Blue Jeans"
// (9e45b2c2) logged, on surface=style_board_live,
//   masked_url_fp=a23944b0 normalized_url_fp=none image_url_fp=cd2defc4
//   selected_field=none source_kind=missing candidate_count=0 rejected_unsafe=1
// while the very same record resolved fine on surface=wardrobe_grid. Test D
// below reproduces that exact signature; A/B/C are the shapes that always
// worked and must keep working.
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

const _masked =
    'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/wardrobe_9e45b2c2-ede4-49bc-8087-e99b8d79cb35_style_this_v1.png';
const _raw =
    'https://pub-d4d02883ddda4a1bba452bfe6d1be814.r2.dev/catalog_9e45b2c2-ede4-49bc-8087-e99b8d79cb35.png';

void main() {
  test('full wardrobe record (masked + normalized) resolves board-ready', () {
    final r = resolveWardrobeImage(
      const {'item_id': '9e45b2c2', 'source': 'wardrobe'},
      surface: 'style_board_live',
      itemId: '9e45b2c2',
      wardrobeRecord: const {
        'item_id': '9e45b2c2',
        'image_url': _raw,
        'masked_url': _masked,
        'normalized_url': _masked,
      },
    );
    expect(r.url, _masked);
    expect(r.sourceKind, isNot('missing'));
  });

  test('wardrobe record with masked_url but no normalized_url resolves', () {
    final r = resolveWardrobeImage(
      const {'item_id': '9e45b2c2', 'source': 'wardrobe'},
      surface: 'style_board_live',
      itemId: '9e45b2c2',
      wardrobeRecord: const {
        'item_id': '9e45b2c2',
        'image_url': _raw,
        'masked_url': _masked,
      },
    );
    expect(r.url, _masked);
    expect(r.sourceKind, isNot('missing'));
  });

  test(
    'empty-string maskedUrl/normalizedUrl params must not hide the real '
    'masked_url in raw (the physical-device drop signature)',
    () {
      final r = resolveWardrobeImage(
        const {
          'item_id': '9e45b2c2',
          'source': 'wardrobe',
          'image_url': _raw,
          'masked_url': _masked,
        },
        // Exactly what _toStyleBoardData forwards from a StyleBoardItem whose
        // board payload carried neither field: '' rather than null.
        normalizedUrl: '',
        maskedUrl: '',
        surface: 'style_board_live',
        itemId: '9e45b2c2',
      );
      expect(
        r.url,
        _masked,
        reason: 'empty-string params must fall through to raw["masked_url"]',
      );
      expect(r.sourceKind, isNot('missing'));
      expect(r.field, isNot('none'));
    },
  );

  test('raw-image safety still holds when the params are empty strings', () {
    // masked_url aliases the raw upload -> must still be rejected on a board
    // surface. The empty-string fix must not widen what gets displayed.
    final r = resolveWardrobeImage(
      const {
        'item_id': 'unsafe-1',
        'source': 'wardrobe',
        'image_url': 'https://test/raw/selfie.png',
        'masked_url': 'https://test/raw/selfie.png?sig=abc',
      },
      normalizedUrl: '',
      maskedUrl: '',
      surface: 'style_board_live',
      itemId: 'unsafe-1',
    );
    expect(r.url, isNot('https://test/raw/selfie.png?sig=abc'));
    expect(r.url, isNot('https://test/raw/selfie.png'));
  });
}
