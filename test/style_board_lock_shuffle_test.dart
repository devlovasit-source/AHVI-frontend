import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_controller.dart';
import 'package:myapp/style_board/style_board_state.dart';

Map<String, dynamic> itemJson(String id, String slot, {bool locked = false}) =>
    {
      'item_id': id,
      'name': 'Same name',
      'slot': slot,
      'role': slot,
      'source': 'wardrobe',
      'image_url': 'https://example.test/$id.png',
      'board_image_url': 'https://example.test/$id-board.png',
      'locked': locked,
      'position': {
        'x': .1,
        'y': .2,
        'width': .3,
        'height': .4,
        'scale': 1,
        'rotation': 2,
        'z': 3,
      },
    };

StyleBoardState boardState({
  Set<String> locked = const {},
  String scenario = '',
  String sourcePolicy = '',
  bool allowWardrobeFallback = false,
}) => StyleBoardState(
  boardId: 'board_123',
  revision: 1,
  scenario: scenario,
  sourcePolicy: sourcePolicy,
  allowWardrobeFallback: allowWardrobeFallback,
  items: [
    'top',
    'bottom',
    'footwear',
  ].map((slot) => StyleBoardItem.fromJson(itemJson(slot, slot))).toList(),
  lockedItemIds: locked,
);

StyleBoardShuffleResult success(
  StyleBoardState board, {
  String scenario = '',
  String sourcePolicy = '',
  List<StyleBoardItem>? items,
}) => StyleBoardShuffleResult(
  boardId: board.boardId,
  revision: board.revision + 1,
  previousRevision: board.revision,
  lockedItemsPreserved: true,
  changedSlots: const ['bottom'],
  items: items ?? board.items,
  scenario: scenario,
  sourcePolicy: sourcePolicy,
);

