import 'dart:async';
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
    {
      'name': 'White shirt',
      'item_id': 'shirt-1',
      'role': 'top',
      'image_url': 'https://x/shirt.png',
      'masked_url': 'https://x/shirt-cutout.png',
    },
    {
      'name': 'Navy chinos',
      'item_id': 'chino-1',
      'role': 'bottom',
      'image_url': 'https://x/chino.png',
      'masked_url': 'https://x/chino-cutout.png',
    },
    {
      'name': 'Brown loafers',
      'item_id': 'loafer-1',
      'role': 'footwear',
      'image_url': 'https://x/loafer.png',
      'masked_url': 'https://x/loafer-cutout.png',
    },
  ],
};

Future<void> _pumpBar(WidgetTester tester, OutfitActionBar bar) =>
    tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: Scaffold(body: bar),
      ),
    );

Future<void> _confirmSave(
  WidgetTester tester, {
  String? category,
  bool favourite = false,
}) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect(find.text('Save this look to'), findsOneWidget);
  if (category != null) {
    await tester.tap(find.text(category));
    await tester.pump();
  }
  if (favourite) {
    await tester.tap(find.text('Add to Favourites'));
    await tester.pump();
  }
  await tester.tap(find.text('Save look'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('feedback state survives an unchanged semantic board rebuild', (
    tester,
  ) async {
    OutfitActionBar bar(Map<String, dynamic> direction) => OutfitActionBar(
      direction: direction,
      editorialCover: const {},
      primaryLabel: 'Office Look',
      missingName: '',
      shareBoundaryKey: GlobalKey(),
    );
    await _pumpBar(tester, bar(_direction()));
    await tester.tap(find.text('Like'));
    await tester.pump();
    expect(find.byIcon(Icons.thumb_up_alt_rounded), findsOneWidget);

    await _pumpBar(tester, bar({..._direction()}));
    await tester.pump();
    expect(find.byIcon(Icons.thumb_up_alt_rounded), findsOneWidget);
  });

  testWidgets(
    'Save invokes callback, persists the rendered board, works without a board contract',
    (tester) async {
      Map<String, dynamic>? captured;
      await _pumpBar(
        tester,
        OutfitActionBar(
          direction: _direction(),
          editorialCover: const {},
          primaryLabel: 'Office Look',
          missingName: '',
          shareBoundaryKey: GlobalKey(),
          saveBoardOverride:
              ({
                required occasion,
                required outfitDescription,
                required imageUrl,
                required title,
                required itemIds,
                required items,
                required isFavourite,
              }) async {
                captured = {
                  'occasion': occasion,
                  'title': title,
                  'imageUrl': imageUrl,
                  'itemIds': itemIds,
                  'items': items,
                  'desc': outfitDescription,
                };
                return 'doc-1';
              },
        ),
      );

      await _confirmSave(tester);

      expect(captured, isNotNull);
      expect(captured!['occasion'], 'office_fits');
      expect(captured!['title'], 'Office Look');
      expect(captured!['imageUrl'], 'https://x/shirt-cutout.png');
      expect(captured!['desc'], 'Sharp and balanced.');
      expect(
        (captured!['itemIds'] as List),
        containsAll(<String>['shirt-1', 'chino-1', 'loafer-1']),
      );
      expect((captured!['items'] as List).length, 3);
      expect(
        find.text('Saved'),
        findsOneWidget,
      ); // heart flips only after success
    },
  );

  testWidgets('Save uses the live board after three mutations', (tester) async {
    var liveBoard = {
      ..._direction(),
      'board_id': 'board-initial',
      'revision': 0,
    };
    Map<String, dynamic>? captured;

    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        currentDirectionOverride: () => liveBoard,
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              captured = {
                'board_id': liveBoard['board_id'],
                'revision': liveBoard['revision'],
                'itemIds': itemIds,
                'items': items,
              };
              return 'doc-live';
            },
      ),
    );

    for (var revision = 1; revision <= 3; revision++) {
      final itemId = 'shirt-$revision';
      liveBoard = {
        ...liveBoard,
        'board_id': 'board-$revision',
        'revision': revision,
        'board_items': [
          {
            'name': 'Shirt $revision',
            'item_id': itemId,
            'role': 'top',
            'image_url': 'https://x/$itemId.png',
            'masked_url': 'https://x/$itemId-cutout.png',
          },
        ],
      };
      await tester.pump();
    }

    await _confirmSave(tester);

    expect(captured?['board_id'], 'board-3');
    expect(captured?['revision'], 3);
    expect(captured?['itemIds'], <String>['shirt-3']);
    expect((captured?['items'] as List).single['item_id'], 'shirt-3');
  });

  testWidgets('Double-tap Save does not create duplicate saves', (
    tester,
  ) async {
    var calls = 0;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              calls++;
              return 'doc-$calls';
            },
      ),
    );

    await _confirmSave(tester);
    await tester.tap(find.text('Saved'));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets(
    'Save completion after navigation does not use disposed context',
    (tester) async {
      final pending = Completer<String?>();
      await _pumpBar(
        tester,
        OutfitActionBar(
          direction: _direction(),
          editorialCover: const {},
          primaryLabel: 'Office Look',
          missingName: '',
          shareBoundaryKey: GlobalKey(),
          saveBoardOverride:
              ({
                required occasion,
                required outfitDescription,
                required imageUrl,
                required title,
                required itemIds,
                required items,
                required isFavourite,
              }) => pending.future,
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save look'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      pending.complete('doc-1');
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Save failure restores the unsaved icon and surfaces an error', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              throw Exception('appwrite down');
            },
      ),
    );

    await _confirmSave(tester);

    expect(find.text('Saved'), findsNothing); // stays unsaved
    expect(find.text('Save'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('Appwrite null document is failure', (tester) async {
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async => null,
      ),
    );

    await _confirmSave(tester);

    expect(find.text('Saved'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets(
    'Share invokes capture and opens the share sheet with the title caption',
    (tester) async {
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
      expect(
        caption,
        contains('Office Look'),
      ); // caption carries the board title
    },
  );

  testWidgets(
    'Share capture failure falls back to text sharing (never does nothing)',
    (tester) async {
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
    },
  );

  testWidgets('Share surfaces a recoverable error when native sharing fails', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        captureOverride: () async => Uint8List.fromList(<int>[1, 2, 3]),
        shareImageOverride: (bytes, caption) async {
          throw StateError('image share unavailable');
        },
        shareTextOverride: (caption) async {
          throw StateError('text share unavailable');
        },
      ),
    );

    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not open the share sheet.'), findsOneWidget);
  });

  testWidgets('Save and Share remain enabled without a board contract', (
    tester,
  ) async {
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
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
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
    await _confirmSave(tester);

    expect(saved, isTrue);
    expect(shared, isTrue);
  });

  testWidgets('office is preselected and user can override category', (
    tester,
  ) async {
    String? selected;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              selected = occasion;
              return 'doc-1';
            },
      ),
    );

    await _confirmSave(tester, category: 'Vacation');
    expect(selected, 'vacation');
  });

  testWidgets('Favourite can be enabled during Save', (tester) async {
    bool? selectedFavourite;
    await _pumpBar(
      tester,
      OutfitActionBar(
        direction: _direction(),
        editorialCover: const {},
        primaryLabel: 'Office Look',
        missingName: '',
        shareBoundaryKey: GlobalKey(),
        saveBoardOverride:
            ({
              required occasion,
              required outfitDescription,
              required imageUrl,
              required title,
              required itemIds,
              required items,
              required isFavourite,
            }) async {
              selectedFavourite = isFavourite;
              return 'doc-1';
            },
      ),
    );

    await _confirmSave(tester, favourite: true);
    expect(selectedFavourite, isTrue);
  });

  testWidgets(
    'Lock/Shuffle stays disabled (no BoardMutationBar) without a contract, while Save/Share still render',
    (tester) async {
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

      expect(
        find.byType(BoardMutationBar),
        findsNothing,
      ); // lock/shuffle gated off
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    },
  );
}
