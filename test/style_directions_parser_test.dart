// Parser tests for the Style This `style_directions` → canonical
// visualDirections adaptation (P0: backend ships style_directions, the parser
// must produce a visualDirections block).
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';

// Mirrors the real backend item shape (item0_keys observed on device).
Map<String, dynamic> _item(String id, String role) => {
  'item_id': id,
  'name': id,
  'category': role,
  'role': role,
  'image_url': 'https://example.test/$id.png',
  'owned': true,
};

// Real backend style_directions entry: {title, items, missing_items,
// styling_note} — NO board_id/revision/board_items/positions.
Map<String, dynamic> _styleThisResponse({
  Map<String, dynamic>? anchor,
  List<Map<String, dynamic>>? directions,
}) => {
  'success': true,
  'route': 'style_this',
  'mode': 'style_this',
  'anchor_item':
      anchor ??
      {
        'item_id': 'anchor-1',
        'name': 'Pink Shirt',
        'category': 'top',
        'image_url': 'https://example.test/anchor-1.png',
      },
  'style_directions':
      directions ??
      [
        {
          'title': 'Sharp Layers',
          'styling_note': 'Balances the anchor',
          'missing_items': const [],
          'items': [
            _item('anchor-1', 'top'),
            _item('bottom-7', 'bottom'),
            _item('shoe-9', 'footwear'),
          ],
        },
      ],
  'context_usage': {'context_version': 'v2'},
};

List<Map<String, dynamic>> _directionsOf(AhviParsedResponse parsed) {
  final block = parsed.blocks.firstWhere(
    (b) => b.type == AhviBlockType.visualDirections,
    orElse: () => AhviResponseBlock(
      type: AhviBlockType.visualDirections,
      data: const {'directions': <Map<String, dynamic>>[]},
    ),
  );
  final raw = block.data['directions'];
  return raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];
}

bool _hasVisualDirections(AhviParsedResponse parsed) =>
    parsed.blocks.any((b) => b.type == AhviBlockType.visualDirections);

