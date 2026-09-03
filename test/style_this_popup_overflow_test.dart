// FINAL APK BLOCKER: Style This popup reported "yellow lines" on a physical
// Samsung device. Flutter's built-in RenderFlex overflow indicator paints as
// a black/yellow diagonal-stripe banner whenever a Row/Column exceeds its
// constraints. This proves whether AhviOutfitBoardDetailSheet -- the tap
// popup opened from a Style This board card (see
// VisualDirectionCarousel._openBoardDetail) -- overflows at the required
// device widths and at a large text scale, now that the backend can return
// longer explicit board titles (e.g. "Structured Refined Weekend") instead
// of the shorter bare archetype name it used to send.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

// Stress the layout harder than the real backend does: a long explicit
// title, four mood tags, and three full-sentence reasons -- worse than
// "Structured Refined Weekend" so a pass here is a safe margin, not a
// coincidence.
Map<String, dynamic> _direction() => {
  'title': 'Effortless Structured Refined Weekend Editorial Edit',
  'adjectives': ['Effortless', 'Structured', 'Considered', 'Polished'],
  'why_it_works':
      'The tailored bottom and clean footwear keep the look client-facing '
      'and polished while staying approachable for a long day out.',
  'reason':
      'A restrained palette and one quiet accessory finish keep the focus '
      'on you instead of the outfit itself.',
  'styling_tip':
      'Let the footwear carry the polish so nothing else has to compete '
      'for attention in the frame.',
  'items': ['Charcoal Wool Overcoat', 'Ivory Silk Blouse', 'Tailored Trouser'],
};

Future<void> _pumpPopup(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AhviOutfitBoardDetailSheet(
                    direction: _direction(),
                    editorialCover: const {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
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
      'Style This popup renders without overflow at ${entry.key}',
      (tester) async {
        await _pumpPopup(tester, size: entry.value);
        expect(tester.takeException(), isNull);
        expect(find.byType(AhviOutfitBoardDetailSheet), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Style This popup survives textScaleFactor 1.3 without overflow',
    (tester) async {
      await _pumpPopup(tester, size: const Size(360, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byType(AhviOutfitBoardDetailSheet), findsOneWidget);
    },
  );
}
