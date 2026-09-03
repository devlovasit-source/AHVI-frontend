import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/widgets/ahvi_style_board_renderer.dart';

Map<String, dynamic> _direction({
  String? title,
  String? archetype,
  String? headline,
}) => {
  if (title != null) 'title': title,
  if (archetype != null) 'style_archetype': archetype,
  if (headline != null) 'story': {'headline': headline},
  'board_items': [
    {
      'item_id': 'top-1',
      'name': 'White shirt',
      'role': 'top',
      'source': 'wardrobe',
      'image_url': 'https://test/top.png',
    },
  ],
};

void main() {
  test('explicit curated title is the active title authority', () {
    expect(
      // Style This dynamic-title audit: story.headline is backend canned
      // copy keyed by occasion/style_direction (see board_storyteller.py
      // _build_headline) and previously shadowed the curated title,
      // collapsing distinct boards onto the same headline. The explicit
      // title now wins whenever it is present.
      resolveOutfitBoardTitle(
        _direction(
          title: 'Backend Board',
          archetype: 'Refined Weekend',
          headline: 'Quiet Confidence',
        ),
      ),
      'Backend Board',
    );
    expect(
      // P0.8: explicit backend title outranks the generic style_archetype
      // label when there is no story.headline — this assertion previously
      // expected 'Refined Weekend' (the regressed precedence); corrected to
      // match the historical/expected authority order.
      resolveOutfitBoardTitle(
        _direction(title: 'Backend Board', archetype: 'Refined Weekend'),
      ),
      'Backend Board',
    );
    expect(
      resolveOutfitBoardTitle(_direction(archetype: 'Refined Weekend')),
      'Refined Weekend',
    );
    expect(resolveOutfitBoardTitle({}), 'Styled for You');
  });

  test('primary board parser hydrates the top-level BoardStory', () {
    final direction = _direction(
      title: 'Backend Board',
      archetype: 'Refined Weekend',
      headline: 'Quiet Confidence',
    );
    final model = OutfitBoardModel.fromPayload(
      direction,
      editorialCover: const {},
    );
    final board = styleBoardDataFromOutfitBoardForTesting(model, direction);

    expect(model.title, 'Backend Board');
    expect(board.title, 'Backend Board');
    expect(board.story?.headline, 'Quiet Confidence');
  });

  test('primary board parser maps stylingTip into StyleBoardData', () {
    final direction = {
      ..._direction(title: 'Weekend Edit'),
      'styling_tip': 'Cuff the sleeves for a cleaner finish.',
    };
    final model = OutfitBoardModel.fromPayload(
      direction,
      editorialCover: const {},
    );
    final board = styleBoardDataFromOutfitBoardForTesting(model, direction);

    expect(model.stylingTip, 'Cuff the sleeves for a cleaner finish.');
    expect(board.stylingTip, 'Cuff the sleeves for a cleaner finish.');
  });

  test('response aliases preserve story for the shared parser path', () {
    final parsed = parseAhviResponse({
      'route': 'wardrobe_style',
      'rendered_boards': [
        {
          ..._direction(headline: 'Quiet Confidence'),
          'board_id': 'story-board',
        },
      ],
    });
    final block = parsed.blocks.singleWhere(
      (item) => item.type == AhviBlockType.visualDirections,
    );
    final direction = (block.data['directions'] as List).single as Map;
    expect((direction['story'] as Map)['headline'], 'Quiet Confidence');
  });

  testWidgets(
    'canonical renderer displays curated title, not story headline or archetype',
    (tester) async {
      final board = StyleBoardData(
        title: 'Backend Board',
        styleArchetype: 'Refined Weekend',
        story: BoardStory.fromJson(const {'headline': 'Quiet Confidence'}),
        items: const [],
      );
      await tester.pumpWidget(
        MaterialApp(home: AhviStyleBoardRenderer(board: board)),
      );

      expect(find.text('Backend Board'), findsOneWidget);
      expect(find.text('Quiet Confidence'), findsNothing);
      expect(find.text('Refined Weekend'), findsNothing);
    },
  );

  test('resolved title survives saved-board title round-trip', () {
    const title = 'Quiet Confidence';
    final content = buildSavedBoardContent(
      board: const {'board_id': 'story-board'},
      items: const [
        {
          'item_id': 'top-1',
          'role': 'top',
          'source': 'wardrobe',
          'name': 'White shirt',
          'image_url': 'https://test/top.png',
          'masked_url': 'https://test/top-cutout.png',
        },
      ],
      selection: const SavedBoardSelection(bucket: 'everything_else'),
      title: title,
      originalOccasion: 'daily',
    );
    final payload = buildSavedBoardPayload(
      userId: 'user-1',
      imageUrl: 'https://test/cover.png',
      content: content,
    );
    final reopened = expandSavedBoardData(payload);

    expect(jsonDecode(content.masterGarment)['title'], title);
    expect(reopened['title'], title);
  });

  test('no universal Refined Weekend fallback is introduced', () {
    expect(resolveOutfitBoardTitle({}), isNot('Refined Weekend'));
  });

  // ------------------------------------------------------------------
  // P0.8 — Dynamic title regression. The backend always populates both
  // card["title"] (curated editorial copy) and card["style_archetype"]
  // (generic label). story.headline is normally absent on the primary
  // live generation path, so whichever of title/style_archetype the
  // function checks first wins in practice — it must be the explicit
  // title. Historical authority: 27acd9a.
  // ------------------------------------------------------------------

  test('CASE 1: explicit title outranks style_archetype when no headline', () {
    expect(
      resolveOutfitBoardTitle(
        _direction(
          title: 'Weekend Terrace Brunch',
          archetype: 'Elevated Essentials',
        ),
      ),
      'Weekend Terrace Brunch',
    );
  });

  test(
    'CASE 2: explicit title now outranks story.headline (canned/occasion '
    'headline copy was collapsing distinct boards onto one title)',
    () {
      expect(
        resolveOutfitBoardTitle(
          _direction(
            title: 'Weekend Terrace Brunch',
            archetype: 'Elevated Essentials',
            headline: 'Sunday Brunch Edit',
          ),
        ),
        'Weekend Terrace Brunch',
      );
    },
  );

  test('CASE 3: style_archetype remains the fallback when title is absent', () {
    expect(
      resolveOutfitBoardTitle(_direction(archetype: 'Elevated Essentials')),
      'Elevated Essentials',
    );
  });

  test(
    'CASE 4: the existing "build outfit" -> "Try-On" rewrite still applies '
    'only on the explicit-title branch',
    () {
      expect(
        resolveOutfitBoardTitle(
          _direction(
            title: 'Build Outfit',
            archetype: 'Elevated Essentials',
          ),
        ),
        'Try-On',
      );
    },
  );

  test(
    'CASE 5: realistic backend payload (title + style_archetype populated, '
    'no story dict) resolves to the curated title, not the archetype',
    () {
      final direction = _direction(
        title: 'Weekend Terrace Brunch',
        archetype: 'Elevated Essentials',
      );
      final model = OutfitBoardModel.fromPayload(
        direction,
        editorialCover: const {},
      );
      expect(model.title, 'Weekend Terrace Brunch');
      expect(model.title, isNot('Elevated Essentials'));
    },
  );

  test(
    'CASE 6: save/share consumer contract — the persisted title is the '
    'curated title, not style_archetype (Save/Share consume the same '
    'resolved primaryLabel; not re-implemented here per P0.8 scope)',
    () {
      final direction = _direction(
        title: 'Weekend Terrace Brunch',
        archetype: 'Elevated Essentials',
      );
      final model = OutfitBoardModel.fromPayload(
        direction,
        editorialCover: const {},
      );
      final content = buildSavedBoardContent(
        board: const {'board_id': 'p0-8-board'},
        items: const [
          {
            'item_id': 'top-1',
            'role': 'top',
            'source': 'wardrobe',
            'name': 'White shirt',
            'image_url': 'https://test/top.png',
            'masked_url': 'https://test/top-cutout.png',
          },
        ],
        selection: const SavedBoardSelection(bucket: 'everything_else'),
        title: model.title,
        originalOccasion: 'daily',
      );
      final payload = buildSavedBoardPayload(
        userId: 'user-1',
        imageUrl: 'https://test/cover.png',
        content: content,
      );
      final reopened = expandSavedBoardData(payload);

      expect(jsonDecode(content.masterGarment)['title'], 'Weekend Terrace Brunch');
      expect(reopened['title'], 'Weekend Terrace Brunch');
      expect(reopened['title'], isNot('Elevated Essentials'));
    },
  );

  // ------------------------------------------------------------------
  // Regression guards — confirm the surrounding precedence tiers were not
  // disturbed by reordering the explicit-title check.
  // ------------------------------------------------------------------

  test('regression guard: explicit title retains highest authority', () {
    expect(
      resolveOutfitBoardTitle(
        _direction(
          title: 'Weekend Terrace Brunch',
          archetype: 'Elevated Essentials',
          headline: 'Quiet Confidence',
        ),
      ),
      'Weekend Terrace Brunch',
    );
  });

  test('regression guard: headline is used only when no explicit title exists', () {
    expect(
      resolveOutfitBoardTitle(
        _direction(archetype: 'Elevated Essentials', headline: 'Quiet Confidence'),
      ),
      'Quiet Confidence',
    );
  });

  // ------------------------------------------------------------------
  // Style This dynamic-title audit — proves distinct garments no longer
  // collapse onto the same backend canned headline (e.g. "Elevated
  // Essentials"/board_storyteller's occasion-keyed headline copy) when
  // each direction carries its own curated title. Fixtures mirror the
  // real backend shape: card["title"] (curated, per-card) +
  // card["style_archetype"] (shared generic label) + story.headline
  // (shared canned occasion/direction copy) all populated at once,
  // as produced by services/style_flow_service.py + board_storyteller.py.
  // ------------------------------------------------------------------

  test(
    'DISTINCT_TITLE_TEST: Pink Jacket, Black Blazer, and Saree resolve to '
    'distinct curated titles despite sharing one generic archetype and one '
    'generic canned headline',
    () {
      const sharedArchetype = 'Elevated Essentials';
      const sharedHeadline = 'Composed Formal'; // e.g. board_storyteller's
      // formal_event canned headline — identical across every board in one
      // Style-This response, regardless of the anchor garment.

      final pinkJacket = _direction(
        title: 'Pink Jacket Evening Edit',
        archetype: sharedArchetype,
        headline: sharedHeadline,
      );
      final blackBlazer = _direction(
        title: 'Black Blazer Power Look',
        archetype: sharedArchetype,
        headline: sharedHeadline,
      );
      final saree = _direction(
        title: 'Saree Festive Drape',
        archetype: sharedArchetype,
        headline: sharedHeadline,
      );

      final titles = [
        resolveOutfitBoardTitle(pinkJacket),
        resolveOutfitBoardTitle(blackBlazer),
        resolveOutfitBoardTitle(saree),
      ];

      expect(titles, [
        'Pink Jacket Evening Edit',
        'Black Blazer Power Look',
        'Saree Festive Drape',
      ]);
      expect(titles.toSet().length, 3, reason: 'titles must not collapse');
      expect(titles, isNot(contains(sharedArchetype)));
      expect(titles, isNot(contains(sharedHeadline)));
    },
  );

  test('regression guard: style_strategy.archetype fallback remains intact', () {
    expect(
      resolveOutfitBoardTitle({
        'style_strategy': {'archetype': 'Understated Polish'},
        'board_items': const [],
      }),
      'Understated Polish',
    );
  });

  test('regression guard: style_strategy.direction fallback remains intact', () {
    expect(
      resolveOutfitBoardTitle({
        'style_strategy': {'direction_title': 'Effortless Edge'},
        'board_items': const [],
      }),
      'Effortless Edge',
    );
  });

  test('regression guard: fallback "Styled for You" remains intact', () {
    expect(resolveOutfitBoardTitle({}), 'Styled for You');
  });
}
