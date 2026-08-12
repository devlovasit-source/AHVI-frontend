// The exported Share PNG must be opaque (never black in dark-mode chat apps),
// show branding + title + occasion + a tight garment canvas + a small footer,
// exclude the why-it-works / styling-tip paragraphs, and still capture to
// non-empty PNG bytes.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/shareable_outfit_board.dart';

const _items = <ShareBoardItem>[
  ShareBoardItem(role: 'top', imageUrl: 'https://x/top.png'),
  ShareBoardItem(role: 'bottom', imageUrl: 'https://x/bottom.png'),
  ShareBoardItem(role: 'footwear', imageUrl: 'https://x/shoe.png'),
];

Future<GlobalKey> _pump(
  WidgetTester tester, {
  double width = 360,
  String title = 'Understated Ease',
  String occasion = 'Office',
  List<ShareBoardItem> items = _items,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ShareableOutfitBoard(
            boundaryKey: key,
            title: title,
            occasion: occasion,
            items: items,
            width: width,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

void main() {
  testWidgets('exported board has an explicit opaque background', (
    tester,
  ) async {
    await _pump(tester);
    final opaque = find.byWidgetPredicate(
      (w) => w is Container && w.color == ShareableOutfitBoard.kShareBackground,
    );
    expect(opaque, findsOneWidget);
    // The opaque fill is inside the capture boundary.
    expect(
      find.descendant(of: find.byType(RepaintBoundary), matching: opaque),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'title, occasion, branding and footer are visible; paragraphs excluded',
    (tester) async {
      await _pump(tester);
      expect(find.text('Understated Ease'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('AHVI'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText() == 'Styled on AHVI',
        ),
        findsOneWidget,
      );
      // No why-it-works / styling-tip copy baked into the share image.
      expect(find.textContaining('why'), findsNothing);
      expect(find.textContaining('styling tip'), findsNothing);
    },
  );

  testWidgets('three garment roles render', (tester) async {
    await _pump(tester);
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('no overflow at a Samsung-width equivalent', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, width: 380);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture returns non-empty PNG bytes', (tester) async {
    final key = await _pump(tester);
    final bytes = await tester.runAsync(() async {
      final ro =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    });
    expect(bytes, isNotNull);
    expect((bytes as Uint8List).isNotEmpty, isTrue);
  });

  testWidgets('empty items still produce a safe opaque board', (tester) async {
    await _pump(tester, items: const []);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container && w.color == ShareableOutfitBoard.kShareBackground,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
