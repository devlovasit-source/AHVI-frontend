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
  test('story headline is the active title authority', () {
    expect(
      resolveOutfitBoardTitle(
        _direction(
          title: 'Backend Board',
          archetype: 'Refined Weekend',
          headline: 'Quiet Confidence',
        ),
      ),
      'Quiet Confidence',
    );
    expect(
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

    expect(model.title, 'Quiet Confidence');
    expect(board.title, 'Quiet Confidence');
    expect(board.story?.headline, 'Quiet Confidence');
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

  testWidgets('canonical renderer displays story headline over archetype', (
    tester,
  ) async {
    final board = StyleBoardData(
      title: 'Backend Board',
      styleArchetype: 'Refined Weekend',
      story: BoardStory.fromJson(const {'headline': 'Quiet Confidence'}),
      items: const [],
    );
    await tester.pumpWidget(
      MaterialApp(home: AhviStyleBoardRenderer(board: board)),
    );

    expect(find.text('Quiet Confidence'), findsOneWidget);
    expect(find.text('Refined Weekend'), findsNothing);
  });

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
}
