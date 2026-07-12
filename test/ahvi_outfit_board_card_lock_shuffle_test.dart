import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  'board_image_url': 'https://example.test/$id.png',
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

Map<String, dynamic> _board({String boardId = 'board-1', int revision = 1}) => {
  'board_id': boardId,
  'revision': revision,
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('actual chat parser preserves connected Build Outfit contract', (
    tester,
  ) async {
    final parsed = parseAhviResponse({
      'success': true,
      'style_boards': [_board()],
    });
    final block = parsed.blocks.singleWhere(
      (block) => block.type == AhviBlockType.visualDirections,
    );
    final directions = (block.data['directions'] as List)
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    expect(directions.single['board_id'], 'board-1');
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

    await tester.tap(find.text('Shuffle unlocked pieces'), warnIfMissed: false);
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
      expect(find.text('Undo shuffle'), findsNothing);
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
    expect(find.text('Shuffle'), findsOneWidget);
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
  boardId: 'board-1',
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
            onSendMessage: (_) {},
            shuffleCall: shuffleCall,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
