import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/profile_theme.dart';

final ThemeData _testTheme = ThemeData(
  extensions: <ThemeExtension<dynamic>>[
    AppThemeTokens.light(getAccentPalette(ProfileTheme.coolBlue)),
  ],
);

// A board WITHOUT board_id / revision / source_policy (no backend contract).
Map<String, dynamic> _direction() => {
      'occasion': 'office',
      'why': 'Sharp and balanced.',
      'board_items': [
        {'name': 'White shirt', 'item_id': 'shirt-1', 'role': 'top', 'image_url': 'https://x/shirt.png'},
        {'name': 'Navy chinos', 'item_id': 'chino-1', 'role': 'bottom', 'image_url': 'https://x/chino.png'},
        {'name': 'Brown loafers', 'item_id': 'loafer-1', 'role': 'footwear', 'image_url': 'https://x/loafer.png'},
      ],
    };

Future<void> _pumpBar(WidgetTester tester, OutfitActionBar bar) =>
    tester.pumpWidget(MaterialApp(theme: _testTheme, home: Scaffold(body: bar)));

void main() {
  testWidgets('Save invokes callback, persists the rendered board, works without a board contract', (tester) async {
    Map<String, dynamic>? captured;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          captured = {'occasion': occasion, 'title': title, 'imageUrl': imageUrl, 'itemIds': itemIds, 'items': items, 'desc': outfitDescription};
          return 'doc-1';
        },
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!['occasion'], 'office');
    expect(captured!['title'], 'Office Look');
    expect(captured!['imageUrl'], 'https://x/shirt.png');
    expect(captured!['desc'], 'Sharp and balanced.');
    expect((captured!['itemIds'] as List), containsAll(<String>['shirt-1', 'chino-1', 'loafer-1']));
    expect((captured!['items'] as List).length, 3);
    expect(find.text('Saved'), findsOneWidget); // heart flips only after success
  });

  testWidgets('Double-tap Save does not create duplicate saves', (tester) async {
    var calls = 0;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          calls++;
          return 'doc-$calls';
        },
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Saved'));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('Save failure restores the unsaved icon and surfaces an error', (tester) async {
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          throw Exception('appwrite down');
        },
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Saved'), findsNothing); // stays unsaved
    expect(find.text('Save'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('Share invokes capture and opens the share sheet with the title caption', (tester) async {
    var captured = false;
    Uint8List? sharedBytes;
    String? caption;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        captureOverride: () async {
          captured = true;
          return Uint8List.fromList(<int>[1, 2, 3, 4]);
        },
        shareImageOverride: (b, c) async {
          sharedBytes = b;
          caption = c;
        },
      ),
    );

    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump();

    expect(captured, isTrue); // Share attempted PNG capture
    expect(sharedBytes, isNotNull);
    expect(sharedBytes!.isNotEmpty, isTrue);
    expect(caption, contains('Office Look')); // caption carries the board title
  });

  testWidgets('Share capture failure falls back to text sharing (never does nothing)', (tester) async {
    var filesShared = false;
    var textShared = false;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        captureOverride: () async => null, // capture fails
        shareImageOverride: (b, c) async => filesShared = true,
        shareTextOverride: (t) async => textShared = true,
      ),
    );

    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump();

    expect(filesShared, isFalse);
    expect(textShared, isTrue); // text fallback fired
  });

  testWidgets('Save and Share remain enabled without a board contract', (tester) async {
    var saved = false;
    var shared = false;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          saved = true;
          return 'doc-1';
        },
        captureOverride: () async => Uint8List.fromList(<int>[1, 2, 3]),
        shareImageOverride: (b, c) async => shared = true,
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    // Share first (no snackbar), then Save (its success snackbar must not block
    // the Share button — assert both callbacks fire without a contract).
    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump();
    await tester.pump();

    expect(saved, isTrue);
    expect(shared, isTrue);
  });

  // ── Post-shuffle state ────────────────────────────────────────────────────

  testWidgets('Save uses currentBoardItems (post-shuffle) not original direction', (tester) async {
    final shuffledItems = <Map<String, dynamic>>[
      {'name': 'Shuffled tee', 'item_id': 'stee-1', 'role': 'top', 'image_url': 'https://x/stee.png', 'source': 'style_asset'},
      {'name': 'Shuffled trousers', 'item_id': 'str-2', 'role': 'bottom', 'image_url': 'https://x/str.png', 'source': 'style_asset'},
      {'name': 'Shuffled sneakers', 'item_id': 'ssn-3', 'role': 'footwear', 'image_url': 'https://x/ssn.png', 'source': 'style_asset'},
    ];
    Map<String, dynamic>? captured;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        currentBoardItems: shuffledItems,
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          captured = {'items': items, 'itemIds': itemIds};
          return 'doc-shuffled';
        },
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(captured, isNotNull, reason: 'save callback must fire');
    final savedItems = captured!['items'] as List;
    expect(savedItems.length, 3, reason: 'shuffled item count preserved');
    expect(savedItems.first['name'], 'Shuffled tee',
        reason: 'shuffled items used, not original direction board_items');
    final savedIds = captured!['itemIds'] as List;
    expect(savedIds, containsAll(<String>['stee-1', 'str-2', 'ssn-3']),
        reason: 'shuffled item IDs propagated');
  });

  testWidgets('Save/reopen item count and order match after shuffle (outfitItems preserves sequence)', (tester) async {
    final shuffled = <Map<String, dynamic>>[
      {'name': 'A', 'item_id': 'a-1', 'role': 'top', 'image_url': 'https://x/a.png', 'source': 'wardrobe'},
      {'name': 'B', 'item_id': 'b-2', 'role': 'bottom', 'image_url': 'https://x/b.png', 'source': 'wardrobe'},
    ];
    List<Map<String, dynamic>>? savedOutfitItems;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Test',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        currentBoardItems: shuffled,
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          savedOutfitItems = items;
          return 'doc-2';
        },
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(savedOutfitItems, isNotNull);
    expect(savedOutfitItems!.length, 2);
    expect(savedOutfitItems![0]['item_id'], 'a-1');
    expect(savedOutfitItems![1]['item_id'], 'b-2');
  });

  testWidgets('asset_cutout_url preserved through currentBoardItems into save', (tester) async {
    final itemWithCutout = <Map<String, dynamic>>[
      {
        'name': 'Floral dress',
        'item_id': 'dress-1',
        'role': 'dress',
        'image_url': 'https://x/opaque.jpg',
        'asset_cutout_url': 'https://x/cutout.png',
        'source': 'style_asset',
      },
    ];
    Map<String, dynamic>? captured;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Test',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        currentBoardItems: itemWithCutout,
        saveBoardOverride: ({required occasion, required outfitDescription, required imageUrl, required title, required itemIds, required items}) async {
          captured = {'items': items};
          return 'doc-3';
        },
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(captured, isNotNull);
    final item = (captured!['items'] as List).first as Map;
    expect(item['asset_cutout_url'], 'https://x/cutout.png',
        reason: 'asset_cutout_url must survive toContractJson() round-trip via raw');
    expect(item['image_url'], 'https://x/opaque.jpg',
        reason: 'image_url also preserved for fallback');
  });

  testWidgets('Unlocked board item has no visible border (no frame on transparent cutout)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AhviOutfitBoardCard(direction: _direction(), width: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    tester.takeException(); // dismiss network-image noise

    // Every DecoratedBox in the canvas should have a null border when items are unlocked.
    // BoardMutationBar absent (no contract) so no lock toggles rendered.
    final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    for (final box in decoratedBoxes) {
      final deco = box.decoration;
      if (deco is BoxDecoration) {
        expect(deco.border, isNull,
            reason: 'Unlocked item must not have a visible frame border');
      }
    }
  });

  testWidgets('Lock/Shuffle stays disabled (no BoardMutationBar) without a contract, while Save/Share still render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AhviOutfitBoardCard(direction: _direction(), width: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Clear any collage layout/network-image noise; this test asserts gating,
    // not pixel layout.
    tester.takeException();

    expect(find.byType(BoardMutationBar), findsNothing); // lock/shuffle gated off
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
