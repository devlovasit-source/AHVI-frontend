import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

const _accent = AccentPalette(
  primary: Color(0xFF6B91FF),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  testWidgets('partial resolved board uses canvas while enrichment arrives', (
    tester,
  ) async {
    await _pumpCard(tester, _direction(1));

    expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
    expect(
      tester
          .widget<AhviUnifiedOutfitGrid>(find.byType(AhviUnifiedOutfitGrid))
          .items,
      hasLength(1),
    );

    await _pumpCard(tester, _direction(3));
    await tester.pump();

    expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
    expect(
      tester
          .widget<AhviUnifiedOutfitGrid>(find.byType(AhviUnifiedOutfitGrid))
          .items,
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolved three and five item boards keep premium canvas path', (
    tester,
  ) async {
    for (final count in [3, 5]) {
      await _pumpCard(tester, _direction(count));
      expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
      expect(
        tester
            .widget<AhviUnifiedOutfitGrid>(find.byType(AhviUnifiedOutfitGrid))
            .items,
        hasLength(count),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('carousel count uses resolver fields and rejects raw-only URLs', (
    tester,
  ) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      final direction = _direction(3);
      final items = direction['board_items'] as List<Map<String, dynamic>>;
      items[0]
        ..remove('normalized_url')
        ..['masked_url'] = 'https://example.test/top-cutout.png';
      items[1]
        ..remove('normalized_url')
        ..['image_url'] = 'https://example.test/person-upload.jpg';

      await tester.pumpWidget(
        _app(
          VisualDirectionCarousel(
            directions: [direction],
            cardWidth: 340,
            curationReveal: false,
          ),
        ),
      );
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      logs.any(
        (line) =>
            line.contains('AHVI_STYLE_CARD_PATH') &&
            line.contains('renderable_asset_count=2'),
      ),
      isTrue,
    );
  });
}

Future<void> _pumpCard(WidgetTester tester, Map<String, dynamic> direction) {
  return tester.pumpWidget(
    _app(
      AhviOutfitBoardCard(
        key: const ValueKey('eligibility-board'),
        direction: direction,
        width: 352,
      ),
    ),
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> _direction(int count) {
  const roles = ['bottom', 'top', 'footwear', 'accessory', 'accessory'];
  return {
    'board_id': 'resolved-eligibility-board',
    'revision': 1,
    'source_policy': 'wardrobe',
    'title': 'Modern Romantic',
    'why_it_works': 'Balanced color and proportion.',
    'board_items': <Map<String, dynamic>>[
      for (var index = 0; index < count; index++)
        {
          'item_id': 'item-$index',
          'name': 'Item $index',
          'role': roles[index],
          'slot': roles[index],
          'source': 'wardrobe',
          'image_url': 'https://example.test/original-$index.jpg',
          'normalized_url': 'https://example.test/catalog_item-$index.jpg',
        },
    ],
  };
}
