// The Samsung case: backend returned weak_occasion_match, items had image_url
// but blank cutout_status / board_status, no board contract, and the transparent
// renderer rejected every image. The carousel must STILL route through the single
// authoritative AhviOutfitBoardCard + OutfitActionBar (Appwrite Save, native
// Share) — never a second Save/Share implementation and never a bare fallback
// with no actions. Tests go through VisualDirectionCarousel, not OutfitActionBar
// directly.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/profile_theme.dart';

final ThemeData _theme = ThemeData(
  extensions: <ThemeExtension<dynamic>>[
    AppThemeTokens.light(getAccentPalette(ProfileTheme.coolBlue)),
  ],
);

// weak_occasion_match, items present with image_url, blank cutout/board status,
// NO board contract, nothing renderable by the transparent filter.
Map<String, dynamic> _samsungDirection() => {
      'response_type': 'weak_occasion_match',
      'occasion': 'office',
      'direction_name': 'Understated Ease',
      'why_it_works': 'Clean lines, quiet colour.',
      'board_items': [
        {'name': 'White shirt', 'item_id': 'shirt-1', 'role': 'top', 'slot': 'top', 'image_url': 'https://x/shirt.png', 'cutout_status': '', 'board_status': ''},
        {'name': 'Navy chinos', 'item_id': 'chino-1', 'role': 'bottom', 'slot': 'bottom', 'image_url': 'https://x/chino.png', 'cutout_status': '', 'board_status': ''},
        {'name': 'Brown loafers', 'item_id': 'loafer-1', 'role': 'footwear', 'slot': 'footwear', 'image_url': 'https://x/loafer.png', 'cutout_status': '', 'board_status': ''},
        {'name': 'Leather belt', 'item_id': 'belt-1', 'role': 'accessory', 'slot': 'accessory', 'image_url': 'https://x/belt.png', 'cutout_status': '', 'board_status': ''},
      ],
    };

// Capture debugPrint for the duration of [body] only, restoring it BEFORE the
// test function returns (the test framework flags any foundation debug var left
// changed past the body).
Future<List<String>> _withLogs(Future<void> Function(List<String>) body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
  try {
    await body(logs);
  } finally {
    debugPrint = original;
  }
  return logs;
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> direction) =>
    tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(
          body: VisualDirectionCarousel(
            directions: [direction],
            cardWidth: 340,
            curationReveal: false,
            editorialCover: const {},
            onSendMessage: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('weak_occasion_match with no renderable assets still uses AhviOutfitBoardCard', (tester) async {
    final logs = await _withLogs((logs) async {
      await _pump(tester, _samsungDirection());
      await tester.pump();
    });

    // 1. authoritative card selected.
    expect(find.byType(AhviOutfitBoardCard), findsOneWidget);
    // 2. rendered safely (fallback visual, no crash).
    expect(tester.takeException(), isNull);
    // route instrumentation.
    expect(
      logs.any((l) =>
          l.contains('AHVI_STYLE_CARD_PATH path=outfit_board') &&
          l.contains('underlying_item_count=4')),
      isTrue,
    );

    // 3 & 6. Save + Share visible.
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    // 5. underlying payload reached the authoritative card.
    final card = tester.widget<AhviOutfitBoardCard>(find.byType(AhviOutfitBoardCard));
    expect((card.direction['board_items'] as List).length, 4);

    // 10. Lock/Shuffle disabled without a contract.
    expect(find.text('Shuffle unlocked pieces'), findsNothing);
  });

  testWidgets('Save tap invokes the authoritative Appwrite handler path', (tester) async {
    final logs = await _withLogs((logs) async {
      await _pump(tester, _samsungDirection());
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();
    });

    // 4 & 9. Authoritative handler entered; legacy feedback-only Save is gone.
    expect(logs.contains('AHVI_BOARD_ACTION_TAP action=save surface=outfit_board'), isTrue);
    expect(logs.contains('AHVI_BOARD_SAVE_TAP'), isTrue);
    // No leftover legacy save log.
    expect(logs.any((l) => l.contains('Saved to Style Boards')), isFalse);
  });

  testWidgets('Share tap invokes the real handler and falls back on capture failure', (tester) async {
    final logs = await _withLogs((logs) async {
      await _pump(tester, _samsungDirection());
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
    });
    tester.takeException(); // consume platform-channel share exception in test env

    // 7. The real image-share handler ran (capture path entered), not a legacy
    // feedback-only stub. Capture-failure -> text fallback is proven with an
    // injected captureOverride in outfit_board_save_share_test.dart.
    expect(logs.contains('AHVI_BOARD_ACTION_TAP action=share surface=outfit_board'), isTrue);
    expect(logs.contains('AHVI_BOARD_SHARE_TAP'), isTrue);
    expect(logs.contains('AHVI_BOARD_SHARE_CAPTURE_START'), isTrue);
  });

  testWidgets('a normal transparent board keeps using the board card too', (tester) async {
    await _withLogs((logs) async {
      final normal = _samsungDirection();
      normal['response_type'] = 'style_boards';
      for (final item in (normal['board_items'] as List)) {
        (item as Map)['board_image_url'] = item['image_url'];
        item['board_status'] = 'cutout_ready';
      }
      await _pump(tester, normal);
      await tester.pump();
    });
    expect(find.byType(AhviOutfitBoardCard), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
