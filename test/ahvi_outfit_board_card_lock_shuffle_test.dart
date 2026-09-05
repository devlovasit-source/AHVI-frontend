import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/style_board/saved_board_thumb.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

Map<String, dynamic> _item(
  String id,
  String slot, {
  bool locked = false,
  double x = .1,
}) => {
  'item_id': id,
  'name': id,
  'slot': slot,
  'role': slot,
  'source': 'wardrobe',
  'image_url': 'https://example.test/$id.png',
  'masked_url': 'https://example.test/$id-cutout.png',
  // Transparent cutout for the style_asset resolver path (asset items read
  // transparent_url/asset_cutout_url, not masked_url). Inert for wardrobe items.
  'transparent_url': 'https://example.test/$id-cutout.png',
  'locked': locked,
  'position': {
    'x': x,
    'y': .1,
    'width': .24,
    'height': .28,
    'rotation': 0,
    'z': 1,
  },
};

Map<String, dynamic> _board({
  String boardId = '11111111-1111-4111-8111-111111111111',
  int revision = 1,
  String scenario = 'build_outfit',
  String sourcePolicy = 'wardrobe',
}) => {
  'board_id': boardId,
  'revision': revision,
  'scenario': scenario,
  'source_policy': sourcePolicy,
  'shuffle_available': true,
  'title': 'Build Outfit',
  'occasion': 'Client meeting',
  'style_archetype': 'Business professional',
  'board_items': [
    _item('anchor', 'top', locked: true, x: .08),
    _item('bottom-1', 'bottom', x: .40),
    _item('shoe-1', 'footwear', x: .14),
  ],
};

