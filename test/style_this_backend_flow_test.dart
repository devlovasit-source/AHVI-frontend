import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/feature/chat/widgets/ahvi_processing_bubble.dart';
import 'package:myapp/feature/chat/widgets/ahvi_style_this_processing_card.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/ahvi_item_detail_modal.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';
import 'package:myapp/widgets/style_boards.dart';
import 'package:myapp/widgets/try_on_coming_soon.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

final _anchor = WardrobeItem(
  id: 'wardrobe-anchor-42',
  name: 'Black Blazer',
  cat: 'outerwear',
  occasions: const ['work'],
  raw: const {r'$id': 'wardrobe-anchor-42', 'board_status': 'ready'},
);

Map<String, dynamic> _boardItem(
  String id,
  String role, {
  bool locked = false,
  String source = 'wardrobe',
}) => {
  'item_id': id,
  'name': id,
  'category': role,
  'role': role,
  'slot': role,
  'source': source,
  'locked': locked,
  'image_url': 'https://example.test/$id.png',
  'masked_url': 'https://example.test/$id-cutout.png',
  if (source == 'style_asset')
    'transparent_url': 'https://example.test/$id-transparent.png',
  'position': {
    'x': role == 'top' ? .08 : .46,
    'y': role == 'footwear' ? .62 : .12,
    'width': .3,
    'height': .3,
    'rotation': 0,
    'z': 1,
  },
};

