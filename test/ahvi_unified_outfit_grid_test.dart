import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

const _accent = AccentPalette(
  primary: Color(0xFF6B91FF),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  test(
    'safe parsed and saved frozen images retain their selected provenance',
    () {
      for (final frozen in [false, true]) {
        final item = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
          StyleBoardItem.fromJson({
            'item_id': 'safe',
            'name': 'Top',
            'slot': 'top',
            'image_url': frozen
                ? 'https://test/safe.png'
                : 'https://test/raw.png',
            'original_image_url': 'https://test/raw.png',
            if (frozen) ...{
              'selected_field': 'normalized_url',
              'source_kind': 'catalog_fallback',
              'expected_transparent': false,
            } else
              'normalized_url': 'https://test/safe.png',
          }),
          surface: 'style_board_saved',
        );
        expect(item.resolvedImageUrl, 'https://test/safe.png');
        expect(item.sourceKind, 'catalog_fallback');
        expect(item.isTransparent, isFalse);
        expect(item.imageCandidates.single.url, item.resolvedImageUrl);
      }
    },
  );
  for (final surface in [
    'style_board_active_unified_grid',
    'style_this_unified_grid',
  ]) {
    testWidgets(
      'P0 $surface tries safe alternative after preferred image fails',
      (tester) async {
        final item = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
          StyleBoardItem.fromJson({
            'item_id': 'fallback',
            'name': 'Top',
            'slot': 'top',
            'image_url': 'https://test/raw.png',
            'normalized_url': 'https://test/normalized.png',
            'masked_url': 'https://test/masked.png',
            'display_image_url': 'https://test/raw.png?alias=true',
          }),
          surface: surface,
        );
        final attempted = <String>[];
        final preferred = surface == 'style_this_unified_grid'
            ? 'https://test/normalized.png'
            : 'https://test/masked.png';
        final fallback = surface == 'style_this_unified_grid'
            ? 'https://test/masked.png'
            : 'https://test/normalized.png';
        final pending = Completer<ImageInfo>();
        await _pumpGrid(
          tester,
          width: 390,
          items: [item],
          imageProviderBuilder: (url) {
            if (attempted.isEmpty || attempted.last != url) attempted.add(url);
            return _ControlledImageProvider(pending.future);
          },
        );
        expect(attempted, [preferred]);
        var image = tester.widget<Image>(find.byType(Image));
        image.errorBuilder!(
          tester.element(find.byType(Image)),
          Exception('403'),
          null,
        );
        await tester.pump();
        await tester.pump();
        expect(attempted, [preferred, fallback]);
        pending.complete(ImageInfo(image: await _testImage()));
        await tester.pump();
        expect(find.byIcon(Icons.checkroom), findsNothing);
        image = tester.widget<Image>(find.byType(Image));
        image.errorBuilder!(
          tester.element(find.byType(Image)),
          Exception('decode'),
          null,
        );
        await tester.pump();
        await tester.pump();
        expect(find.byIcon(Icons.checkroom), findsOneWidget);
        expect(attempted, [preferred, fallback]);
      },
    );
  }

  for (final labels in [false, true]) {
    testWidgets('P0 ninth locked garment is not truncated (labels=$labels)', (
      tester,
    ) async {
      final toggled = <String>[];
      await _pumpGrid(
        tester,
        width: 390,
        height: 1100,
        showItemLabels: labels,
        items: [
          ..._items(8),
          const AhviUnifiedOutfitGridItem(
            id: 'ninth',
            name: 'Ninth',
            category: 'accessory',
            resolvedImageUrl: '',
            isLocked: true,
          ),
        ],
        onToggleLock: toggled.add,
      );
      expect(find.byKey(const ValueKey('ninth')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lock-ninth')));
      expect(toggled, ['ninth']);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('same five-item fixture always has identical grid geometry', (
    tester,
  ) async {
    final geometries = <List<Rect>>[];
    for (final surface in ['normal-style', 'style-this', 'daily-wear']) {
      await _pumpGrid(tester, width: 390, items: _items(5, source: surface));
      geometries.add([
        for (var i = 0; i < 5; i++)
          tester.getRect(find.byKey(ValueKey('item-$i'))),
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(geometries[1], geometries[0]);
    expect(geometries[2], geometries[0]);
  });

  testWidgets('3-6 items remain responsive at supported phone widths', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 384.0, 390.0, 430.0]) {
      for (final count in [3, 4, 5, 6]) {
        await _pumpGrid(tester, width: width, items: _items(count));
        final gridRect = tester.getRect(find.byType(AhviUnifiedOutfitGrid));
        expect(gridRect.height, greaterThan(100));
        expect(gridRect.height, lessThan(500));
        for (var i = 0; i < count; i++) {
          final itemRect = tester.getRect(find.byKey(ValueKey('item-$i')));
          expect(gridRect.inflate(0.1).contains(itemRect.topLeft), isTrue);
          expect(gridRect.inflate(0.1).contains(itemRect.bottomRight), isTrue);
          expect(itemRect.shortestSide, greaterThan(50));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  group('showItemLabels (Daily Wear only)', () {
    testWidgets('default (Style Board) surfaces render no item names', (
      tester,
    ) async {
      await _pumpGrid(tester, width: 390, items: _items(3));
      expect(find.text('Item 0'), findsNothing);
    });

    testWidgets('labelled surface shows the item name below each tile', (
      tester,
    ) async {
      await _pumpGrid(
        tester,
        width: 390,
        items: _items(3),
        showItemLabels: true,
      );
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });

    testWidgets('falls back to category when no usable name exists', (
      tester,
    ) async {
      await _pumpGrid(
        tester,
        width: 390,
        items: [
          const AhviUnifiedOutfitGridItem(
            id: 'i0',
            name: '',
            category: 'Top',
            resolvedImageUrl: 'https://example.test/i0.png',
          ),
        ],
        showItemLabels: true,
      );
      expect(find.text('Top'), findsOneWidget);
    });

    testWidgets('never exposes the raw item id as a label', (tester) async {
      await _pumpGrid(
        tester,
        width: 390,
        items: [
          const AhviUnifiedOutfitGridItem(
            id: 'wardrobe_item_9f2c1',
            name: '',
            category: '',
            resolvedImageUrl: 'https://example.test/i0.png',
          ),
        ],
        showItemLabels: true,
      );
      expect(find.text('wardrobe_item_9f2c1'), findsNothing);
    });

    for (final size in [Size(360, 640), Size(360, 800), Size(412, 915)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'no overflow at ${size.width.toInt()}x${size.height.toInt()} '
          '@${scale}x text scale',
          (tester) async {
            await _pumpGrid(
              tester,
              width: size.width,
              height: size.height,
              items: [
                for (var i = 0; i < 3; i++)
                  AhviUnifiedOutfitGridItem(
                    id: 'item-$i',
                    name: 'A Genuinely Long Wardrobe Item Name Number $i',
                    category: 'Top',
                    resolvedImageUrl: 'https://example.test/long-$i.png',
                  ),
              ],
              showItemLabels: true,
              textScale: scale,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  testWidgets('anchor remains visible and locked', (tester) async {
    await _pumpGrid(
      tester,
      width: 390,
      items: [
        ..._items(1).map(
          (item) => AhviUnifiedOutfitGridItem(
            id: item.id,
            name: item.name,
            category: item.category,
            resolvedImageUrl: item.resolvedImageUrl,
            isAnchor: true,
            isLocked: true,
          ),
        ),
        ..._items(4).skip(1),
      ],
      onToggleLock: (_) {},
    );
    expect(find.byKey(const ValueKey('item-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-item-0')), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('delayed and broken images retain individual slots', (
    tester,
  ) async {
    final delayed = Completer<ImageInfo>();
    final provider = _ControlledImageProvider(delayed.future);
    await _pumpGrid(
      tester,
      width: 390,
      items: _items(3),
      imageProvider: provider,
    );
    final before = tester.getRect(find.byKey(const ValueKey('item-0')));
    expect(before.size, isNot(Size.zero));
    expect(
      find.byKey(const ValueKey('unified-grid-image-loading')),
      findsNWidgets(3),
    );

    delayed.complete(ImageInfo(image: await _testImage()));
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('item-0'))), before);
  });

  testWidgets(
    'image decode is constrained to the rendered card size, DPR-capped, '
    'aspect-ratio preserved',
    (tester) async {
      tester.view.devicePixelRatio = 3.0; // exceeds the 2x decode cap
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGrid(tester, width: 390, items: _items(1));

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      expect(resize.policy, ResizeImagePolicy.fit);
      expect(resize.imageProvider, isA<NetworkImage>());
      expect(
        (resize.imageProvider as NetworkImage).url,
        'https://example.test/fixture-0.png',
      );

      final cardSize = tester.getSize(find.byType(Image));
      final cappedWidth = (cardSize.width * 2.0).round();
      final cappedHeight = (cardSize.height * 2.0).round();
      final uncappedWidth = (cardSize.width * 3.0).round();
      expect(resize.width, cappedWidth);
      expect(resize.height, cappedHeight);
      // Proves the DPR cap actually did something, not a coincidental match.
      expect(resize.width, isNot(uncappedWidth));
    },
  );

  testWidgets(
    'default network image path keeps frameBuilder/errorBuilder/fit intact',
    (tester) async {
      await _pumpGrid(tester, width: 390, items: _items(1));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.frameBuilder, isNotNull);
      expect(image.errorBuilder, isNotNull);
      expect(image.fit, BoxFit.contain);
    },
  );

  test('surface-name change (board-surface classification fix) leaves locked '
      'anchor identity unaffected', () {
    final anchor = StyleBoardItem.fromJson({
      'item_id': 'anchor-1',
      'name': 'Blazer',
      'slot': 'top',
      'role': 'top',
      'source': 'wardrobe',
      'image_url': 'https://example.test/anchor.png',
      'board_status': 'cutout_ready',
      'board_image_url': 'https://example.test/anchor-board.png',
    });
    final before = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
      anchor,
      isAnchor: true,
      isLocked: true,
      surface: 'active_style_unified_grid', // pre-fix surface name
    );
    final after = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
      anchor,
      isAnchor: true,
      isLocked: true,
      surface: 'style_board_active_unified_grid', // post-fix surface name
    );
    expect(after.id, before.id);
    expect(after.id, 'anchor-1');
    expect(after.isAnchor, isTrue);
    expect(after.isLocked, isTrue);
    expect(after.category, before.category);
  });

  test('P0 parsed metadata cannot resurrect an explicitly raw image', () {
    const url = 'https://example.test/parsed-catalog.png';
    const item = StyleBoardItem(
      id: 'parsed-1',
      name: 'Top',
      imageUrl: url,
      category: 'top',
      role: BoardItemRole.top,
      raw: {
        'image_url': url,
        'original_image_url': url,
        '_image_field': 'normalized_url',
        '_image_source_kind': 'catalog_fallback',
        '_image_expected_transparent': false,
      },
    );

    final gridItem = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
      item,
      surface: 'style_board_daily_wear_unified_grid',
    );

    expect(gridItem.resolvedImageUrl, isEmpty);
  });

  test('grid does not retain an unvalidated raw image', () {
    const item = StyleBoardItem(
      id: 'raw-1',
      name: 'Top',
      imageUrl: 'https://example.test/raw-upload.png',
      category: 'top',
      role: BoardItemRole.top,
      raw: {
        'image_url': 'https://example.test/raw-upload.png',
        '_image_field': 'none',
      },
    );

    final gridItem = AhviUnifiedOutfitGridItem.fromStyleBoardItem(
      item,
      surface: 'style_board_daily_wear_unified_grid',
    );

    expect(gridItem.resolvedImageUrl, isEmpty);
  });
}

List<AhviUnifiedOutfitGridItem> _items(
  int count, {
  String source = 'fixture',
}) => [
  for (var i = 0; i < count; i++)
    AhviUnifiedOutfitGridItem(
      id: 'item-$i',
      name: 'Item $i',
      category: i == 0 ? 'top' : 'accessory',
      resolvedImageUrl: 'https://example.test/$source-$i.png',
    ),
];

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  required List<AhviUnifiedOutfitGridItem> items,
  ValueChanged<String>? onToggleLock,
  ImageProvider? imageProvider,
  ImageProvider<Object> Function(String)? imageProviderBuilder,
  bool showItemLabels = false,
  double height = 700,
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: BaseTheme.light.copyWith(
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AhviUnifiedOutfitGrid(
                  items: items,
                  onToggleLock: onToggleLock,
                  imageProviderBuilder:
                      imageProviderBuilder ??
                      (imageProvider == null ? null : (_) => imageProvider),
                  showItemLabels: showItemLabels,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  final Future<ImageInfo> image;
  const _ControlledImageProvider(this.image);
  @override
  Future<_ControlledImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) async => this;
  @override
  ImageStreamCompleter loadImage(
    _ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(image);
}

Future<ui.Image> _testImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = Colors.white,
  );
  return recorder.endRecording().toImage(1, 1);
}