StyleBoardShuffleResult _success(StyleBoardState request) {
  final items = request.items.map((item) {
    if (request.lockedItemIds.contains(item.itemId)) return item;
    return StyleBoardItem.fromJson(
      _item('${item.itemId}-new', item.slot, x: item.position!.x!),
    );
  }).toList();
  return StyleBoardShuffleResult(
    boardId: request.boardId,
    revision: request.revision + 1,
    previousRevision: request.revision,
    lockedItemsPreserved: true,
    changedSlots: const ['bottom'],
    items: items,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedBoardsStore.resetForTest();
  });

  testWidgets(
    'mutation regression: saved identity resets after shuffle3 undo',
    (tester) async {
      final saved = <List<String>>[];
      final readbacks = <Map<String, dynamic>>[];
      await _pumpCard(
        tester,
        board: _board()
          ..['why_it_works'] = 'The original trousers balance this shirt.',
        shuffleCall: (state) async => _success(state),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              saved.add(List<String>.from(itemIds));
              final bar = tester.widget<OutfitActionBar>(
                find.byType(OutfitActionBar),
              );
              final content = buildSavedBoardContent(
                board: bar.currentDirectionOverride!(),
                items: items,
                selection: SavedBoardSelection(bucket: occasion),
                title: title,
                originalOccasion: 'office',
              );
              readbacks.add(
                expandSavedBoardData(
                  buildSavedBoardPayload(
                    userId: 'user-test',
                    imageUrl: imageUrl,
                    content: content,
                  ),
                ),
              );
              return 'doc-${saved.length}';
            },
      );
      Future<void> save() async {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save look'));
        await tester.pumpAndSettle();
      }

      await save();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Shuffle unlocked pieces'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Undo shuffle'));
      await tester.pump();
      final controller = tester
          .widget<BoardMutationBar>(find.byType(BoardMutationBar))
          .controller;
      expect(controller.state.revision, 3);
      expect(controller.state.lockedItemIds, {'anchor'});
      expect(find.text('Save'), findsOneWidget);
      await save();
      expect(saved, [
        ['anchor', 'bottom-1', 'shoe-1'],
        ['anchor', 'bottom-1-new-new', 'shoe-1-new-new'],
      ]);
      expect(
        readbacks.first['why_it_works'],
        'The original trousers balance this shirt.',
      );
      expect(readbacks.last['why_it_works'], isNull);
      expect(readbacks.last['revision'], 3);
      expect(
        (readbacks.last['items'] as List).map((item) => item['item_id']),
        saved.last,
      );
    },
  );

  testWidgets(
    'mutation regression: Style This saves visible normalized image and copy',
    (tester) async {
      final board = _board(scenario: 'style_this')
        ..['anchor_item_id'] = 'anchor'
        ..['why_it_works'] = 'The anchor balances these trousers.'
        ..['styling_tip'] = 'Roll the anchor sleeves.';
      for (final item
          in (board['board_items'] as List).cast<Map<String, dynamic>>()) {
        item['normalized_url'] =
            'https://example.test/catalog_${item['item_id']}.jpg';
      }
      Map<String, dynamic>? reopened;
      await _pumpCard(
        tester,
        board: board,
        shuffleCall: (state) async => _success(state),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              final bar = tester.widget<OutfitActionBar>(
                find.byType(OutfitActionBar),
              );
              final content = buildSavedBoardContent(
                board: bar.currentDirectionOverride!(),
                items: items,
                selection: SavedBoardSelection(bucket: occasion),
                title: title,
                originalOccasion: 'office',
              );
              reopened = expandSavedBoardData(
                buildSavedBoardPayload(
                  userId: 'user-test',
                  imageUrl: imageUrl,
                  content: content,
                ),
              );
              return 'doc-parity';
            },
      );
      final visible = tester
          .widget<AhviUnifiedOutfitGrid>(find.byType(AhviUnifiedOutfitGrid))
          .items;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save look'));
      await tester.pumpAndSettle();
      expect(
        (reopened!['items'] as List).map((item) => item['image_url']),
        visible.map((item) => item.resolvedImageUrl),
      );
      expect(reopened!['why_it_works'], 'The anchor balances these trousers.');
      expect(reopened!['styling_tip'], 'Roll the anchor sleeves.');
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 400,
            child: SavedBoardThumb(source: reopened!, wardrobeById: const {}),
          ),
        ),
      );
      await tester.pump();
      final readback = tester
          .widget<AhviUnifiedOutfitGrid>(find.byType(AhviUnifiedOutfitGrid))
          .items;
      expect(
        readback.map((item) => item.resolvedImageUrl),
        visible.map((item) => item.resolvedImageUrl),
      );
    },
  );

  testWidgets(
    'mutation regression: reasoning clears on composition change and returns on undo',
    (tester) async {
      final board = _board()
        ..['short_note'] = 'The original trousers balance this shirt.'
        ..['why'] = 'Old alternate reasoning.'
        ..['styling_tip'] = 'Cuff the original trousers.';
      await _pumpCard(
        tester,
        board: board,
        shuffleCall: (state) async => _success(state),
      );
      expect(
        find.text('The original trousers balance this shirt.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style-why-it-works')), findsNothing);
      expect(find.byKey(const ValueKey('style-styling-tip')), findsNothing);
      final bar = tester.widget<OutfitActionBar>(find.byType(OutfitActionBar));
      final direction = bar.currentDirectionOverride!();
      expect(direction['why_it_works'], isEmpty);
      expect(
        direction['short_note'],
        isNot('The original trousers balance this shirt.'),
      );
      expect(direction['why'], isNot('Old alternate reasoning.'));
      await tester.tap(find.text('Undo shuffle'));
      await tester.pump();
      expect(
        find.text('The original trousers balance this shirt.'),
        findsOneWidget,
      );
      expect(find.text('Cuff the original trousers.'), findsOneWidget);
    },
  );

  testWidgets(
    'mutation regression: pending replacement publishes accepted state',
    (tester) async {
      final pending = Completer<StyleBoardShuffleResult>();
      final observed = <Map<String, dynamic>>[];
      await _pumpCard(
        tester,
        board: _board(),
        shuffleCall: (_) => pending.future,
        onBoardStateChanged: observed.add,
      );
      final controller = tester
          .widget<BoardMutationBar>(find.byType(BoardMutationBar))
          .controller;
      final request = controller.state;
      final shuffle = controller.shuffle();
      await _pumpCard(
        tester,
        board: _board(revision: 3),
        shuffleCall: (_) => pending.future,
        onBoardStateChanged: observed.add,
      );
      pending.complete(_success(request));
      await shuffle;
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<BoardMutationBar>(find.byType(BoardMutationBar))
            .controller
            .state
            .revision,
        3,
      );
      expect(observed.last['revision'], 3);
    },
  );

  testWidgets(
    'mutation regression: queued replacement cannot overwrite newer board',
    (tester) async {
      final pending = Completer<StyleBoardShuffleResult>();
      await _pumpCard(
        tester,
        board: _board(),
        shuffleCall: (_) => pending.future,
      );
      final controller = tester
          .widget<BoardMutationBar>(find.byType(BoardMutationBar))
          .controller;
      final request = controller.state;
      final shuffle = controller.shuffle();
      await _pumpCard(
        tester,
        board: _board(revision: 3),
        shuffleCall: (_) => pending.future,
      );
      pending.complete(_success(request));
      await shuffle;
      await _pumpCard(
        tester,
        board: _board(revision: 4),
        shuffleCall: (state) async => _success(state),
      );
      await tester.pump();
      expect(
        tester
            .widget<BoardMutationBar>(find.byType(BoardMutationBar))
            .controller
            .state
            .revision,
        4,
      );
      final bar = tester.widget<OutfitActionBar>(find.byType(OutfitActionBar));
      expect(bar.currentDirectionOverride!()['revision'], 4);
    },
  );

  test(
    'interaction mode is explicit and never inferred from source policy',
    () {
      expect(
        inferBoardInteractionMode({'source_policy': 'wardrobe'}),
        BoardInteractionMode.recommendation,
      );
      expect(
        inferBoardInteractionMode({
          'interaction_mode': 'style-this',
          'source_policy': 'wardrobe',
        }),
        BoardInteractionMode.styleThis,
      );
      expect(
        inferBoardInteractionMode({
          'interaction_mode': '',
          'scenario': 'build_outfit',
          'source_policy': 'style_asset',
        }),
        BoardInteractionMode.buildOutfit,
      );
    },
  );

  testWidgets('recommendation exposes feedback without mutation controls', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      board: _board(scenario: 'recommendation'),
      shuffleCall: (state) async => _success(state),
    );

    expect(find.byType(BoardMutationBar), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.textContaining('Shuffle'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Dislike'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('Style This locks its originating garment by default', (
    tester,
  ) async {
    final board = _board(scenario: 'style_this', sourcePolicy: 'style_asset');
    final items = (board['board_items'] as List).whereType<Map>();
    for (final item in items) {
      item['locked'] = false;
      if (item['item_id'] != 'anchor') item['source'] = 'style_asset';
    }
    await _pumpCard(
      tester,
      board: board,
      shuffleCall: (state) async => _success(state),
    );

    expect(find.text('1 of 3 items locked'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('Like'), findsNothing);
    expect(find.text('Dislike'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('active card locks multiple items and unlocks all locally', (
    tester,
  ) async {
    var apiCalls = 0;
    await _pumpCard(
      tester,
      board: _board(),
      shuffleCall: (state) async {
        apiCalls++;
        return _success(state);
      },
    );

    expect(find.text('1 of 3 items locked'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('lock-shoe-1')));
    await tester.pump();
    expect(find.text('2 of 3 items locked'), findsOneWidget);
    expect(apiCalls, 0);

    await tester.tap(find.byKey(const ValueKey<String>('lock-bottom-1')));
    await tester.pump();
    expect(find.text('3 of 3 items locked'), findsOneWidget);
    expect(find.text('Unlock an item to shuffle'), findsOneWidget);

    await tester.tap(find.text('Unlock all'));
    await tester.pump();
    expect(find.text('0 of 3 items locked'), findsOneWidget);
    expect(find.text('Unlock all'), findsNothing);
    expect(apiCalls, 0);
  });

  testWidgets(
    'live board matches wardrobe image by stable id without changing layout',
    (tester) async {
      List<Map<String, dynamic>>? savedItems;
      final board = _board();
      board['title'] = 'Image audit board';
      final top = (board['board_items'] as List).first as Map<String, dynamic>;
      // Untrusted board image (raw original only, no cutout provenance) so the
      // wardrobe map's catalog image is the authoritative source.
      top.remove('masked_url');
      top.remove('transparent_url');
      top['image_url'] = 'https://example.test/original.jpg';

      await _pumpCard(
        tester,
        board: board,
        wardrobeById: {
          'anchor': {
            r'$id': 'anchor',
            'normalized_url': 'https://example.test/catalog_anchor.jpg',
          },
        },
        shuffleCall: (state) async => _success(state),
      );
      await tester.tap(find.byKey(const ValueKey<String>('lock-shoe-1')));
      await tester.pump();
      expect(find.text('2 of 3 items locked'), findsOneWidget);
      await _pumpCard(
        tester,
        board: board,
        wardrobeById: {
          'anchor': {
            r'$id': 'anchor',
            'normalized_url': 'https://example.test/catalog_anchor.jpg',
          },
        },
        shuffleCall: (state) async => _success(state),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              savedItems = items;
              return 'doc-1';
            },
      );
      expect(find.text('2 of 3 items locked'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save look'));
      await tester.pumpAndSettle();

      final savedTop = savedItems!.firstWhere(
        (item) => item['item_id'] == 'anchor',
      );
      expect(savedTop['image_url'], 'https://example.test/catalog_anchor.jpg');
      expect(savedTop['selected_field'], 'normalized_url');
      expect(savedTop['source_kind'], 'catalog_fallback');
      expect(savedTop['expected_transparent'], isFalse);
      expect(savedTop['position'], top['position']);
      expect(savedTop['item_id'], 'anchor');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('clearing an explicit wardrobe map removes stale images', (
    tester,
  ) async {
    List<Map<String, dynamic>>? savedItems;
    final board = _board()
      ..['title'] = 'Cleared wardrobe map regression'
      ..['style_archetype'] = 'Wardrobe clearing regression';
    await _pumpCard(
      tester,
      board: board,
      wardrobeById: {
        'anchor': {
          r'$id': 'anchor',
          'normalized_url': 'https://example.test/catalog_anchor.jpg',
        },
      },
      shuffleCall: (state) async => _success(state),
    );
    await _pumpCard(
      tester,
      board: board,
      shuffleCall: (state) async => _success(state),
      saveBoardOverride:
          ({
            required occasion,
            required outfitDescription,
            required imageUrl,
            required title,
            required itemIds,
            required items,
            required isFavourite,
          }) async {
            savedItems = items;
            return 'doc-1';
          },
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save look'));
    await tester.pumpAndSettle();

    final savedTop = savedItems!.firstWhere(
      (item) => item['item_id'] == 'anchor',
    );
    expect(
      savedTop['image_url'],
      isNot('https://example.test/catalog_anchor.jpg'),
    );
    // Stale catalog removed; item reverts to its own masked cutout.
    expect(
      savedTop['source_kind'],
      anyOf('validated_cutout', 'legacy_masked_cutout'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('actual chat parser preserves connected Build Outfit contract', (
    tester,
  ) async {
    final parsed = parseAhviResponse({
      'success': true,
      'route': 'build_outfit',
      'board_policy': 'allow',
      'style_boards': [_board()],
    });
    final block = parsed.blocks.singleWhere(
      (block) => block.type == AhviBlockType.visualDirections,
    );
    final directions = (block.data['directions'] as List)
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    expect(
      directions.single['board_id'],
      '11111111-1111-4111-8111-111111111111',
    );
    expect(directions.single['revision'], 1);
    expect(
      (directions.single['board_items'] as List).first['item_id'],
      'anchor',
    );

    await _pumpCard(
      tester,
      board: directions.single,
      shuffleCall: (state) async => _success(state),
    );
    expect(find.text('1 of 3 items locked'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
  });

  testWidgets('Save persists the current shuffled board items', (tester) async {
    List<Map<String, dynamic>>? savedItems;
    await _pumpCard(
      tester,
      board: _board(),
      shuffleCall: (state) async => _success(state),
      saveBoardOverride:
          ({
            required occasion,
            required outfitDescription,
            required imageUrl,
            required title,
            required itemIds,
            required items,
            required isFavourite,
          }) async {
            savedItems = items;
            return 'doc-1';
          },
    );

    await tester.tap(find.text('Shuffle unlocked pieces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save look'));
    await tester.pumpAndSettle();

    expect(savedItems, isNotNull);
    expect(savedItems!.map((item) => item['item_id']), [
      'anchor',
      'bottom-1-new',
      'shoe-1-new',
    ]);
  });

  testWidgets(
    'wardrobe board without positions keeps durable mutation shuffle',
    (tester) async {
      final board = _board();
      for (final item in (board['board_items'] as List).whereType<Map>()) {
        item.remove('position');
      }
      final sentMessages = <String>[];
      StyleBoardState? request;
      await _pumpCard(
        tester,
        board: board,
        onSendMessage: sentMessages.add,
        shuffleCall: (state) async {
          request = state.deepCopy();
          return StyleBoardShuffleResult(
            boardId: state.boardId,
            revision: 2,
            previousRevision: 1,
            lockedItemsPreserved: true,
            changedSlots: const ['bottom', 'footwear'],
            items: state.items,
            scenario: state.scenario,
            sourcePolicy: state.sourcePolicy,
          );
        },
      );

      expect(find.text('Shuffle unlocked pieces'), findsOneWidget);
      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pumpAndSettle();

      expect(sentMessages, isEmpty);
      expect(request!.boardId, '11111111-1111-4111-8111-111111111111');
      expect(request!.revision, 1);
      expect(request!.sourcePolicy, 'wardrobe');
      expect(request!.lockedItemIds, {'anchor'});

      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pumpAndSettle();
      expect(request!.revision, 2);
      expect(request!.sourcePolicy, 'wardrobe');
      expect(request!.lockedItemIds, {'anchor'});
      expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
    },
  );

  testWidgets('contract check logs the actual failed predicate', (
    tester,
  ) async {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      await _pumpCard(
        tester,
        board: _board(sourcePolicy: 'unknown'),
        shuffleCall: (state) async => _success(state),
      );

      final check = messages.singleWhere(
        (message) => message.startsWith('AHVI_BOARD_CONTRACT_CHECK'),
      );
      expect(check, contains('source_policy_ok=false'));
      expect(check, contains('can_lock=false'));
      expect(check, contains('can_shuffle=false'));
      expect(check, contains('failed_predicates=source_policy'));
      expect(find.textContaining('Shuffle'), findsNothing);
      final interaction = messages.singleWhere(
        (message) => message.startsWith('AHVI_BOARD_INTERACTION_MODE'),
      );
      expect(interaction, contains('mode=build_outfit'));
      expect(interaction, contains('lock=false'));
      expect(interaction, contains('shuffle=false'));
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  testWidgets('revision conflict rolls back and shows safe conflict message', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      board: _board(),
      shuffleCall: (_) async =>
          throw const StyleBoardApiException('BOARD_REVISION_CONFLICT'),
    );
    await tester.tap(find.text('Shuffle unlocked pieces'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('bottom-1')), findsOneWidget);
    expect(find.text('1 of 3 items locked'), findsOneWidget);
    expect(
      find.text('This board changed. Your current look has been preserved.'),
      findsOneWidget,
    );
  });

  testWidgets('loading keeps old items and affects only unlocked pieces', (
    tester,
  ) async {
    final pending = Completer<StyleBoardShuffleResult>();
    var calls = 0;
    await _pumpCard(
      tester,
      board: _board(),
      shuffleCall: (state) {
        calls++;
        return pending.future;
      },
    );

    await tester.tap(find.text('Shuffle unlocked pieces'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('bottom-1')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    // Mid-shuffle the control now reads the inline processing copy and is
    // disabled — tapping it must not fire a second request.
    expect(find.text('Refreshing unlocked pieces'), findsOneWidget);
    await tester.tap(
      find.text('Refreshing unlocked pieces'),
      warnIfMissed: false,
    );
    expect(calls, 1);

    pending.complete(_success(_requestWithAnchorLocked()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('bottom-1-new')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Undo shuffle'), findsOneWidget);
  });

  testWidgets(
    'mocked Build Outfit flow preserves two locks and supports undo',
    (tester) async {
      StyleBoardState? captured;
      await _pumpCard(
        tester,
        board: _board(),
        shuffleCall: (state) async {
          captured = state.deepCopy();
          return _success(state);
        },
      );

      await tester.tap(find.byKey(const ValueKey<String>('lock-shoe-1')));
      await tester.pump();
      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pumpAndSettle();

      expect(captured!.lockedItemIds, {'anchor', 'shoe-1'});
      final payload = const StyleBoardApiService().buildShufflePayload(
        board: captured!,
      );
      expect(
        (payload['locked_items'] as List).map((item) => item['item_id']),
        unorderedEquals(['anchor', 'shoe-1']),
      );
      expect(payload['shuffle_slots'], ['bottom']);
      expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shoe-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bottom-1-new')),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo shuffle'));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('bottom-1')), findsOneWidget);
      expect(find.text('2 of 3 items locked'), findsOneWidget);
      expect(find.text('Undo shuffle'), findsOneWidget);
    },
  );

  testWidgets('typed failure restores board and shows safe message', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      board: _board(),
      shuffleCall: (_) async =>
          throw const StyleBoardApiException('NO_REPLACEMENT_FOUND'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('lock-shoe-1')));
    await tester.pump();
    await tester.tap(find.text('Shuffle unlocked pieces'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('bottom-1')), findsOneWidget);
    expect(find.text('2 of 3 items locked'), findsOneWidget);
    expect(
      find.text('AHVI couldn’t find a stronger replacement right now.'),
      findsOneWidget,
    );
  });

  testWidgets('synthetic Style This shuffle fails locally with guidance', (
    tester,
  ) async {
    var calls = 0;
    await _pumpCard(
      tester,
      board: _board(
        boardId: 'style_this_anchor_0',
        scenario: 'style_this',
        sourcePolicy: 'style_asset',
      ),
      shuffleCall: (state) async {
        calls++;
        return _success(state);
      },
    );

    await tester.pumpAndSettle();

    // Synthetic (non-UUID) board is not backend-persisted: no shuffle control
    // is exposed at all. Lock UI still renders locally.
    expect(find.text('Shuffle unlocked pieces'), findsNothing);
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    expect(calls, 0);
    expect(find.text('1 of 3 items locked'), findsOneWidget);
  });

  testWidgets(
    'mocked connected Style This flow keeps style_asset policy end to end',
    (tester) async {
      final board = _board(
        boardId: '22222222-2222-4222-8222-222222222222',
        scenario: 'style_this',
        sourcePolicy: 'style_asset',
      );
      // Completion pieces on a Style This board are curated style assets;
      // only the anchor is wardrobe-owned.
      for (final item in (board['board_items'] as List).skip(1)) {
        (item as Map)['source'] = 'style_asset';
      }
      StyleBoardState? captured;
      await _pumpCard(
        tester,
        board: board,
        shuffleCall: (state) async {
          captured = state.deepCopy();
          final items = state.items.map((item) {
            if (state.lockedItemIds.contains(item.itemId)) return item;
            return StyleBoardItem.fromJson({
              ..._item('${item.itemId}-new', item.slot, x: item.position!.x!),
              'source': 'style_asset',
            });
          }).toList();
          return StyleBoardShuffleResult(
            boardId: state.boardId,
            revision: state.revision + 1,
            previousRevision: state.revision,
            lockedItemsPreserved: true,
            changedSlots: const ['bottom', 'footwear'],
            items: items,
            scenario: 'style_this',
            sourcePolicy: 'style_asset',
          );
        },
      );

      // 1-3: parsed real Style This board with policy, anchor-only lock.
      expect(find.text('1 of 3 items locked'), findsOneWidget);
      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pumpAndSettle();

      // 5: request sends the explicit policy.
      final payload = const StyleBoardApiService().buildShufflePayload(
        board: captured!,
      );
      // Request always sends 'inherit'; the board's own style_asset policy is
      // preserved in state (asserted below), not echoed into the request.
      expect(payload['source_policy'], 'inherit');
      expect(captured!.lockedItemIds, {'anchor'});

      // 7-9: response accepted, revision advanced, policy preserved.
      expect(find.byKey(const ValueKey<String>('anchor')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bottom-1-new')),
        findsOneWidget,
      );
    },
  );

  testWidgets('legacy board renders without mutation controls', (tester) async {
    await _pumpCard(
      tester,
      board: {
        'title': 'Legacy look',
        'board_items': [
          _item('', 'top'),
          _item('', 'bottom'),
          _item('', 'footwear'),
        ],
      },
      shuffleCall: (state) async => _success(state),
    );
    expect(find.text('Shuffle unlocked pieces'), findsNothing);
    expect(find.text('0 of 3 items locked'), findsNothing);
    expect(find.textContaining('Shuffle'), findsNothing);
  });

  testWidgets(
    'same board rebuild preserves locks and disposal ignores response',
    (tester) async {
      final pending = Completer<StyleBoardShuffleResult>();
      final board = _board();
      await _pumpCard(tester, board: board, shuffleCall: (_) => pending.future);
      await tester.tap(find.byKey(const ValueKey<String>('lock-shoe-1')));
      await tester.pump();
      await _pumpCard(
        tester,
        board: Map<String, dynamic>.from(board),
        shuffleCall: (_) => pending.future,
      );
      expect(find.text('2 of 3 items locked'), findsOneWidget);

      await tester.tap(find.text('Shuffle unlocked pieces'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      pending.complete(_success(_requestWithAnchorLocked()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

StyleBoardState _requestWithAnchorLocked() => StyleBoardState(
  boardId: '11111111-1111-4111-8111-111111111111',
  revision: 1,
  items: (_board()['board_items'] as List)
      .whereType<Map>()
      .map((item) => StyleBoardItem.fromJson(Map<String, dynamic>.from(item)))
      .toList(),
  lockedItemIds: const {'anchor'},
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required Map<String, dynamic> board,
  required Future<StyleBoardShuffleResult> Function(StyleBoardState)
  shuffleCall,
  ValueChanged<String>? onSendMessage,
  BoardSaveFn? saveBoardOverride,
  OutfitBoardStateChanged? onBoardStateChanged,
  Map<String, Map<String, dynamic>> wardrobeById = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: Scaffold(
        body: Center(
          child: AhviOutfitBoardCard(
            direction: board,
            width: 390,
            onSendMessage: onSendMessage ?? (_) {},
            shuffleCall: shuffleCall,
            saveBoardOverride: saveBoardOverride,
            onBoardStateChanged: onBoardStateChanged,
            wardrobeById: wardrobeById,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
