import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_renderer.dart';
import 'package:myapp/style_board/saved_board_images.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

void main() {
  final shuffledItems = <Map<String, dynamic>>[
    {
      'item_id': 'bottom-2',
      'role': 'bottom',
      'source': 'wardrobe',
      'name': 'Navy trousers',
      'masked_url': 'https://test/wardrobe_bottom-2_cutout_v2.png',
      'image_status': 'rmbg_complete',
      'position': {
        'x': 0.44,
        'y': 0.38,
        'width': 0.5,
        'height': 0.52,
        'scale': 1.08,
        'rotation': -0.03,
        'z': 1,
      },
    },
    {
      'item_id': 'top-4',
      'role': 'top',
      'source': 'style_asset',
      'name': 'White shirt',
      'normalized_url': 'https://test/catalog_top-4.png',
      'position': {'x': 0.15, 'y': 0.07, 'width': 0.62, 'height': 0.52, 'z': 2},
    },
  ];

  Map<String, dynamic> liveBoard() => {
    'board_id': 'board-stable-1',
    'revision': 3,
    'source_policy': 'wardrobe',
    'occasion': 'office',
  };

  SavedBoardContent content({bool favourite = false}) => buildSavedBoardContent(
    board: liveBoard(),
    items: shuffledItems,
    selection: SavedBoardSelection(
      bucket: 'office_fits',
      isFavourite: favourite,
    ),
    title: 'Office polish',
    originalOccasion: 'office',
  );

  Map<String, dynamic> payload({bool favourite = false}) =>
      buildSavedBoardPayload(
        userId: 'user-1',
        imageUrl: 'https://test/cover.png',
        content: content(favourite: favourite),
      );

  test('Style This save preserves the exact anchor identity and revision', () {
    final saved = buildSavedBoardContent(
      board: {
        ...liveBoard(),
        'scenario': 'style_this',
        'interaction_mode': 'style_this',
        'anchor_item_id': 'bottom-2',
      },
      items: shuffledItems,
      selection: const SavedBoardSelection(bucket: 'office_fits'),
      title: 'Style This office look',
      originalOccasion: 'office',
    );

    final master = jsonDecode(saved.masterGarment) as Map<String, dynamic>;
    expect(saved.itemIds, contains('bottom-2'));
    expect(master['scenario'], 'style_this');
    expect(master['interaction_mode'], 'style_this');
    expect(master['anchor_item_id'], 'bottom-2');
    expect(master['revision'], 3);
  });

  test(
    'Daily Wear v2 content reopens with canonical bucket and item identity',
    () {
      final items = [
        {
          'id': 'daily-top-1',
          'item_id': 'daily-top-1',
          'role': 'top',
          'source': 'wardrobe',
          'name': 'White shirt',
          'image_url': 'https://test/daily-top-cutout.png',
          'masked_url': 'https://test/daily-top-cutout.png',
          'original_image_url': 'https://test/daily-top.png',
          'selected_field': 'masked_url',
          'source_kind': 'legacy_masked_cutout',
          'expected_transparent': true,
        },
        {
          'id': 'daily-shoe-1',
          'item_id': 'daily-shoe-1',
          'role': 'footwear',
          'source': 'wardrobe',
          'name': 'Loafers',
          'image_url': 'https://test/daily-shoe-cutout.png',
          'masked_url': 'https://test/daily-shoe-cutout.png',
          'original_image_url': 'https://test/daily-shoe.png',
          'selected_field': 'masked_url',
          'source_kind': 'legacy_masked_cutout',
          'expected_transparent': true,
        },
      ];
      final content = buildSavedBoardContent(
        board: {
          'board_id': 'daily-board-1',
          'revision': 1,
          'source_policy': 'wardrobe',
        },
        items: items,
        selection: const SavedBoardSelection(bucket: 'everything_else'),
        title: 'Daily Look',
        originalOccasion: 'daily',
      );
      final payload = buildSavedBoardPayload(
        userId: 'user-1',
        imageUrl: 'https://test/daily-top-cutout.png',
        content: content,
      );

      expect(payload.keys.toSet(), savedBoardAcceptedFields);
      expect(payload['occasion'], 'everything_else');
      expect(payload['itemIds'], ['daily-top-1', 'daily-shoe-1']);
      expect(jsonDecode(content.masterGarment)['original_occasion'], 'daily');
      expect(jsonDecode(content.outfitItems), hasLength(2));

      final reopened = expandSavedBoardData(payload);
      expect(reopened['bucket'], 'everything_else');
      expect(reopened['itemIds'], ['daily-top-1', 'daily-shoe-1']);
      expect(
        (reopened['items'] as List).first['image_url'],
        'https://test/daily-top-cutout.png',
      );
      expect(savedBoardReopenParity(payload)['image_provenance_match'], isTrue);
    },
  );

  test('Daily Wear content fails safely for missing stable IDs', () {
    expect(
      () => buildSavedBoardContent(
        board: {'board_id': 'daily-board-2'},
        items: [
          {
            'role': 'top',
            'source': 'wardrobe',
            'image_url': 'https://test/no-id.png',
          },
        ],
        selection: const SavedBoardSelection(bucket: 'everything_else'),
        title: 'Daily Look',
        originalOccasion: 'daily',
      ),
      throwsA(
        isA<SavedBoardPersistenceException>().having(
          (error) => error.reason,
          'reason',
          'invalid_item_ids',
        ),
      ),
    );
  });

  group('deployed Appwrite contract', () {
    test('payload contains exactly the six deployed attributes', () {
      final data = payload();

      expect(data.keys.toSet(), savedBoardAcceptedFields);
      expect(data, isNot(contains('outfitDescription')));
      expect(data, isNot(contains('emoji')));
      expect(data, isNot(contains('boardCategory')));
      expect(data, isNot(contains('thumbnailUrl')));
      expect(data, isNot(contains('board_payload')));
    });

    test('userId limit is enforced', () {
      expect(
        () => buildSavedBoardPayload(
          userId: 'u' * 53,
          imageUrl: 'https://test/cover.png',
          content: content(),
        ),
        throwsA(
          isA<SavedBoardPersistenceException>().having(
            (error) => error.reason,
            'reason',
            'invalid_user_id',
          ),
        ),
      );
    });

    test('occasion limit and canonical value are enforced', () {
      final valid = payload();
      expect(valid['occasion'], 'office_fits');
      final invalid = SavedBoardContent(
        bucket: 'x' * 51,
        isFavourite: false,
        boardId: 'board-1',
        itemIds: const ['item-1'],
        masterGarment: '{}',
        outfitItems: '[]',
      );
      expect(
        () => buildSavedBoardPayload(
          userId: 'user-1',
          imageUrl: 'https://test/cover.png',
          content: invalid,
        ),
        throwsA(isA<SavedBoardPersistenceException>()),
      );
    });

    test('imageUrl must be an absolute HTTP or HTTPS URL', () {
      for (final value in [
        '',
        'board-1',
        'assets/look.png',
        'file:///look.png',
      ]) {
        expect(
          () => buildSavedBoardPayload(
            userId: 'user-1',
            imageUrl: value,
            content: content(),
          ),
          throwsA(isA<SavedBoardPersistenceException>()),
        );
      }
    });

    test('masterGarment and outfitItems limits are enforced', () {
      final base = content();
      for (final oversized in [
        SavedBoardContent(
          bucket: base.bucket,
          isFavourite: false,
          boardId: base.boardId,
          itemIds: base.itemIds,
          masterGarment: 'x' * 100001,
          outfitItems: base.outfitItems,
        ),
        SavedBoardContent(
          bucket: base.bucket,
          isFavourite: false,
          boardId: base.boardId,
          itemIds: base.itemIds,
          masterGarment: base.masterGarment,
          outfitItems: 'x' * 10001,
        ),
      ]) {
        expect(
          () => buildSavedBoardPayload(
            userId: 'user-1',
            imageUrl: 'https://test/cover.png',
            content: oversized,
          ),
          throwsA(isA<SavedBoardPersistenceException>()),
        );
      }
    });
  });

  group('category inference', () {
    for (final entry in {
      'office': 'office_fits',
      'work': 'office_fits',
      'business': 'office_fits',
      'party': 'party_looks',
      'cocktail': 'party_looks',
      'vacation': 'vacation',
      'beach': 'vacation',
      'wedding': 'occasion',
      'festival': 'occasion',
      'unknown': 'everything_else',
    }.entries) {
      test('${entry.key} defaults to ${entry.value}', () {
        expect(inferSavedBoardBucket({'occasion': entry.key}), entry.value);
      });
    }

    test('user selection overrides inferred category', () {
      final selected = buildSavedBoardContent(
        board: liveBoard(),
        items: shuffledItems,
        selection: const SavedBoardSelection(bucket: 'vacation'),
        title: 'Office polish',
        originalOccasion: 'office',
      );
      expect(selected.bucket, 'vacation');
    });
  });

  group('canonical persistence and reopen', () {
    test('visible reasoning and tip survive canonical save readback', () {
      final saved = buildSavedBoardContent(
        board: {
          ...liveBoard(),
          'why_it_works': 'Visible reasoning.',
          'styling_tip': 'Visible tip.',
        },
        items: shuffledItems,
        selection: const SavedBoardSelection(bucket: 'office_fits'),
        title: 'Look',
        originalOccasion: 'office',
      );
      final reopened = expandSavedBoardData(
        buildSavedBoardPayload(
          userId: 'user-test',
          imageUrl: 'https://test/cover.png',
          content: saved,
        ),
      );
      expect(reopened['why_it_works'], 'Visible reasoning.');
      expect(reopened['styling_tip'], 'Visible tip.');
    });
    test('current order, metadata, provenance and layout survive', () {
      final saved = payload(favourite: true);
      final reopened = expandSavedBoardData(saved);
      final items = (reopened['items'] as List).cast<Map<String, dynamic>>();

      expect(reopened['board_id'], 'board-stable-1');
      expect(reopened['revision'], 3);
      expect(reopened['source_policy'], 'wardrobe');
      expect(reopened['layout_mode'], 'generic');
      expect(reopened['itemIds'], ['bottom-2', 'top-4']);
      expect(reopened, isNot(contains('outfitItems')));
      expect(items.map((item) => item['item_id']), ['bottom-2', 'top-4']);
      expect(items.map((item) => item['role']), ['bottom', 'top']);
      expect(items.map((item) => item['source']), ['wardrobe', 'style_asset']);
      expect(items.first['selected_field'], 'masked_url');
      expect(items.first['source_kind'], 'validated_cutout');
      expect(items.first['expected_transparent'], isTrue);
      expect(items.first['position'], {
        'x': 0.44,
        'y': 0.38,
        'width': 0.5,
        'height': 0.52,
        'scale': 1.08,
        'rotation': -0.03,
        'z': 1,
      });
      expect(items.last['selected_field'], 'normalized_url');
      expect(items.last['source_kind'], 'catalog_fallback');
      expect(items.last['expected_transparent'], isFalse);
      expect(reopened['is_favourite'], isTrue);
    });

    test('style asset policy is preserved as a valid runtime policy', () {
      final board = liveBoard()..['source_policy'] = 'style_asset';
      final saved = buildSavedBoardContent(
        board: board,
        items: shuffledItems,
        selection: const SavedBoardSelection(bucket: 'office_fits'),
        title: 'Office polish',
        originalOccasion: 'office',
      );

      expect(jsonDecode(saved.masterGarment)['source_policy'], 'style_asset');
      expect(
        expandSavedBoardData(
          buildSavedBoardPayload(
            userId: 'user-1',
            imageUrl: 'https://test/cover.png',
            content: saved,
          ),
        )['source_policy'],
        'style_asset',
      );
    });

    test('boards without a backend id receive a deterministic saved id', () {
      SavedBoardContent build() => buildSavedBoardContent(
        board: const {'occasion': 'office'},
        items: shuffledItems,
        selection: const SavedBoardSelection(bucket: 'office_fits'),
        title: 'Office polish',
        originalOccasion: 'office',
      );

      final first = build();
      final second = build();
      expect(first.boardId, startsWith('saved_'));
      expect(first.boardId, second.boardId);
      expect(jsonDecode(first.masterGarment)['source_policy'], isEmpty);
    });

    test('catalogue stays framed and validated cutout stays transparent', () {
      final reopened = expandSavedBoardData(payload());
      final board = boardDataFromMap(reopened);
      final bottom = board.items.firstWhere((item) => item.id == 'bottom-2');
      final top = board.items.firstWhere((item) => item.id == 'top-4');

      expect(bottom.role, BoardItemRole.bottom);
      expect(bottom.shouldFrame, isFalse);
      expect(bottom.position?.x, 0.44);
      expect(bottom.position?.scale, 1.08);
      expect(bottom.position?.rotation, -0.03);
      expect(board.boardId, 'board-stable-1');
      expect(board.revision, 3);
      expect(board.sourcePolicy, 'wardrobe');
      expect(top.role, BoardItemRole.top);
      expect(top.shouldFrame, isTrue);
      expect(extractSavedBoardImages(payload()), [
        'https://test/wardrobe_bottom-2_cutout_v2.png',
        'https://test/catalog_top-4.png',
      ]);
    });

    test('saved reopen preserves the live resolver decision and layout', () {
      final liveItem = resolveStyleBoardItemImage(
        {
          'item_id': 'saved-white-1',
          'role': 'top',
          'source': 'wardrobe',
          'name': 'White shirt',
          'board_image_url': 'https://test/white-board.png',
          'position': {
            'x': 0.21,
            'y': 0.12,
            'width': 0.55,
            'height': 0.48,
            'rotation': 0.02,
          },
        },
        {
          'saved-white-1': {
            r'$id': 'saved-white-1',
            'normalized_url': 'https://test/catalog_saved-white-1.jpg',
          },
        },
        surface: 'style_board_live',
        emitDiagnostic: false,
      );
      final savedContent = buildSavedBoardContent(
        board: liveBoard(),
        items: [liveItem],
        selection: const SavedBoardSelection(bucket: 'office_fits'),
        title: 'White shirt look',
        originalOccasion: 'office',
      );
      final reopened = expandSavedBoardData(
        buildSavedBoardPayload(
          userId: 'user-1',
          imageUrl: 'https://test/cover.png',
          content: savedContent,
        ),
      );
      final reopenedItem = (reopened['items'] as List).single as Map;
      final rendered = boardDataFromMap(reopened).items.single;

      expect(reopenedItem['item_id'], 'saved-white-1');
      expect(reopenedItem['selected_field'], 'normalized_url');
      expect(reopenedItem['source_kind'], 'catalog_fallback');
      expect(reopenedItem['expected_transparent'], isFalse);
      expect(rendered.shouldFrame, isTrue);
      expect(rendered.position?.x, 0.21);
      expect(rendered.position?.rotation, 0.02);

      final parity = savedBoardReopenParity(
        reopened,
        renderedItems: [rendered.toContractJson()],
      );
      expect(parity['item_count_match'], isTrue);
      expect(parity['item_order_match'], isTrue);
      expect(parity['source_policy_match'], isTrue);
      expect(parity['image_provenance_match'], isTrue);
    });
  });

  group('Favourites and filters', () {
    test('Favourite defaults false and survives reopen when enabled', () {
      expect(expandSavedBoardData(payload())['is_favourite'], isFalse);
      expect(
        expandSavedBoardData(payload(favourite: true))['is_favourite'],
        isTrue,
      );
    });

    test('Favourite updates only the encoded master metadata', () {
      final data = payload();
      final updated = savedBoardMasterGarmentWithFavourite(data, true);
      final reopened = expandSavedBoardData({
        ...data,
        'masterGarment': updated,
      });

      expect(reopened['is_favourite'], isTrue);
      expect(reopened['itemIds'], data['itemIds']);
    });

    test('legacy Favourite updates use the deployed masterGarment field', () {
      final legacy = {
        'occasion': 'Office',
        'isFavourite': true,
        'outfitDescription': jsonEncode({
          'schema': 'ahvi_saved_board_v1',
          'board': {'board_id': 'old-board', 'items': shuffledItems},
        }),
      };
      final updated = savedBoardMasterGarmentWithFavourite(legacy, true);

      expect(
        expandSavedBoardData({
          ...legacy,
          'masterGarment': updated,
        })['is_favourite'],
        isTrue,
      );
      final removed = savedBoardMasterGarmentWithFavourite({
        ...legacy,
        'masterGarment': updated,
      }, false);
      expect(
        expandSavedBoardData({
          ...legacy,
          'masterGarment': removed,
        })['is_favourite'],
        isFalse,
      );
    });

    test('duplicate item ids are rejected before persistence', () {
      expect(
        () => buildSavedBoardContent(
          board: liveBoard(),
          items: [shuffledItems.first, shuffledItems.first],
          selection: const SavedBoardSelection(bucket: 'office_fits'),
          title: 'Office polish',
          originalOccasion: 'office',
        ),
        throwsA(
          isA<SavedBoardPersistenceException>().having(
            (error) => error.reason,
            'reason',
            'duplicate_item_ids',
          ),
        ),
      );
    });

    test('Favourite remains in primary category and appears in Favourites', () {
      final data = payload(favourite: true);
      expect(savedBoardMatchesFilter(data, 'all'), isTrue);
      expect(savedBoardMatchesFilter(data, 'office_fits'), isTrue);
      expect(savedBoardMatchesFilter(data, 'favourites'), isTrue);
    });

    test('non-Favourite does not appear in Favourites', () {
      expect(savedBoardMatchesFilter(payload(), 'favourites'), isFalse);
    });
  });

  group('backward compatibility', () {
    test('old v1 saved documents still open', () {
      final old = {
        'occasion': 'Office',
        'outfitDescription': jsonEncode({
          'schema': 'ahvi_saved_board_v1',
          'board': {'board_id': 'old-board', 'items': shuffledItems},
        }),
      };
      final reopened = expandSavedBoardData(old);
      expect(reopened['board_id'], 'old-board');
      expect(reopened['bucket'], 'office_fits');
      expect(reopened['is_favourite'], isFalse);
    });

    test('legacy occasion values map to canonical buckets', () {
      expect(canonicalSavedBoardBucket('work'), 'office_fits');
      expect(canonicalSavedBoardBucket('cocktail'), 'party_looks');
      expect(canonicalSavedBoardBucket('beach'), 'vacation');
      expect(canonicalSavedBoardBucket('formal'), 'occasion');
      expect(canonicalSavedBoardBucket('daily'), 'everything_else');
    });

    test('provisional shared assets policy reopens as style asset', () {
      final data = payload();
      final master =
          jsonDecode(data['masterGarment'] as String) as Map<String, dynamic>;
      master['source_policy'] = 'shared_assets';

      expect(
        expandSavedBoardData({
          ...data,
          'masterGarment': jsonEncode(master),
        })['source_policy'],
        'style_asset',
      );
    });

    test('malformed JSON and missing optional fields fall back safely', () {
      final malformed = expandSavedBoardData({
        'occasion': 'unknown',
        'masterGarment': '{bad',
        'outfitItems': '[bad',
        'itemIds': const ['old-1'],
      });
      expect(malformed['bucket'], 'everything_else');
      expect(malformed['is_favourite'], isFalse);
      expect(extractSavedBoardImages(malformed), isEmpty);
    });
  });
}
