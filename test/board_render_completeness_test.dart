import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/board_render_completeness.dart';
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

StyleBoardItem _item(String slot, {String img = 'https://x/i.png', bool primaryOuter = false}) =>
    StyleBoardItem.fromJson({
      'item_id': '$slot-1',
      'slot': slot,
      'name': slot,
      'image_url': img,
      if (primaryOuter) 'primary_outerwear': true,
    });

Map<String, dynamic> _direction(List<String> slots) => {
      'title': slots.join('+'),
      'occasion': 'party',
      'board_items': [
        for (final s in slots)
          {
            'item_id': '$s-1',
            'slot': s,
            'role': s,
            'name': s,
            // Transparent cutout so the card's image-resolution keeps the item
            // (the completeness guard runs on the FINAL rendered set).
            'image_url': 'https://x/$s.png',
            'transparent_image_url': 'https://x/$s.png',
            'board_image_url': 'https://x/$s.png',
            'board_status': 'cutout_ready',
          },
      ],
    };

void main() {
  test('1. top+bottom+footwear passes (separates)', () {
    final r = evaluateRenderCompleteness([_item('top'), _item('bottom'), _item('footwear')]);
    expect(r.complete, isTrue);
    expect(r.structure, 'separates');
  });

  test('2. top+bottom+footwear+accessory passes', () {
    final r = evaluateRenderCompleteness(
        [_item('top'), _item('bottom'), _item('footwear'), _item('accessory')]);
    expect(r.complete, isTrue);
  });

  test('3. dress+footwear passes without a bottom (one-piece)', () {
    final r = evaluateRenderCompleteness([_item('dress'), _item('footwear')]);
    expect(r.complete, isTrue);
    expect(r.structure, 'one_piece');
  });

  test('4. jumpsuit+footwear passes (one-piece)', () {
    final r = evaluateRenderCompleteness([_item('jumpsuit'), _item('footwear')]);
    expect(r.complete, isTrue);
    expect(r.structure, 'one_piece');
  });

  test('5. bottom+footwear+accessory fails (missing top)', () {
    final r = evaluateRenderCompleteness([_item('bottom'), _item('footwear'), _item('accessory')]);
    expect(r.complete, isFalse);
    expect(r.reason, contains('top'));
  });

  test('6. outerwear+bottom+footwear fails unless primary_outerwear', () {
    final r = evaluateRenderCompleteness([_item('outerwear'), _item('bottom'), _item('footwear')]);
    expect(r.complete, isFalse);
  });

  test('7. primary outerwear+bottom+footwear passes', () {
    final r = evaluateRenderCompleteness(
        [_item('outerwear', primaryOuter: true), _item('bottom'), _item('footwear')]);
    expect(r.complete, isTrue);
    expect(r.structure, 'separates');
  });

  test('8. scarf/gloves + bottom + footwear fails', () {
    final r = evaluateRenderCompleteness([_item('scarf'), _item('gloves'), _item('bottom'), _item('footwear')]);
    expect(r.complete, isFalse);
    expect(r.reason, contains('top'));
  });

  test('9. item with no renderable image is excluded before validation', () {
    // The top has no image -> excluded -> board reads as bottom+footwear only.
    final r = evaluateRenderCompleteness([_item('top', img: ''), _item('bottom'), _item('footwear')]);
    expect(r.complete, isFalse);
    expect(r.reason, contains('top'));
  });

  test('12. rendered completeness ignores backend completeness flags', () {
    // Even if a direction claims completeness, the RENDERED items decide.
    final direction = {
      ..._direction(['bottom', 'footwear', 'accessory']),
      'completeness': true,
      'constraint_status': {'final_validation_status': 'passed'},
    };
    final r = boardCompletenessForDirection(direction);
    expect(r.complete, isFalse);
  });

  testWidgets('10. invalid board is skipped while a valid sibling remains', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: _theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VisualDirectionCarousel(
            directions: [
              _direction(['top', 'bottom', 'footwear']), // valid
              _direction(['bottom', 'footwear', 'accessory']), // invalid
            ],
            curationReveal: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    tester.takeException(); // ignore collage layout/network-image noise
    // Not all-rejected: the fallback message must NOT appear.
    expect(find.textContaining('could not build a complete outfit'), findsNothing);
  });

  testWidgets('11. all-invalid response shows the fallback and no outfit visual', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: _theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VisualDirectionCarousel(
            directions: [
              _direction(['bottom', 'footwear', 'accessory']),
              _direction(['footwear', 'accessory']),
            ],
            curationReveal: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    tester.takeException();
    expect(find.textContaining('could not build a complete outfit'), findsOneWidget);
  });
}
