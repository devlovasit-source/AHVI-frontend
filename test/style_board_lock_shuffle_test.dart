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

StyleBoardState boardState({Set<String> locked = const {}}) => StyleBoardState(
  boardId: 'board_123',
  revision: 1,
  items: [
    'top',
    'bottom',
    'footwear',
  ].map((slot) => StyleBoardItem.fromJson(itemJson(slot, slot))).toList(),
  lockedItemIds: locked,
);

StyleBoardShuffleResult success(StyleBoardState board) =>
    StyleBoardShuffleResult(
      boardId: board.boardId,
      revision: board.revision + 1,
      previousRevision: board.revision,
      lockedItemsPreserved: true,
      changedSlots: const ['bottom'],
      items: board.items,
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
