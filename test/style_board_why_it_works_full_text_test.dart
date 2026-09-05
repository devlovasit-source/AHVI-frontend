// STYLE BOARD P0 step 7: the compact chat board card's "WHY IT WORKS" copy
// used to hard-truncate at 2 lines (maxLines: 2, ellipsis). The ticket asks
// for the full reasoning to be readable there -- confirms the cap is gone
// and that removing it doesn't overflow at the required device widths /
// text scales. Only the WHY IT WORKS text loses its cap; the title
// (OutfitContextStrip) and STYLING TIP keep theirs, so this test also
// guards against an over-broad "remove all maxLines" edit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

const _longWhy =
    'The tailored bottom and clean footwear keep the look client-facing and '
    'polished while staying approachable for a long day out, and the '
    'monochrome palette lets the single accessory carry all of the visual '
    'interest without competing for attention across the frame.';

Map<String, dynamic> _direction() => {
  'title': 'Lunch',
  'board_items': [
    {
      'item_id': 'top-1',
      'name': 'White shirt',
      'role': 'top',
      'source': 'wardrobe',
      'image_url': 'https://test/raw/top.png',
      'masked_url': 'https://test/processed/top.png',
    },
  ],
  'why_it_works': _longWhy,
  'styling_tip': 'Let the footwear carry the polish.',
};

Future<void> _pump(WidgetTester tester, {required Size size, double textScale = 1.0}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, extensions: [AppThemeTokens.light(_accent)]),
        home: Scaffold(
          body: Center(
            child: AhviOutfitBoardCard(direction: _direction(), width: size.width - 24),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const deviceSizes = <String, Size>{
    '360x640': Size(360, 640),
    '360x800': Size(360, 800),
    '412x915': Size(412, 915),
  };

  for (final entry in deviceSizes.entries) {
    testWidgets(
      'Style board card WHY IT WORKS renders full text without overflow at ${entry.key}',
      (tester) async {
        await _pump(tester, size: entry.value);
        expect(tester.takeException(), isNull);

        final textWidget = tester.widget<Text>(
          find.byKey(const ValueKey('style-why-it-works')),
        );
        expect(textWidget.data, _longWhy);
        expect(textWidget.maxLines, isNull);
      },
    );
  }

  testWidgets(
    'Style board card WHY IT WORKS survives textScaleFactor 1.3 without overflow',
    (tester) async {
      await _pump(tester, size: const Size(360, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);

      final textWidget = tester.widget<Text>(
        find.byKey(const ValueKey('style-why-it-works')),
      );
      expect(textWidget.data, _longWhy);
      expect(textWidget.maxLines, isNull);
    },
  );
}
