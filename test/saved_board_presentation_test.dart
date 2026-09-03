import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/saved_board_card.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  testWidgets('saved board title stays above the canonical canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 300,
            height: 520,
            child: SavedBoardCard(
              source: {
                'title': 'Refined Ease',
                'occasion': 'Work',
                'description': 'Balanced tailoring for a polished day.',
                'items': [
                  {
                    'item_id': 'top-1',
                    'name': 'Shirt',
                    'role': 'top',
                    'image_url': 'https://example.test/top.png',
                    'masked_url': 'https://example.test/top-cutout.png',
                  },
                  {
                    'item_id': 'bottom-1',
                    'name': 'Trousers',
                    'role': 'bottom',
                    'image_url': 'https://example.test/bottom.png',
                    'masked_url': 'https://example.test/bottom-cutout.png',
                  },
                  {
                    'item_id': 'shoe-1',
                    'name': 'Loafers',
                    'role': 'footwear',
                    'image_url': 'https://example.test/shoe.png',
                    'masked_url': 'https://example.test/shoe-cutout.png',
                  },
                ],
              },
              wardrobeById: {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = find.byKey(const ValueKey('saved-board-title'));
    final canvas = find.byKey(const ValueKey('saved-board-canvas'));
    expect(title, findsOneWidget);
    expect(canvas, findsOneWidget);
    expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
    expect(tester.getTopLeft(title).dy, lessThan(tester.getTopLeft(canvas).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved board hides the Try On CTA without a callback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 300,
            height: 520,
            child: SavedBoardCard(
              source: {
                'title': 'Refined Ease',
                'occasion': 'Work',
                'description': 'Balanced tailoring for a polished day.',
                'items': [
                  {
                    'item_id': 'top-1',
                    'name': 'Shirt',
                    'role': 'top',
                    'image_url': 'https://example.test/top.png',
                    'masked_url': 'https://example.test/top-cutout.png',
                  },
                ],
              },
              wardrobeById: {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Regression: a 2-column saved-boards grid (childAspectRatio 0.54, as used
  // by everything_else.dart/party_looks.dart/occasion.dart/vacation.dart)
  // overflowed by ~7.4px on narrow screens with a scaled-up text size,
  // because the title/description/button content was fixed-size while the
  // AspectRatio(1) image box was not flexible.
  for (final size in const [Size(360, 640), Size(360, 800), Size(412, 915)]) {
    testWidgets(
      'saved board grid cell does not overflow at ${size.width.toInt()}x'
      '${size.height.toInt()} with 1.3x text scale',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              extensions: [AppThemeTokens.light(_accent)],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.54,
                ),
                itemCount: 1,
                itemBuilder: (context, index) => const SavedBoardCard(
                  source: {
                    'title': 'Monochrome Dressing',
                    'boardCategoryLabel': 'Curated look',
                    'description': 'AHVI saved style board',
                    'items': [
                      {
                        'item_id': 'dress-1',
                        'name': 'Gingham dress',
                        'role': 'dress',
                        'image_url': 'https://example.test/dress.png',
                      },
                      {
                        'item_id': 'shoe-1',
                        'name': 'Heel',
                        'role': 'footwear',
                        'image_url': 'https://example.test/shoe.png',
                      },
                      {
                        'item_id': 'bag-1',
                        'name': 'Clutch',
                        'role': 'accessory',
                        'image_url': 'https://example.test/bag.png',
                      },
                    ],
                  },
                  wardrobeById: {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
