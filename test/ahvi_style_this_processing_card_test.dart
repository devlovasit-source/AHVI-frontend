import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/feature/chat/widgets/ahvi_processing_bubble.dart';
import 'package:myapp/feature/chat/widgets/ahvi_style_this_processing_card.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

class _TestLocalizations extends AppLocalizations {
  _TestLocalizations() : super(const Locale('en'));

  @override
  String translate(String key) =>
      const {
        'item_detail_style_processing_title': 'Styling your {item}',
        'item_detail_style_processing_subtitle':
            'Finding the best pieces from your wardrobe...',
      }[key] ??
      key;
}

class _TestLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_TestLocalizations());

  @override
  bool shouldReload(_TestLocalizationsDelegate old) => false;
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required String itemName,
  bool dark = false,
  double width = 412,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [_TestLocalizationsDelegate()],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        extensions: [dark ? AppThemeTokens.dark(_accent) : AppThemeTokens.light(_accent)],
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            // Mirrors the clamp in ahvi_item_detail_modal.dart's dialog builder.
            constraints: BoxConstraints(
              maxWidth: (width - 24).clamp(280.0, 356.0),
            ),
            child: AhviStyleThisProcessingCard(itemName: itemName),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Mirrors the mode branch in ahvi_item_detail_modal.dart's
/// _performStyleRequest dialog builder, without the request/navigation
/// scaffolding around it.
Widget _dialogContentFor(String mode, String itemName) {
  return mode == 'style_this'
      ? AhviStyleThisProcessingCard(itemName: itemName)
      : const AhviProcessingBubble(message: 'Putting the outfit together');
}

void main() {
  group('AhviStyleThisProcessingCard', () {
    testWidgets('shows the AHVI brand row', (tester) async {
      await _pumpCard(tester, itemName: 'White Shirt');
      expect(find.text('AHVI'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNWidgets(2));
    });

    testWidgets('shows the selected item name', (tester) async {
      await _pumpCard(tester, itemName: 'White Shirt');
      expect(find.text('Styling your White Shirt'), findsOneWidget);
      expect(find.textContaining('Styling around'), findsNothing);
    });

    testWidgets('shows wardrobe-sourced wording, not technical copy', (tester) async {
      await _pumpCard(tester, itemName: 'Blazer');
      expect(
        find.text('Finding the best pieces from your wardrobe...'),
        findsOneWidget,
      );
      expect(find.textContaining('processing'), findsNothing);
      expect(find.textContaining('Generating'), findsNothing);
    });

    testWidgets('falls back gracefully with no item name', (tester) async {
      await _pumpCard(tester, itemName: '');
      expect(find.text('Styling your piece'), findsOneWidget);
    });

    testWidgets('renders without overflow at a narrow Android width', (tester) async {
      await _pumpCard(tester, itemName: 'Charcoal Wool Overcoat', width: 360);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long item names wrap onto a second line without overflowing',
        (tester) async {
      for (final name in [
        'Grey Button-down Shirt',
        'White Short-Sleeved Button-Up Shirt',
        'Cheetah Waistcoat Outerwear',
      ]) {
        await _pumpCard(tester, itemName: name, width: 360);
        expect(tester.takeException(), isNull, reason: name);
        final titleFinder = find.textContaining('Styling your $name');
        expect(titleFinder, findsOneWidget, reason: name);
        final titleWidget = tester.widget<Text>(titleFinder);
        expect(titleWidget.maxLines, 2, reason: name);
        expect(titleWidget.textAlign, TextAlign.center, reason: name);
      }
    });

    testWidgets('title and subtitle are centered', (tester) async {
      await _pumpCard(tester, itemName: 'White Shirt');
      final titleWidget = tester.widget<Text>(
        find.text('Styling your White Shirt'),
      );
      final subtitleWidget = tester.widget<Text>(
        find.text('Finding the best pieces from your wardrobe...'),
      );
      expect(titleWidget.textAlign, TextAlign.center);
      expect(subtitleWidget.textAlign, TextAlign.center);
    });

    testWidgets('renders without error in dark theme', (tester) async {
      await _pumpCard(tester, itemName: 'White Shirt', dark: true);
      expect(tester.takeException(), isNull);
      expect(find.text('AHVI'), findsOneWidget);
    });
  });

  group('Style This processing dialog branch', () {
    testWidgets('style_this mode renders the branded card, not the bubble',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [_TestLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          theme: ThemeData(
            useMaterial3: true,
            extensions: [AppThemeTokens.light(_accent)],
          ),
          home: Scaffold(body: _dialogContentFor('style_this', 'White Shirt')),
        ),
      );
      await tester.pump();
      expect(find.byType(AhviStyleThisProcessingCard), findsOneWidget);
      expect(find.byType(AhviProcessingBubble), findsNothing);
    });

    testWidgets('build_outfit mode keeps the original bubble unchanged',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [_TestLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          theme: ThemeData(
            useMaterial3: true,
            extensions: [AppThemeTokens.light(_accent)],
          ),
          home: Scaffold(body: _dialogContentFor('build_outfit', 'White Shirt')),
        ),
      );
      await tester.pump();
      expect(find.byType(AhviProcessingBubble), findsOneWidget);
      expect(find.byType(AhviStyleThisProcessingCard), findsNothing);
      expect(find.text('Putting the outfit together'), findsOneWidget);
    });
  });
}