Map<String, dynamic> _successfulResponse({
  WardrobeItem? selectedItem,
  String anchorRole = 'top',
  bool includeStyleAssetDress = false,
}) {
  final anchor = selectedItem ?? _anchor;
  final isDefault = anchor.id == _anchor.id && anchorRole == 'top';
  final boardItems = isDefault
      ? [
          _boardItem(anchor.id, anchorRole),
          _boardItem('wardrobe-bottom-7', 'bottom', locked: true),
          _boardItem('wardrobe-shoe-9', 'footwear', locked: true),
        ]
      : [
          _boardItem(anchor.id, anchorRole),
          for (final role in const ['top', 'bottom', 'footwear', 'accessory'])
            if (role != anchorRole)
              _boardItem(
                includeStyleAssetDress && role == 'top'
                    ? 'dress-support'
                    : 'support-$role',
                role,
                locked: true,
                source: includeStyleAssetDress && role == 'top'
                    ? 'style_asset'
                    : 'wardrobe',
              ),
        ];
  return {
    'success': true,
    'route': 'style_this',
    'board_policy': 'allow',
    'anchor_item': {'item_id': anchor.id},
    'selected_item_id': anchor.id,
    'visual_directions': [
      {
        'board_id': 'style-board-${anchor.id}',
        'revision': 1,
        'source_policy': 'wardrobe',
        'scenario': 'style_this',
        'direction_name': 'Sharp Layers',
        'title': 'Sharp Layers',
        'occasion': 'work',
        'board_items': boardItems,
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mismatched selected item and anchor cannot render a Style This board', () {
    final response = _successfulResponse()
      ..['selected_item_id'] = 'belt-anchor'
      ..['anchor_item'] = {'item_id': 'dress-support'};

    final parsed = parseAhviResponse(response);

    expect(
      parsed.blocks.where((block) => block.type == AhviBlockType.visualDirections),
      isEmpty,
    );
  });

  test('selected_item_id bridges Style This responses without anchor_item', () {
    final response = _successfulResponse()..remove('anchor_item');

    final parsed = parseAhviResponse(response);
    final block = parsed.blocks.singleWhere(
      (candidate) => candidate.type == AhviBlockType.visualDirections,
    );
    final direction = (block.data['directions'] as List).first as Map;

    expect(direction['selected_item_id'], _anchor.id);
    expect(direction['anchor_item_id'], _anchor.id);
  });

  testWidgets(
    'Style This sends canonical backend request and renders canonical board',
    (tester) async {
      String? itemId;
      String? scenario;
      Map<String, dynamic>? anchorItem;
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      try {
        await _pumpItemDetail(
          tester,
          styleCall:
              ({
                required requestedItemId,
                required requestedScenario,
                requestAnchorItem,
                occasion,
              }) async {
                itemId = requestedItemId;
                scenario = requestedScenario;
                anchorItem = requestAnchorItem;
                return _successfulResponse();
              },
        );
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
        };

        await tester.tap(find.text('Style'));
        await tester.pumpAndSettle();

        expect(itemId, _anchor.id);
        expect(scenario, 'style_this');
        expect(anchorItem?['item_id'], _anchor.id);
        expect(anchorItem?['anchor_item_id'], _anchor.id);
        expect(anchorItem?['selected_item_id'], _anchor.id);
        expect(anchorItem?['interaction_mode'], 'style_this');
        expect(anchorItem?['source_policy'], 'wardrobe');
        expect(anchorItem?['locked'], isTrue);
        expect(anchorItem?['anchor'], isTrue);
        expect(anchorItem?['resolved_image_field'], isNotNull);
        expect(find.byType(StyleBoardsScreen), findsNothing);
        expect(find.byType(VisualDirectionCarousel), findsOneWidget);
        expect(find.byType(AhviOutfitBoardCard), findsOneWidget);
        expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
        expect(find.text('STYLE THIS'), findsOneWidget);
        expect(find.text('1 of 3 items locked'), findsOneWidget);
        final requestLog = logs.singleWhere(
          (line) => line.startsWith('AHVI_STYLE_THIS_REQUEST'),
        );
        expect(requestLog, contains('correlation_id=style-'));
        expect(requestLog, contains('anchor_item_id=id-'));
        expect(
          requestLog,
          contains('scenario=style_this source_policy=wardrobe'),
        );
        final anchorLog = logs.singleWhere(
          (line) => line.startsWith('AHVI_STYLE_THIS_ANCHOR'),
        );
        expect(anchorLog, contains('anchor_present=true'));
        expect(anchorLog, contains('initial_locked_count=1'));
        expect(anchorLog, contains('supporting_locked_count=0'));
      } finally {
        debugPrint = originalDebugPrint;
      }
    },
  );

  for (final fixture in const [
    (id: 'shirt-anchor', name: 'White Shirt', role: 'top'),
    (id: 'jeans-anchor', name: 'Blue Jeans', role: 'bottom'),
    (id: 'shoe-anchor', name: 'Black Loafers', role: 'footwear'),
    (id: 'belt-anchor', name: 'Brown Belt', role: 'accessory'),
  ]) {
    testWidgets(
      'Style This preserves ${fixture.name} identity through canonical board',
      (tester) async {
        final selected = WardrobeItem(
          id: fixture.id,
          name: fixture.name,
          cat: fixture.role,
          occasions: const ['work'],
          raw: {
            r'$id': fixture.id,
            'board_status': 'ready',
          },
        );
        Map<String, dynamic>? requestAnchor;
        await _pumpItemDetail(
          tester,
          selectedItem: selected,
          styleCall:
              ({
                required requestedItemId,
                required requestedScenario,
                requestAnchorItem,
                occasion,
              }) async {
                requestAnchor = requestAnchorItem;
                return _successfulResponse(
                  selectedItem: selected,
                  anchorRole: fixture.role,
                  includeStyleAssetDress: fixture.role == 'accessory',
                );
              },
        );

        await tester.tap(find.text('Style'));
        await tester.pumpAndSettle();

        expect(requestAnchor?['item_id'], selected.id);
        expect(requestAnchor?['anchor_item_id'], selected.id);
        expect(requestAnchor?['selected_item_id'], selected.id);
        expect(find.byType(VisualDirectionCarousel), findsOneWidget);
        expect(find.byType(AhviOutfitBoardCard), findsOneWidget);
        expect(find.byType(AhviUnifiedOutfitGrid), findsOneWidget);
        expect(find.text('STYLE THIS'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);

        final card = tester.widget<AhviOutfitBoardCard>(
          find.byType(AhviOutfitBoardCard),
        );
        final items = (card.direction['board_items'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false);
        expect(card.direction['interaction_mode'], 'style_this');
        expect(card.direction['anchor_item_id'], selected.id);
        expect(card.direction['selected_item_id'], selected.id);
        expect(items.first['item_id'], selected.id);
        expect(items.first['image_url'], 'https://example.test/${selected.id}.png');
        if (fixture.role == 'accessory') {
          expect(items.any((item) => item['source'] == 'style_asset'), isTrue);
          expect(items.any((item) => item['item_id'] == 'dress-support'), isTrue);
          expect(items.first['item_id'], isNot('dress-support'));
          expect(items.first['image_url'], isNot(contains('dress-support')));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Try-On is Coming Soon and does not call Build Outfit', (
    tester,
  ) async {
    var calls = 0;
    await _pumpItemDetail(
      tester,
      styleCall:
          ({
            required requestedItemId,
            required requestedScenario,
            requestAnchorItem,
            occasion,
          }) async {
            calls++;
            return null;
          },
    );

    expect(find.text('Try-On'), findsOneWidget);
    expect(find.text('Build Outfit'), findsNothing);

    await tester.tap(find.text('Try-On'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(TryOnComingSoonDialog), findsOneWidget);
    expect(
      find.text('See how your looks come together on you.'),
      findsOneWidget,
    );
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.byType(AhviProcessingBubble), findsNothing);
    expect(find.byType(AhviOutfitBoardCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Style This loading state presents the branded AhviStyleThisProcessingCard '
    '(not the bare chat bubble), sized to a fraction of the barrier width',
    (tester) async {
      final completer = Completer<Map<String, dynamic>?>();
      await _pumpItemDetail(
        tester,
        styleCall:
            ({
              required requestedItemId,
              required requestedScenario,
              requestAnchorItem,
              occasion,
            }) => completer.future,
      );

      await tester.tap(find.text('Style'));
      await tester.pump(); // let showDialog build the loading state

      expect(find.byType(AhviStyleThisProcessingCard), findsOneWidget);
      expect(find.byType(AhviProcessingBubble), findsNothing);
      expect(find.text('AHVI'), findsOneWidget);
      expect(find.text('Styling your ${_anchor.name}'), findsOneWidget);
      expect(
        find.text('Finding the best pieces from your wardrobe…'),
        findsOneWidget,
      );

      final constraint = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byType(AhviStyleThisProcessingCard),
          matching: find.byType(ConstrainedBox),
        ),
      );
      // showDialog's root-navigator context sees the raw test window, not
      // the 430-wide surface set for the item-detail page itself -- assert
      // the actual ratio (78-86% of that window) rather than a hardcoded
      // pixel value tied to a surface size the dialog doesn't inherit.
      final dialogWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final ratio = constraint.constraints.maxWidth / dialogWidth;
      expect(ratio, greaterThanOrEqualTo(0.78));
      expect(ratio, lessThanOrEqualTo(0.86));

      completer.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'item-level Build Outfit contract stays text-only even with stale board fields',
    (tester) async {
      var calls = 0;
      await _pumpItemDetail(
        tester,
        styleCall:
            ({
              required requestedItemId,
              required requestedScenario,
              requestAnchorItem,
              occasion,
            }) async {
              calls++;
              return {
                'success': false,
                'intent': 'try_on_coming_soon',
                'action': 'try_on_coming_soon',
                'response_mode': 'text_only',
                'message': 'Try-On is coming soon.',
                'outfit': {
                  'board_id': 'stale-board',
                  'revision': 1,
                  'items': [_boardItem('stale-top', 'top')],
                },
              };
            },
      );

      expect(find.text('Try-On'), findsOneWidget);
      expect(find.text('Build Outfit'), findsNothing);
      await tester.tap(find.text('Try-On'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.byType(TryOnComingSoonDialog), findsOneWidget);
      expect(find.byType(AhviOutfitBoardCard), findsNothing);
      expect(find.byType(AhviUnifiedOutfitGrid), findsNothing);
      expect(find.text('Coming soon'), findsOneWidget);
    },
  );

  testWidgets(
    'Style This keeps valid directions when one direction is malformed',
    (tester) async {
      final response = _successfulResponse();
      final validDirections = [
        for (var index = 1; index <= 3; index++)
          {
            ...Map<String, dynamic>.from(
              (response['visual_directions'] as List).single as Map,
            ),
            'board_id':
                '00000000-0000-4000-8000-00000000000$index',
            'direction_name': 'Sharp Layers $index',
            'title': 'Sharp Layers $index',
          },
      ];
      response.remove('visual_directions');
      response['style_directions'] = [
        {
          'board_id': 'outfit_card_legacy',
          'revision': 0,
          'source_policy': 'catalog',
          'scenario': 'style_this',
          'direction_name': 'Legacy fallback',
          'board_items': const [],
        },
        ...validDirections,
      ];
      /*
       * The malformed direction is intentionally retained in the backend
       * payload. The item-detail contract filter must reject only it while
       * forwarding all three valid directions to the canonical carousel.
       */
      final expectedValidTitles = [
        'Sharp Layers 1',
        'Sharp Layers 2',
        'Sharp Layers 3',
      ];
      await _pumpItemDetail(
        tester,
        styleCall:
            ({
              required requestedItemId,
              required requestedScenario,
              requestAnchorItem,
              occasion,
            }) async => response,
      );

      await tester.tap(find.text('Style'));
      await tester.pumpAndSettle();

      expect(find.byType(VisualDirectionCarousel), findsOneWidget);
      expect(find.byType(AhviOutfitBoardCard), findsNWidgets(3));
      expect(find.text('STYLE THIS'), findsNWidgets(3));
      expect(find.text('Undo shuffle'), findsNWidgets(3));
      expect(find.text('Save'), findsNWidgets(3));
      expect(find.text('Share'), findsNWidgets(3));
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(3));
      for (final title in expectedValidTitles) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Legacy fallback'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed Style This response keeps detail open with retry', (
    tester,
  ) async {
    var calls = 0;
    await _pumpItemDetail(
      tester,
      styleCall:
          ({
            required requestedItemId,
            required requestedScenario,
            requestAnchorItem,
            occasion,
          }) async {
            calls++;
            return {'success': true, 'visual_directions': const []};
          },
    );

    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Black Blazer'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(StyleBoardsScreen), findsNothing);
    expect(find.byType(VisualDirectionCarousel), findsNothing);
    expect(find.byType(AhviOutfitBoardCard), findsNothing);
  });

  testWidgets('recommendation mode remains feedback-only', (tester) async {
    final direction = Map<String, dynamic>.from(
      (_successfulResponse()['visual_directions'] as List).single as Map,
    )..remove('scenario');
    direction['interaction_mode'] = 'recommendation';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [_TestLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        home: Scaffold(
          body: AhviOutfitBoardCard(direction: direction, width: 390),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AHVI EDIT'), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Dislike'), findsOneWidget);
    expect(find.byType(BoardMutationBar), findsNothing);
  });
}

typedef _TestStyleCall =
    Future<Map<String, dynamic>?> Function({
      required String requestedItemId,
      required String requestedScenario,
      Map<String, dynamic>? requestAnchorItem,
      String? occasion,
    });

Future<void> _pumpItemDetail(
  WidgetTester tester, {
  WardrobeItem? selectedItem,
  required _TestStyleCall styleCall,
}) async {
  final item = selectedItem ?? _anchor;
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [_TestLocalizationsDelegate()],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        useMaterial3: true,
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showItemDetailModal(
              context,
              item: item,
              allItems: [item],
              styleWardrobeItemCall:
                  ({
                    required itemId,
                    required scenario,
                    anchorItem,
                    occasion,
                  }) => styleCall(
                    requestedItemId: itemId,
                    requestedScenario: scenario,
                    requestAnchorItem: anchorItem,
                    occasion: occasion,
                  ),
            ),
            child: const Text('Open item'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open item'));
  await tester.pumpAndSettle();
}

class _TestLocalizations extends AppLocalizations {
  _TestLocalizations() : super(const Locale('en'));

  @override
  String translate(String key) =>
      const {
        'item_detail_style_this': 'Style',
        'item_detail_build_outfit': 'Build',
        'item_detail_wore_today': 'Wore',
        'common_edit': 'Edit',
        'item_detail_never_worn': 'Never worn',
        'item_detail_style_directions': 'Style Directions',
      }[key] ??
      'Label';
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
