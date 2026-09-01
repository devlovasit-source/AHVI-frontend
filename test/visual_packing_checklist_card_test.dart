import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/chat_cards/visual_packing_checklist_card.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

Map<String, dynamic> _card({
  List<Map<String, dynamic>>? items,
  List<dynamic>? actions,
  String actionKey = 'actions',
}) => {
  'type': 'visual_packing_checklist',
  'title': 'Carry-on Checklist',
  'subtitle': 'Three days',
  'visual_sections': [
    {
      'id': 'tech',
      'title': 'Tech & Power',
      'items':
          items ??
          [
            {'id': 'charger', 'label': 'Charger'},
            {'id': 'passport', 'label': 'Passport', 'packed': true},
          ],
    },
  ],
  if (actions != null) actionKey: actions,
};

List<Map<String, dynamic>> _items(int count, {Set<int> packed = const {}}) => [
  for (var i = 1; i <= count; i++)
    {
      'id': 'item-$i',
      'label': 'Item $i',
      if (packed.contains(i)) 'packed': true,
    },
];

void main() {
  test('plural image_urls wins over singular image_url', () {
    expect(
      packingImageUrlForItem({
        'image_urls': ['https://example.test/plural.png'],
        'image_url': 'https://example.test/singular.png',
      }),
      'https://example.test/plural.png',
    );
  });

  test('singular image_url is the fallback when plural is empty', () {
    expect(
      packingImageUrlForItem({
        'image_urls': [],
        'image_url': 'https://example.test/singular.png',
      }),
      'https://example.test/singular.png',
    );
  });

  test('asset_key and rich packing icon aliases are preserved', () {
    expect(
      packingAssetKeyForItem({
        'asset_key': 'assets/images/plan_card_women.jpg',
      }),
      'assets/images/plan_card_women.jpg',
    );
    expect(packingIconForKey('passport'), Icons.badge_outlined);
    expect(packingSectionIconForKey('Tech & Power'), Icons.power_rounded);
    expect(
      packingSectionIconForKey('Unknown Section'),
      Icons.inventory_2_rounded,
    );
  });

  testWidgets('backend packed state and section icon fallback are preserved', (
    tester,
  ) async {
    await tester.pumpWidget(_app(VisualPackingChecklistCard(card: _card())));
    expect(find.textContaining('Tech & Power'), findsOneWidget);
    expect(find.text('Charger'), findsOneWidget);
    expect(find.byIcon(Icons.power_outlined), findsAtLeastNWidgets(1));
    expect(find.text('1 of 2 packed'), findsOneWidget);
  });

  testWidgets('asset_key renders Image.asset when no backend image exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        VisualPackingChecklistCard(
          card: _card(
            items: [
              {
                'label': 'Local plan image',
                'asset_key': 'assets/images/plan_card_women.jpg',
              },
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('CTA action is rendered and sends its label', (tester) async {
    String? sent;
    await tester.pumpWidget(
      _app(
        VisualPackingChecklistCard(
          card: _card(
            actions: const [
              {'label': 'Weather prep'},
            ],
          ),
          onAction: (value) => sent = value,
        ),
      ),
    );
    await tester.tap(find.text('Weather prep'));
    expect(sent, 'Weather prep');
  });

  testWidgets('four items use the standard non-scrolling row', (tester) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: _items(4)))),
    );
    for (var i = 1; i <= 4; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('five items remain available in a horizontal scroll row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: _items(5)))),
    );
    for (var i = 1; i <= 5; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('eight items remain reachable without shrinking their tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: _items(8)))),
    );
    for (var i = 1; i <= 8; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    final scroll = find.byType(SingleChildScrollView);
    await tester.drag(scroll, const Offset(-500, 0));
    await tester.pump();
    expect(find.text('Item 8'), findsOneWidget);
  });

  testWidgets('checking item five updates progress across all items', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: _items(5)))),
    );
    expect(find.text('0 of 5 packed'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-500, 0),
    );
    await tester.pump();
    await tester.tap(find.byType(InkWell).at(4));
    await tester.pump();
    expect(find.text('1 of 5 packed'), findsOneWidget);
  });

  testWidgets('checking item eight updates progress across all items', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: _items(8)))),
    );
    expect(find.text('0 of 8 packed'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-700, 0),
    );
    await tester.pump();
    await tester.tap(find.byType(InkWell).at(7));
    await tester.pump();
    expect(find.text('1 of 8 packed'), findsOneWidget);
  });

  test('all action aliases remain accepted', () {
    for (final key in ['actions', 'quick_actions', 'quickActions', 'chips']) {
      final payload = VisualPackingChecklistPayload.fromJson(
        _card(
          actionKey: key,
          actions: const [
            {'label': 'Alias action'},
          ],
        ),
      );
      expect(payload.actions.single['label'], 'Alias action');
    }
  });

  test('default actions remain available when aliases are absent', () {
    final payload = VisualPackingChecklistPayload.fromJson(
      _card(items: _items(1)),
    );
    expect(payload.actions.map((action) => action['label']), [
      'Open checklist',
      'Plan outfits',
      'Weather prep',
    ]);
  });

  testWidgets('empty sections render safely without an item row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(VisualPackingChecklistCard(card: _card(items: const []))),
    );
    expect(find.textContaining('Tech & Power'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('packing card has no overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          VisualPackingChecklistCard(
            card: _card(
              items: _items(8),
              actions: const [
                {'label': 'Open checklist'},
                {'label': 'Plan outfits'},
                {'label': 'Weather prep'},
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.beach_access_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('action labels stay accessible in responsive wrap layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        VisualPackingChecklistCard(
          card: _card(
            items: _items(1),
            actions: const [
              {'label': 'Open checklist'},
              {'label': 'Plan outfits'},
              {'label': 'Weather prep'},
            ],
          ),
        ),
      ),
    );
    for (final label in ['Open checklist', 'Plan outfits', 'Weather prep']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) {
  final tokens = AppThemeTokens.light(_accent);
  return MaterialApp(
    theme: BaseTheme.light.copyWith(extensions: [tokens]),
    home: Scaffold(body: child),
  );
}