void main() {
  group('canonical item parsing', () {
    test('uses backend identity priority and never name', () {
      final item = StyleBoardItem.fromJson({
        ...itemJson('canonical', 'top'),
        'id': 'secondary',
        r'$id': 'third',
      });
      expect(item.itemId, 'canonical');
      expect(
        StyleBoardItem.fromJson({'name': 'No ID', 'role': 'top'}).itemId,
        isEmpty,
      );
    });

    test(r'accepts $id and complete contract fields', () {
      final item = StyleBoardItem.fromJson({
        ...itemJson('', 'accessory'),
        'item_id': '',
        r'$id': 'appwrite-id',
        'board_role': 'hero',
        'accessory_type': 'watch',
        'sub_category': 'Watches',
      });
      expect(item.itemId, 'appwrite-id');
      expect(item.source, 'wardrobe');
      expect(item.slot, 'accessory');
      expect(item.boardRole, 'hero');
      expect(item.accessoryType, 'watch');
      expect(item.position!.toJson(), containsPair('rotation', 2.0));
    });

    test('accepts wardrobe item identity aliases', () {
      final snake = StyleBoardItem.fromJson({
        ...itemJson('', 'top'),
        'item_id': '',
        'wardrobe_item_id': 'wardrobe-snake',
      });
      final camel = StyleBoardItem.fromJson({
        ...itemJson('', 'bottom'),
        'item_id': '',
        'wardrobeItemId': 'wardrobe-camel',
      });

      expect(snake.itemId, 'wardrobe-snake');
      expect(camel.itemId, 'wardrobe-camel');
    });

    test('legacy item remains displayable but cannot lock', () {
      final item = StyleBoardItem.fromJson({
        'name': 'Legacy',
        'image_url': 'legacy.png',
      });
      expect(item.name, 'Legacy');
      expect(item.isLockable, isFalse);
    });
  });

  test(
    'request preserves locked payload and derives unique unlocked slots',
    () {
      const api = StyleBoardApiService();
      final payload = api.buildShufflePayload(
        board: boardState(locked: {'top'}),
      );
      expect(payload, isNot(contains('board_id')));
      expect(payload['revision'], 1);
      expect(payload['source_policy'], 'inherit');
      expect(payload['shuffle_slots'], unorderedEquals(['bottom', 'footwear']));
      final locked = (payload['locked_items'] as List).single as Map;
      expect(locked['item_id'], 'top');
      expect(locked['position'], containsPair('x', .1));
      expect(payload['board_items'], hasLength(3));
    },
  );

  group('board controller', () {
    test('locks multiple distinct IDs and unlocks individually/all', () {
      final controller = StyleBoardController(
        initialState: boardState(),
        shuffleCall: (board) async => success(board),
      );
      controller.toggleLock('top');
      controller.toggleLock('bottom');
      expect(controller.state.lockedItemIds, {'top', 'bottom'});
      controller.toggleLock('top');
      expect(controller.state.lockedItemIds, {'bottom'});
      controller.unlockAll();
      expect(controller.state.lockedItemIds, isEmpty);
    });

    test(
      'loading affects only unlocked items and duplicate request is prevented',
      () async {
        final pending = Completer<StyleBoardShuffleResult>();
        var calls = 0;
        final controller = StyleBoardController(
          initialState: boardState(locked: {'top'}),
          shuffleCall: (board) {
            calls++;
            return pending.future;
          },
        );
        final first = controller.shuffle();
        await controller.shuffle();
        expect(calls, 1);
        expect(
          controller.state.items
              .singleWhere((item) => item.itemId == 'top')
              .isRegenerating,
          isFalse,
        );
        expect(
          controller.state.items
              .singleWhere((item) => item.itemId == 'bottom')
              .isRegenerating,
          isTrue,
        );
        pending.complete(success(boardState(locked: {'top'})));
        await first;
      },
    );

    test('accessory subtype stays in items but shuffle slot is canonical', () {
      const api = StyleBoardApiService();
      final accessory = StyleBoardItem.fromJson({
        ...itemJson('bag-1', 'accessory'),
        'accessory_type': 'bag',
      });
      final payload = api.buildShufflePayload(
        board: StyleBoardState(
          boardId: 'board-123',
          revision: 1,
          items: [accessory],
        ),
      );
      expect(payload['shuffle_slots'], ['accessory']);
      expect((payload['board_items'] as List).single['accessory_type'], 'bag');
    });

    test('typed failure restores exact snapshot', () async {
      final initial = boardState(locked: {'top'});
      final controller = StyleBoardController(
        initialState: initial,
        shuffleCall: (_) async =>
            throw const StyleBoardApiException('NO_REPLACEMENT_FOUND'),
      );
      expect(await controller.shuffle(), 'NO_REPLACEMENT_FOUND');
      expect(controller.state.revision, initial.revision);
      expect(controller.state.lockedItemIds, initial.lockedItemIds);
      expect(
        controller.state.items.map((item) => item.itemId),
        initial.items.map((item) => item.itemId),
      );
    });

    test('legacy board without explicit policy cannot shuffle', () {
      expect(boardState().supportsShuffle, isFalse);
      expect(
        boardState(sourcePolicy: 'style_asset').supportsShuffle,
        isTrue,
      );
    });

    test('wardrobe contract remains durable without backend positions', () {
      final items = ['top', 'bottom', 'footwear']
          .map(
            (slot) => StyleBoardItem.fromJson({
              ...itemJson(slot, slot)..remove('position'),
            }),
          )
          .toList();
      final state = StyleBoardState(
        boardId: 'board_b2fe1847ee39',
        revision: 1,
        sourcePolicy: 'wardrobe',
        items: items,
      );

      expect(state.positionsOk, isFalse);
      expect(state.canLock, isTrue);
      expect(state.canShuffle, isTrue);
      expect(state.failedContractPredicates, isEmpty);
    });

    test('unknown policy identifies the exact failed predicate', () {
      final state = boardState(sourcePolicy: 'unknown');

      expect(state.canShuffle, isFalse);
      expect(state.failedContractPredicates, ['source_policy']);
    });

    test('transient outfit card id is not a durable board id', () {
      final state = StyleBoardState(
        boardId: 'outfit_card_123',
        revision: 1,
        sourcePolicy: 'wardrobe',
        items: boardState(sourcePolicy: 'wardrobe').items,
      );

      expect(state.boardIdOk, isFalse);
      expect(state.canShuffle, isFalse);
      expect(state.failedContractPredicates, ['board_id']);
    });

    test('shuffle request sends the explicit board policy', () {
      const api = StyleBoardApiService();
      final styleThis = api.buildShufflePayload(
        board: boardState(
          scenario: 'style_this',
          sourcePolicy: 'style_asset',
          locked: {'top'},
        ),
      );
      expect(styleThis['source_policy'], 'style_asset');
      expect(styleThis.containsKey('allow_wardrobe_fallback'), isFalse);

      final buildOutfit = api.buildShufflePayload(
        board: boardState(scenario: 'build_outfit', sourcePolicy: 'wardrobe'),
      );
      expect(buildOutfit['source_policy'], 'wardrobe');

      final mixed = api.buildShufflePayload(
        board: boardState(
          sourcePolicy: 'mixed',
          allowWardrobeFallback: true,
        ),
      );
      expect(mixed['source_policy'], 'mixed');
      expect(mixed['allow_wardrobe_fallback'], isTrue);
    });

    test('controller preserves policy through success, rollback and undo',
        () async {
      final initial = boardState(
        scenario: 'style_this',
        sourcePolicy: 'style_asset',
        locked: {'top'},
      );
      var fail = false;
      final controller = StyleBoardController(
        initialState: initial,
        shuffleCall: (board) async {
          if (fail) throw const StyleBoardApiException('NO_REPLACEMENT_FOUND');
          final replacements = board.items
              .map(
                (item) => board.lockedItemIds.contains(item.itemId)
                    ? item
                    : StyleBoardItem.fromJson({
                        ...itemJson('${item.itemId}-new', item.slot),
                        'source': 'style_asset',
                      }),
              )
              .toList();
          return success(
            board,
            scenario: 'style_this',
            sourcePolicy: 'style_asset',
            items: replacements,
          );
        },
      );
      expect(await controller.shuffle(), isNull);
      expect(controller.state.sourcePolicy, 'style_asset');
      expect(controller.state.scenario, 'style_this');
      fail = true;
      expect(await controller.shuffle(), 'NO_REPLACEMENT_FOUND');
      expect(controller.state.sourcePolicy, 'style_asset');
      controller.undo();
      expect(controller.state.sourcePolicy, 'style_asset');
      expect(controller.state.revision, initial.revision);
    });

    test('conflicting response policy is rejected and board restored',
        () async {
      final initial = boardState(
        scenario: 'style_this',
        sourcePolicy: 'style_asset',
        locked: {'top'},
      );
      final controller = StyleBoardController(
        initialState: initial,
        shuffleCall: (board) async =>
            success(board, sourcePolicy: 'wardrobe'),
      );
      expect(await controller.shuffle(), 'SOURCE_POLICY_CHANGED');
      expect(controller.state.revision, initial.revision);
      expect(controller.state.sourcePolicy, 'style_asset');
    });

    test('wardrobe completion under style_asset policy is rejected',
        () async {
      final initial = boardState(
        sourcePolicy: 'style_asset',
        locked: {'top'},
      );
      final controller = StyleBoardController(
        initialState: initial,
        // itemJson source is 'wardrobe': unlocked bottom/footwear violate.
        shuffleCall: (board) async =>
            success(board, sourcePolicy: 'style_asset'),
      );
      expect(await controller.shuffle(), 'SOURCE_POLICY_VIOLATION');
      expect(controller.state.revision, initial.revision);
    });

    test('locked wardrobe anchor is valid inside a style_asset board',
        () async {
      final initial = boardState(
        sourcePolicy: 'style_asset',
        locked: {'top'},
      );
      final controller = StyleBoardController(
        initialState: initial,
        shuffleCall: (board) async => success(
          board,
          sourcePolicy: 'style_asset',
          items: board.items
              .map(
                (item) => item.itemId == 'top'
                    ? item
                    : StyleBoardItem.fromJson({
                        ...itemJson('${item.itemId}-new', item.slot),
                        'source': 'style_asset',
                      }),
              )
              .toList(),
        ),
      );
      expect(await controller.shuffle(), isNull);
      expect(controller.state.revision, 2);
      expect(
        controller.state.items
            .singleWhere((item) => item.itemId == 'top')
            .source,
        'wardrobe',
      );
    });

    test(
      'success increments revision, records exclusions, and supports local undo',
      () async {
        final initial = boardState(locked: {'top'});
        final controller = StyleBoardController(
          initialState: initial,
          shuffleCall: (board) async => success(board),
        );
        expect(await controller.shuffle(), isNull);
        expect(controller.state.revision, 2);
        expect(
          controller.state.excludedItemIds,
          containsAll(['bottom', 'footwear']),
        );
        expect(controller.canUndo, isTrue);
        controller.undo();
        expect(controller.state.revision, 1);
        expect(controller.state.lockedItemIds, {'top'});
      },
    );
  });
}
