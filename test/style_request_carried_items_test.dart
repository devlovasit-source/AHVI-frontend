// The device blocker: board contract + stable wardrobe IDs parsed fine, but
// request_carried_items_ok=false kept Lock/Shuffle disabled. Cause: items whose
// raw board_items entry misses (or carries no per-item source) were built with
// source='unknown' / raw={}. The card now reconstructs the request-carried
// payload from the canonical parsed items (board source_policy=wardrobe => the
// items are wardrobe items). No fabricated IDs: id-less items stay ineligible.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/profile_theme.dart';

final ThemeData _theme = ThemeData(
  extensions: <ThemeExtension<dynamic>>[
    AppThemeTokens.light(getAccentPalette(ProfileTheme.coolBlue)),
  ],
);

Map<String, dynamic> _boardItem(String id, String slot, {bool source = false}) => {
      'item_id': id,
      'name': id,
      'slot': slot,
      'role': slot,
      'image_url': 'https://x/$id.png',
      // Renderable transparent asset (as the deployed backend sends).
      'board_image_url': 'https://x/$id.png',
      // Device case: backend board_items carried NO per-item source field.
      if (source) 'source': 'wardrobe',
    };

Map<String, dynamic> _officeDirection({String sourcePolicy = 'wardrobe'}) => {
      'board_id': 'board_67acadea9420',
      'revision': 1,
      'source_policy': sourcePolicy,
      'occasion': 'office',
      'direction_name': 'Composed Authority',
      'board_items': [
        _boardItem('w-top-1', 'top'),
        _boardItem('w-bottom-1', 'bottom'),
        _boardItem('w-shoe-1', 'footwear'),
        _boardItem('w-belt-1', 'accessory'),
      ],
    };

Future<List<String>> _pumpAndCapture(
  WidgetTester tester,
  Map<String, dynamic> direction,
) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  try {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AhviOutfitBoardCard(
              direction: direction,
              width: 340,
              onSendMessage: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    debugPrint = original;
  }
  return logs;
}

String? _contractLine(List<String> logs) {
  for (final l in logs) {
    if (l.contains('AHVI_BOARD_CONTRACT_CHECK')) return l;
  }
  return null;
}

void main() {
  testWidgets('office wardrobe board without per-item source becomes shuffle-eligible', (tester) async {
    final logs = await _pumpAndCapture(tester, _officeDirection());
    final line = _contractLine(logs);
    expect(line, isNotNull);
    expect(line, contains('request_carried_items_ok=true'));
    expect(line, contains('can_lock=true'));
    expect(line, contains('can_shuffle=true'));
    expect(line, contains('request_carried_source=canonical_reconstruction'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-wardrobe policy without item source stays ineligible', (tester) async {
    // No honest source fallback -> Shuffle must remain disabled, never guessed.
    final logs = await _pumpAndCapture(
      tester,
      _officeDirection(sourcePolicy: 'daily'),
    );
    final line = _contractLine(logs);
    expect(line, isNotNull);
    expect(line, contains('request_carried_items_ok=false'));
    expect(line, contains('can_shuffle=false'));
  });

  test('state predicate: reconstructed wardrobe items pass, id-less items fail', () {
    StyleBoardItem item({String id = 'w-1', String source = 'wardrobe', Map<String, dynamic>? raw}) =>
        StyleBoardItem(
          id: id,
          name: 'x',
          imageUrl: 'https://x/x.png',
          category: 'top',
          role: BoardItemRole.top,
          source: source,
          raw: raw ?? {'item_id': id, 'source': source},
        );
    final ok = StyleBoardState(
      boardId: 'board_abc',
      revision: 1,
      sourcePolicy: 'wardrobe',
      items: [item()],
    );
    expect(ok.requestCarriedItemsOk, isTrue);
    final noRaw = StyleBoardState(
      boardId: 'board_abc',
      revision: 1,
      sourcePolicy: 'wardrobe',
      items: [item(raw: const {})],
    );
    expect(noRaw.requestCarriedItemsOk, isFalse);
    // Transient board id remains invalid regardless of items.
    final transient = StyleBoardState(
      boardId: 'outfit_card_1',
      revision: 1,
      sourcePolicy: 'wardrobe',
      items: [item()],
    );
    expect(transient.canShuffle, isFalse);
  });
}
