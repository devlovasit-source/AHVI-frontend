// Focused, lightweight widget tests for OutfitReasoningStrip's Styling Tip
// truncation fix. This widget renders text only (no board images/canvas), so
// it is pumped directly rather than through the full VisualDirectionCarousel
// + fixture-image harness in test/visual_board_85_phase1_test.dart — that
// harness is independently flaky/timeout-prone in this environment on both
// the pre-fix and post-fix code (confirmed via git stash comparison), so
// this file is the reliable source of truth for this specific fix.
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

OutfitBoardModel _model({required String why, required String tip}) =>
    OutfitBoardModel(
      title: 'Refined Weekend',
      chips: const [],
      items: const [],
      missingName: '',
      intelligenceText: why,
      stylingTip: tip,
    );

Future<void> _pumpStrip(
  WidgetTester tester, {
  required String why,
  required String tip,
  double width = 360,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: OutfitReasoningStrip(
                  model: _model(why: why, tip: tip),
                  mode: BoardInteractionMode.recommendation,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const shortWhy =
      'The tailored fit and clean palette keep the look sharp without effort.';

  testWidgets('A. Styling Tip Text exists with key style-styling-tip', (
    tester,
  ) async {
    await _pumpStrip(tester, why: shortWhy, tip: 'Keep the accessories minimal.');
    expect(find.byKey(const ValueKey('style-styling-tip')), findsOneWidget);
  });

  testWidgets('B. Styling Tip is no longer line-limited (maxLines == null)', (
    tester,
  ) async {
    await _pumpStrip(tester, why: shortWhy, tip: 'Keep the accessories minimal.');
    final tip = tester.widget<Text>(
      find.byKey(const ValueKey('style-styling-tip')),
    );
    expect(tip.maxLines, isNull);
  });

  testWidgets('C. Styling Tip is not configured with ellipsis overflow', (
    tester,
  ) async {
    await _pumpStrip(tester, why: shortWhy, tip: 'Keep the accessories minimal.');
    final tip = tester.widget<Text>(
      find.byKey(const ValueKey('style-styling-tip')),
    );
    expect(tip.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets(
    'D+F. a deliberately long Styling Tip renders past 2 lines at width 360 with no overflow/exception',
    (tester) async {
      const longTip =
          'Layer a lightweight overshirt for the early evening chill, keep the '
          'footwear polished but low-key, and let the accessories stay minimal '
          'so the tailoring does the talking from arrival through to the last '
          'toast of the night.';
      await _pumpStrip(tester, why: shortWhy, tip: longTip, width: 360);

      final tipFinder = find.byKey(const ValueKey('style-styling-tip'));
      final tip = tester.widget<Text>(tipFinder);
      expect(tip.data, longTip); // full sentence, not truncated
      expect(tip.maxLines, isNull);
      expect(tip.overflow, isNot(TextOverflow.ellipsis));

      final renderedHeight = tester.getSize(tipFinder).height;
      final fontSize = tip.style?.fontSize ?? 14.0;
      final lineHeightMultiplier = tip.style?.height ?? 1.2;
      final singleLineHeight = fontSize * lineHeightMultiplier;
      expect(renderedHeight, greaterThan(singleLineHeight * 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('E+F. long Styling Tip survives textScaleFactor 1.3 with no overflow/exception', (
    tester,
  ) async {
    const longTip =
        'Layer a lightweight overshirt for the early evening chill, keep the '
        'footwear polished but low-key, and let the accessories stay minimal '
        'so the tailoring does the talking from arrival through to the last '
        'toast of the night.';
    await _pumpStrip(
      tester,
      why: shortWhy,
      tip: longTip,
      width: 360,
      textScale: 1.3,
    );

    final tip = tester.widget<Text>(
      find.byKey(const ValueKey('style-styling-tip')),
    );
    expect(tip.data, longTip);
    expect(tip.maxLines, isNull);
    expect(tip.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('G. WHY IT WORKS behavior remains unchanged (bounded to 2 lines, ellipsized)', (
    tester,
  ) async {
    const longWhy =
        'The warm silhouette balances the occasion with an easy proportion '
        'that should end at a clean, readable boundary regardless of screen width.';
    await _pumpStrip(tester, why: longWhy, tip: 'Keep it simple.');

    final why = tester.widget<Text>(
      find.byKey(const ValueKey('style-why-it-works')),
    );
    expect(why.maxLines, 2);
    expect(why.overflow, TextOverflow.ellipsis);
    expect(why.data, longWhy);
  });

  testWidgets('empty tip/why renders nothing (SizedBox.shrink) without exception', (
    tester,
  ) async {
    await _pumpStrip(tester, why: '', tip: '');
    expect(find.byKey(const ValueKey('style-styling-tip')), findsNothing);
    expect(find.byKey(const ValueKey('style-why-it-works')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