void main() {
  test('top-level style_directions produces a visualDirections block', () {
    final parsed = parseAhviResponse(_styleThisResponse());
    expect(_hasVisualDirections(parsed), isTrue);
    expect(_directionsOf(parsed), hasLength(1));
  });

  test('mapped direction carries the Style This contract fields', () {
    final dir = _directionsOf(parseAhviResponse(_styleThisResponse())).single;
    expect(dir['scenario'], 'style_this');
    expect(dir['interaction_mode'], 'style_this');
    expect(dir['source_policy'], 'wardrobe');
  });

  test('anchor id is carried onto the direction for lock + verification', () {
    final dir = _directionsOf(parseAhviResponse(_styleThisResponse())).single;
    expect(dir['anchor_item_id'], 'anchor-1');
    expect(dir['originating_item_id'], 'anchor-1');
  });

  test(
    'synthesizes contract fields the backend omits (board_id, revision)',
    () {
      final dir = _directionsOf(parseAhviResponse(_styleThisResponse())).single;
      // board_id stable + not a forbidden outfit_card_* id.
      expect((dir['board_id'] as String).startsWith('style_this_'), isTrue);
      expect((dir['board_id'] as String).startsWith('outfit_card_'), isFalse);
      expect(dir['revision'], 1);
      expect(dir['title'], 'Sharp Layers');
      // styling_note → why_it_works (board card reads whyItWorks).
      expect(dir['why_it_works'], 'Balances the anchor');
    },
  );

  test('maps items → board_items and keeps the anchor present', () {
    final dir = _directionsOf(parseAhviResponse(_styleThisResponse())).single;
    final items = (dir['board_items'] as List).cast<Map>();
    expect(items, hasLength(3));
    expect(items.map((e) => e['item_id']), contains('anchor-1'));
  });

  test('rejects a direction when its board omits the anchor', () {
    final resp = _styleThisResponse(
      directions: [
        {
          'title': 'Support Only',
          'styling_note': 'note',
          'items': [_item('bottom-7', 'bottom'), _item('shoe-9', 'footwear')],
        },
      ],
    );
    expect(_hasVisualDirections(parseAhviResponse(resp)), isFalse);
  });

  test('keeps exactly one anchor when a direction repeats its id', () {
    final resp = _styleThisResponse(
      directions: [
        {
          'title': 'Duplicate anchor',
          'items': [
            _item('anchor-1', 'top'),
            _item('anchor-1', 'top'),
            _item('shoe-9', 'footwear'),
          ],
        },
      ],
    );
    final dir = _directionsOf(parseAhviResponse(resp)).single;
    final ids = (dir['board_items'] as List)
        .map((e) => (e as Map)['item_id'])
        .toList();
    expect(ids.where((id) => id == 'anchor-1'), hasLength(1));
  });

  test(
    'existing visual_directions parsing is unchanged (no style_this stamp)',
    () {
      final response = {
        'success': true,
        'route': 'visual_inspiration',
        'visual_directions': [
          {
            'board_id': 'rec-board-1',
            'revision': 2,
            'interaction_mode': 'recommendation',
            'title': 'Weekend Ease',
            'board_items': [_item('a', 'top')],
          },
        ],
      };
      final dir = _directionsOf(parseAhviResponse(response)).single;
      // Must NOT be forced to style_this — the recommendation path is untouched.
      expect(dir['interaction_mode'], 'recommendation');
      expect(dir.containsKey('scenario'), isFalse);
      expect(dir['board_id'], 'rec-board-1');
    },
  );

  test(
    'direction-level style_asset / mixed policy survives (not forced wardrobe)',
    () {
      for (final policy in ['style_asset', 'mixed']) {
        final resp = _styleThisResponse(
          directions: [
            {
              'title': 'P',
              'source_policy': policy,
              'items': [_item('anchor-1', 'top'), _item('b', 'bottom')],
            },
          ],
        );
        final dir = _directionsOf(parseAhviResponse(resp)).single;
        expect(dir['source_policy'], policy);
      }
    },
  );

  test('direction-level policy beats response-level policy', () {
    final resp = _styleThisResponse(
      directions: [
        {
          'title': 'P',
          'source_policy': 'style_asset',
          'items': [_item('anchor-1', 'top')],
        },
      ],
    )..['source_policy'] = 'wardrobe';
    final dir = _directionsOf(parseAhviResponse(resp)).single;
    expect(dir['source_policy'], 'style_asset');
  });

  test('response-level policy used when the direction omits it', () {
    final resp = _styleThisResponse(
      directions: [
        {
          'title': 'P',
          'items': [_item('anchor-1', 'top')],
        },
      ],
    )..['source_policy'] = 'mixed';
    final dir = _directionsOf(parseAhviResponse(resp)).single;
    expect(dir['source_policy'], 'mixed');
  });

  test('style board conversion keeps the direct image_url alias first', () {
    final resp = _styleThisResponse(
      directions: const [],
    )..['style_boards'] = [
        {
          'board_id': 'wardrobe-1',
          'title': 'Wardrobe Set',
          'items': [
            {
              'item_id': 'anchor-1',
              'name': 'Pink Shirt',
              'role': 'top',
              'image_url': 'https://example.test/direct.png',
              'safe_image_url': 'https://example.test/safe.png',
              'resolved_image_url': 'https://example.test/resolved.png',
              'board_image_url': 'https://example.test/board.png',
            },
          ],
        },
      ];
    final dir = _directionsOf(parseAhviResponse(resp)).single;
    final item = (dir['board_items'] as List).cast<Map>().single;
    expect(item['image_url'], 'https://example.test/direct.png');
    expect(item['board_image_url'], 'https://example.test/board.png');
  });

  test('wardrobe fallback only when neither level has a valid policy', () {
    final dir = _directionsOf(parseAhviResponse(_styleThisResponse())).single;
    expect(dir['source_policy'], 'wardrobe');
  });

  test('backend shuffle_available flag is preserved onto the direction', () {
    final resp = _styleThisResponse(
      directions: [
        {
          'title': 'P',
          'shuffle_available': true,
          'items': [_item('anchor-1', 'top')],
        },
      ],
    );
    final dir = _directionsOf(parseAhviResponse(resp)).single;
    expect(dir['shuffle_available'], isTrue);
  });

  test(
    'anchor carries its catalog image (resolved_image_url) as normalized_url',
    () {
      // Backend echoes the request anchor_item: raw image_url + the resolved
      // catalog under resolved_image_url. The board anchor must surface the
      // catalog so it renders clean, not the raw crop.
      final resp = _styleThisResponse(
        anchor: {
          'item_id': 'anchor-1',
          'name': 'Pink Shirt',
          'category': 'top',
          'image_url': 'https://example.test/raw_anchor-1.png',
          'resolved_image_url': 'https://example.test/catalog_anchor-1.png',
        },
      );
      final dir = _directionsOf(parseAhviResponse(resp)).single;
      final anchor = (dir['board_items'] as List).cast<Map>().firstWhere(
        (e) => e['item_id'] == 'anchor-1',
      );
      expect(
        anchor['normalized_url'],
        'https://example.test/catalog_anchor-1.png',
      );
    },
  );

  test('no directions of either kind → no visualDirections block', () {
    final parsed = parseAhviResponse({'success': true, 'message_text': 'hi'});
    expect(_hasVisualDirections(parsed), isFalse);
  });

  test('missing anchor_item suppresses Style This boards', () {
    final resp = _styleThisResponse(anchor: const {})..remove('anchor_item');
    expect(_hasVisualDirections(parseAhviResponse(resp)), isFalse);
  });
}
