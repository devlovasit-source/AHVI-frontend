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
