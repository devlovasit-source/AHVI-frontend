import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

const _fixturePngs = <String, String>{
  'kurta-1':
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABgCAYAAACtxXToAAABXElEQVR42u2awQ3CMBAEw3YAxdAHX0R5iC99UAyUAF8ECTH22RdfZp8R8e3OniWEGAaEEEIIIbRObWodfD/vn5/PtodL8vuP6/Hr2e50M/erlrTHQpV8brEAxtpf6rlqfefm2m3ZfhUAtdqvdX7zDfjVcuv2zQHUbr/GHJcNGGvbo31TAK3at57ntgHvrXu1bwagdfuWc103wLt9EwBe7VvNV8/hLXyo9/ClfhQhfIkvRQmf60+Rwuf4VLTw//pVxPD/+FbU8Kn+FTl8Sg5FDz+XZxJAjZ+gPTWVR8PKpRxqUdpP2oDeIcz5l8UhHqCsPKmVGS8IZgB6uwqpflV6qDeYUk/qcfUtfSh32NKuRK4v9dy8hS++CQIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYOC/wmwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQgghhELpBeEUm37qsApQAAAAAElFTkSuQmCC',
  'bottom-1':
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABgCAYAAACtxXToAAAAx0lEQVR42u3a0QmDMBSG0RtxjuJT3rqBdIIu4kQu4gQupjs00KS95xtA8PArokZIkqSsldYDnMd+9T6J13v7+Dym7AsAAAAAAAAAAABI29x6gKU+LQAAgH496losAAAAAAB6AbTehS0AAAAAAAAAAAAAAAAAAAAAAAAAAAAA8cX3kRYA4A9mbAEAAAAAAAAAAAAAAPwWwAi/11gAAAAAIvO/ghYAAAAAAAAi52exYQB6Pke4BAAAyPsyxAIAAAAAAAAASZKUtBvj1Amglc8VNwAAAABJRU5ErkJggg==',
  'shoe-1':
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABgCAYAAACtxXToAAAA8ElEQVR42u3ZwXHDIBBAUZZ6fM6kjBTgs4vKOQW4DE/O6ccuIYlHZhd4rwLpCyFArQEAAAAAAAAAAAAAADzh8/x2r3ptMfKmL1/fsXyA3552tQiRMcQrRYis97pKhMic0CpEiOxZPDtC3/0T2dvm64Re5eKyIpQYAZkRSgXIiFAuwOgIJQOMjBCz7ORetV6I2baxR4eIWffxR8WYOsARMZYJ8GyM3tqaR3B/fXhLjoD/jIq+w81v9woIcESAikfYw0fADhH6TEfYr1gX9NnO8dMmwVUj9Fn/6Aw7D/h4Py2xILrefsI6QAABAAAAoLX2APy7Ww3uoHLEAAAAAElFTkSuQmCC',
};

var _fixtureImageRequestCount = 0;

class _FixtureImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (method != 'GET') {
      throw StateError('Unexpected $method request in visual-board test: $url');
    }
    return getUrl(url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _fixtureImageRequestCount++;
    if (url.scheme != 'https' || url.host != 'example.test') {
      throw StateError('Unexpected network request in visual-board test: $url');
    }
    final fileName = url.pathSegments.last;
    final fixtureId = fileName.endsWith('.png')
        ? fileName.substring(0, fileName.length - 4)
        : '';
    if (fixtureId == 'bag-1') {
      return _FixtureImageRequest(
        File(
          'assets/style_assets/accessories/bags/bag_04.jpg',
        ).readAsBytesSync(),
      );
    }
    final encoded = _fixturePngs[fixtureId.replaceFirst('-next', '')];
    if (encoded == null) {
      throw StateError('Missing deterministic PNG fixture for $url');
    }
    return _FixtureImageRequest(base64Decode(encoded));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureImageRequest implements HttpClientRequest {
  _FixtureImageRequest(this.bytes);

  final Uint8List bytes;

  @override
  final HttpHeaders headers = _FixtureHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = false;

  @override
  int contentLength = 0;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async => _FixtureImageResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureImageResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FixtureImageResponse(this.bytes);

  final Uint8List bytes;

  @override
  late final HttpHeaders headers = _FixtureHttpHeaders(bytes.length);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHttpHeaders implements HttpHeaders {
  _FixtureHttpHeaders([int? contentLength]) {
    if (contentLength != null) {
      set(HttpHeaders.contentLengthHeader, contentLength);
    }
    set(HttpHeaders.contentTypeHeader, 'image/png');
  }

  final Map<String, List<String>> _values = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => this[name]?.join(', ');

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<T> _withFixtureImages<T>(Future<T> Function() body) async {
  debugNetworkImageHttpClientProvider = () => _FixtureImageHttpClient();
  try {
    return await HttpOverrides.runZoned(
      body,
      createHttpClient: (_) => _FixtureImageHttpClient(),
    );
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

Map<String, dynamic> _boardItem(
  String id,
  String name,
  String slot, {
  required double x,
  required double y,
  required double width,
  required double height,
  int z = 1,
}) => {
  'item_id': id,
  'name': name,
  'slot': slot,
  'role': slot,
  'source': 'wardrobe',
  'image_url': 'https://example.test/original-$id.jpg',
  'board_image_url': 'https://example.test/$id.png',
  'board_status': 'cutout_ready',
  'position': {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': 0,
    'z': z,
  },
};

final _direction = <String, dynamic>{
  'board_id': '11111111-1111-4111-8111-111111111111',
  'revision': 3,
  'scenario': 'recommendation',
  'source_policy': 'wardrobe',
  'shuffle_available': true,
  'direction_name': 'Sunlit Traditional',
  'style_archetype': 'Sunlit Traditional',
  'occasion': 'Haldi',
  'adjectives': ['Festive', 'Relaxed', 'Bright'],
  'board_items': [
    _boardItem(
      'kurta-1',
      'Marigold Yellow Cotton Kurta',
      'top',
      x: .06,
      y: .08,
      width: .48,
      height: .58,
    ),
    _boardItem(
      'bottom-1',
      'Cream Churidar Trousers',
      'bottom',
      x: .55,
      y: .08,
      width: .38,
      height: .36,
    ),
    _boardItem(
      'shoe-1',
      'Embroidered Mojaris',
      'footwear',
      x: .58,
      y: .50,
      width: .34,
      height: .24,
      z: 2,
    ),
    {
      ..._boardItem(
        'bag-1',
        'Structured Handbag',
        'accessory',
        x: .72,
        y: .12,
        width: .22,
        height: .20,
        z: 3,
      ),
      'category': 'bag',
      // Opaque catalog accessory: no cutout exists, only a garment-only
      // normalized/catalog image. Board-safe (catalog_fallback) → one frame,
      // never promoted to cutout_ready.
      'board_image_url': null,
      'board_status': 'catalog_fallback',
      'normalized_url': 'https://example.test/bag-1.png',
    },
  ],
  'why_it_works': 'Warm festive color with a clean traditional silhouette.',
  'styling_tip':
      'Keep accessories minimal so the marigold kurta stays central.',
  'description':
      'This deliberately long report description must not appear on the Phase 1 card.',
  'badge': {'occasion_fit': 'Inspiring', 'wardrobe_match_pct': 88},
  'owned_items': [
    {'name': 'Existing Cream Trousers', 'category': 'bottom'},
  ],
  'missing_piece': {
    'name': 'Ethnic Footwear',
    'category': 'footwear',
    'reason': 'Completes the festive look.',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fixtureImageRequestCount = 0;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('canonical title precedence is stable', () {
    // P0.8: an explicit backend title now outranks every archetype/strategy
    // fallback tier — it wins here even though selected_archetype and
    // style_strategy.archetype are both also present.
    expect(
      resolveOutfitBoardTitle({
        'selected_archetype': {'title': 'Refined Weekend'},
        'style_strategy': {'archetype': 'Understated Polish'},
        'title': 'Legacy Board',
      }),
      'Legacy Board',
    );
    // Without an explicit title, selected_archetype is next.
    expect(
      resolveOutfitBoardTitle({
        'selected_archetype': {'title': 'Refined Weekend'},
        'style_strategy': {'archetype': 'Understated Polish'},
      }),
      'Refined Weekend',
    );
    // Without title or selected_archetype, style_strategy.archetype is next.
    expect(
      resolveOutfitBoardTitle({
        'style_strategy': {'archetype': 'Understated Polish'},
      }),
      'Understated Polish',
    );
    // Without any archetype tier, style_strategy.direction_title is next.
    expect(
      resolveOutfitBoardTitle({
        'style_strategy': {'direction_title': 'Effortless Edge'},
      }),
      'Effortless Edge',
    );
    expect(resolveOutfitBoardTitle({'title': 'Legacy Board'}), 'Legacy Board');
    expect(resolveOutfitBoardTitle({}), 'Styled for You');
  });

  testWidgets('Phase 1 keeps the board and removes report-style content', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 320);

    expect(find.text('Sunlit Traditional'), findsOneWidget);
    expect(find.text('Legacy Editorial Cover'), findsNothing);
    expect(find.text('Haldi'), findsOneWidget);
    expect(find.text('Festive'), findsOneWidget);
    expect(find.text('Relaxed'), findsNothing);
    expect(find.byKey(const ValueKey<String>('kurta-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('bottom-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('shoe-1')), findsOneWidget);
    expect(_fixtureImageRequestCount, 4);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);

    expect(find.text('Recommended'), findsNothing);
    expect(find.textContaining('Occasion Fit'), findsNothing);
    expect(find.textContaining('Wardrobe Match'), findsNothing);
    expect(
      find.text('Warm festive color with a clean traditional silhouette.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Keep accessories minimal so the marigold kurta stays central.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('long report description'), findsNothing);
    expect(find.text('Existing Cream Trousers'), findsNothing);
    expect(find.text('Missing: Ethnic Footwear'), findsNothing);
    expect(find.textContaining('Shuffle'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Dislike'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Style This'), findsNothing);
    expect(find.text('Missing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium hierarchy puts one title and context above the canvas', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 320);

    final title = find.text('Sunlit Traditional');
    final canvas = find.byKey(const ValueKey('editorial-outfit-canvas'));
    expect(title, findsOneWidget);
    expect(canvas, findsOneWidget);
    expect(tester.getTopLeft(title).dy, lessThan(tester.getTopLeft(canvas).dy));
  });

  testWidgets('selected archetype wins and meaningful context is not clipped', (
    tester,
  ) async {
    await _pumpBoard(
      tester,
      use85Layout: true,
      width: 320,
      direction: {
        ..._direction,
        'selected_archetype': {'title': 'Refined Weekend'},
        'occasion': 'daily',
        'dress_code': 'Smart Casual',
        'style_strategy': {'direction_title': 'Understated Polish'},
      },
    );

    expect(find.text('Refined Weekend'), findsOneWidget);
    expect(find.text('Understated Polish'), findsOneWidget);
    expect(find.text('Understated Po...'), findsNothing);
    expect(find.text('Smart Casual'), findsOneWidget);
    expect(find.text('daily'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('editorial-outfit-canvas')));
    await tester.pumpAndSettle();
    expect(find.text('Refined Weekend'), findsNWidgets(2));
    expect(find.textContaining('Marigold Yellow Cotton Kurta'), findsOneWidget);
  });

  testWidgets('reasoning keeps WHY IT WORKS bounded; Styling Tip renders in full', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 320);

    final canvas = find.byKey(const ValueKey('editorial-outfit-canvas'));
    final why = find.byKey(const ValueKey('style-why-it-works'));
    final tip = find.byKey(const ValueKey('style-styling-tip'));
    expect(
      tester.getTopLeft(why).dy,
      greaterThan(tester.getTopLeft(canvas).dy),
    );
    // WHY IT WORKS is untouched by this fix.
    expect(tester.widget<Text>(why).maxLines, 2);
    expect(tester.widget<Text>(why).overflow, TextOverflow.ellipsis);
    // Styling Tip is no longer line-limited or ellipsized.
    expect(tester.widget<Text>(tip).maxLines, isNull);
    expect(tester.widget<Text>(tip).overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('recommendation cards reserve equal outer and canvas heights', (
    tester,
  ) async {
    final directions = [
      for (var index = 0; index < 3; index++)
        {
          ..._direction,
          'board_id': '00000000-0000-4000-8000-00000000000$index',
          'direction_name': 'Board $index',
          'style_archetype': 'Board $index',
        },
    ];
    await _pumpBoard(
      tester,
      use85Layout: true,
      directions: directions,
      width: 320,
    );

    final cards = find.byType(AhviOutfitBoardCard);
    final canvases = find.byKey(
      const ValueKey<String>('editorial-outfit-canvas'),
    );
    expect(cards, findsNWidgets(3));
    expect(canvases, findsNWidgets(3));
    final cardHeights = [
      for (var i = 0; i < 3; i++) tester.getSize(cards.at(i)).height,
    ];
    final canvasHeights = [
      for (var i = 0; i < 3; i++) tester.getSize(canvases.at(i)).height,
    ];
    expect(cardHeights, everyElement(closeTo(cardHeights.first, 0.01)));
    expect(canvasHeights, everyElement(closeTo(canvasHeights.first, 0.01)));
    expect(
      canvasHeights.first,
      closeTo(editorialBoardCanvasHeightForWidth(320), 0.01),
    );
  });

  testWidgets(
      'long WHY copy stays bounded; long Styling Tip renders in full without shrinking the canvas',
      (tester) async {
    const fullTip =
        'Keep the supporting accents deliberate and let the main garment lead the composition through the evening.';
    await _pumpBoard(
      tester,
      use85Layout: true,
      width: 320,
      direction: {
        ..._direction,
        'direction_name':
            'A very long editorial title that remains readable and bounded',
        'style_archetype':
            'A very long editorial title that remains readable and bounded',
        'why_it_works':
            'The warm silhouette balances the occasion with an easy proportion that should end at a clean boundary.',
        'styling_tip': fullTip,
      },
    );

    final canvas = find.byKey(const ValueKey('editorial-outfit-canvas'));
    final why = tester.widget<Text>(
      find.byKey(const ValueKey('style-why-it-works')),
    );
    final tip = tester.widget<Text>(
      find.byKey(const ValueKey('style-styling-tip')),
    );
    // The canvas (board grid/images) never grows or shrinks from copy length.
    expect(
      tester.getSize(canvas).height,
      closeTo(editorialBoardCanvasHeightForWidth(320), 0.01),
    );
    expect(why.maxLines, 2);
    expect(why.overflow, TextOverflow.ellipsis);
    expect(why.data, contains('clean boundary'));
    // Styling Tip: no truncation, complete sentence rendered.
    expect(tip.maxLines, isNull);
    expect(tip.overflow, isNot(TextOverflow.ellipsis));
    expect(tip.data, fullTip);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long copy remains usable at narrow width and large text scale', (
    tester,
  ) async {
    await _withFixtureImages(() async {
      await tester.binding.setSurfaceSize(const Size(320, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _testApp(
          textScaler: const TextScaler.linear(1.8),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: VisualDirectionCarousel(
                directions: [
                  {
                    ..._direction,
                    'why_it_works':
                        'The warm silhouette balances the occasion with an easy proportion that should end at a clean boundary.',
                    'styling_tip':
                        'Keep the supporting accents deliberate and let the main garment lead the composition through the evening.',
                  },
                ],
                cardWidth: 286,
                curationReveal: false,
                use85Layout: true,
                onSendMessage: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('style-why-it-works')), findsOneWidget);
      expect(find.byKey(const ValueKey('style-styling-tip')), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('style-why-it-works')))
            .overflow,
        TextOverflow.ellipsis,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('style-styling-tip')))
            .overflow,
        isNot(TextOverflow.ellipsis),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('style-styling-tip')))
            .maxLines,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'Styling Tip: deliberately long copy renders past 2 lines at width 360 and textScale 1.3, no overflow',
      (tester) async {
    const longTip =
        'Layer a lightweight overshirt for the early evening chill, keep the '
        'footwear polished but low-key, and let the accessories stay minimal '
        'so the tailoring does the talking from arrival through to the last '
        'toast of the night.';
    await _withFixtureImages(() async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _testApp(
          textScaler: const TextScaler.linear(1.3),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: VisualDirectionCarousel(
                directions: [
                  {..._direction, 'styling_tip': longTip},
                ],
                cardWidth: 360,
                curationReveal: false,
                use85Layout: true,
                onSendMessage: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tipFinder = find.byKey(const ValueKey('style-styling-tip'));
      // A. key exists
      expect(tipFinder, findsOneWidget);
      final tip = tester.widget<Text>(tipFinder);
      // B. no longer line-limited
      expect(tip.maxLines, isNull);
      // C. not configured with ellipsis
      expect(tip.overflow, isNot(TextOverflow.ellipsis));
      // D. full sentence present, unabridged
      expect(tip.data, longTip);
      // F. renders past 2 lines with no RenderFlex overflow / exception
      final renderedHeight = tester.getSize(tipFinder).height;
      final singleLineHeight = (tip.style?.fontSize ?? 14) * (tip.style?.height ?? 1.2);
      expect(renderedHeight, greaterThan(singleLineHeight * 2));
      expect(tester.takeException(), isNull);
      // G. WHY IT WORKS unaffected by this fix.
      final why = tester.widget<Text>(
        find.byKey(const ValueKey('style-why-it-works')),
      );
      expect(why.maxLines, 2);
      expect(why.overflow, TextOverflow.ellipsis);
    });
  });

  testWidgets('cutouts stay unframed and opaque accessory gets one frame', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 320);

    expect(find.byKey(const ValueKey('cutout-kurta-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cutout-bottom-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cutout-shoe-1')), findsOneWidget);
    final frame = find.byKey(const ValueKey('fallback-bag-1'));
    expect(frame, findsOneWidget);
    final frameWidget = tester.widget<Container>(frame);
    expect(frameWidget.padding, const EdgeInsets.all(6));
    expect((frameWidget.decoration! as BoxDecoration).color, isNotNull);
    expect(
      tester.widget<Image>(
        find.descendant(of: frame, matching: find.byType(Image)),
      ),
      isA<Image>().having((image) => image.fit, 'fit', BoxFit.cover),
    );
  });

  testWidgets('legacy masked accessory stays unframed', (tester) async {
    final items = (List<Map<String, dynamic>>.from(
      _direction['board_items'] as List,
    )).map(Map<String, dynamic>.from).toList();
    items[3] = {
      ...items[3],
      'masked_url': 'https://example.test/kurta-1.png',
      'board_image_url': null,
      'image_url': null,
      'board_status': null,
    };
    await _pumpBoard(
      tester,
      use85Layout: true,
      direction: {..._direction, 'board_items': items},
    );

    expect(find.byKey(const ValueKey('cutout-bag-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback-bag-1')), findsNothing);
  });

  testWidgets('failed cutout activates exactly one catalog frame', (
    tester,
  ) async {
    final items = (List<Map<String, dynamic>>.from(
      _direction['board_items'] as List,
    )).map(Map<String, dynamic>.from).toList();
    items[0] = {
      ...items[0],
      'board_image_url': 'https://example.test/missing-cutout.png',
      'normalized_url': 'https://example.test/bag-1.png',
      'image_url': null,
    };
    await _pumpBoard(
      tester,
      use85Layout: true,
      direction: {..._direction, 'board_items': items},
    );

    final frame = find.byKey(const ValueKey('fallback-kurta-1'));
    expect(frame, findsOneWidget);
    expect(find.byKey(const ValueKey('cutout-kurta-1')), findsNothing);
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey<String>('vscale-kurta-1')),
          )
          .transform
          .getMaxScaleOnAxis(),
      1,
    );
    expect(tester.widget<Container>(frame).padding, const EdgeInsets.all(6));
  });

  testWidgets('duplicate titles open the exact tapped board pieces', (
    tester,
  ) async {
    final boardA = Map<String, dynamic>.from(_direction)
      ..['direction_name'] = 'Duplicate title'
      ..['style_archetype'] = 'Duplicate title';
    final boardBItems = (List<Map<String, dynamic>>.from(
      _direction['board_items'] as List,
    )).map(Map<String, dynamic>.from).toList();
    boardBItems[0] = {...boardBItems[0], 'name': 'Teal Shirt Board B'};
    final boardB = <String, dynamic>{
      ..._direction,
      'board_id': '22222222-2222-4222-8222-222222222222',
      'direction_name': 'Duplicate title',
      'style_archetype': 'Duplicate title',
      'board_items': boardBItems,
    };
    await _pumpBoard(
      tester,
      use85Layout: true,
      directions: [boardA, boardB],
      surface: const Size(430, 900),
    );

    final secondBoard = find.byKey(
      const ValueKey('vd-board-22222222-2222-4222-8222-222222222222-3'),
    );
    await tester.drag(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      const Offset(-390, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: secondBoard,
        matching: find.byKey(const ValueKey('editorial-outfit-canvas')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Teal Shirt Board B'), findsOneWidget);
    expect(find.textContaining('Marigold Yellow Cotton Kurta'), findsNothing);
  });

  testWidgets('connected Shuffle invokes the injected backend action', (
    tester,
  ) async {
    var apiCalls = 0;
    StyleBoardState? captured;
    Map<String, dynamic>? tappedBoard;
    await _pumpConnectedBoard(
      tester,
      onTapBoard: (board) => tappedBoard = board,
      shuffleCall: (state) async {
        apiCalls++;
        captured = state.deepCopy();
        return StyleBoardShuffleResult(
          boardId: state.boardId,
          revision: state.revision + 1,
          previousRevision: state.revision,
          lockedItemsPreserved: true,
          changedSlots: state.items.map((item) => item.slot).toList(),
          items: state.items
              .map(
                (item) => StyleBoardItem.fromJson(
                  _boardItem(
                    '${item.itemId}-next',
                    item.name,
                    item.slot,
                    x: item.position!.x!,
                    y: item.position!.y!,
                    width: item.position!.width!,
                    height: item.position!.height!,
                    z: item.position!.z ?? 1,
                  ),
                ),
              )
              .toList(),
          scenario: state.scenario,
          sourcePolicy: state.sourcePolicy,
        );
      },
    );

    await tester.tap(find.text('Shuffle unlocked pieces'));
    await _settleFixtureImages(tester);

    expect(apiCalls, 1);
    expect(captured!.boardId, '11111111-1111-4111-8111-111111111111');
    expect(captured!.revision, 3);
    expect(captured!.scenario, 'build_outfit');
    expect(captured!.sourcePolicy, 'wardrobe');
    expect(find.byKey(const ValueKey<String>('kurta-1-next')), findsOneWidget);

    await tester.tap(find.text('Sunlit Traditional'));
    expect(tappedBoard?['revision'], 4);
    final tappedItems = (tappedBoard?['board_items'] as List).whereType<Map>();
    expect(
      tappedItems.map((item) => item['item_id']),
      contains('kurta-1-next'),
    );
    expect(
      tappedItems.map((item) => item['item_id']),
      isNot(contains('kurta-1')),
    );
  });

  testWidgets('footer Shuffle never sends a conversational fallback', (
    tester,
  ) async {
    final sent = <String>[];
    await _pumpBoard(tester, use85Layout: true, onSendMessage: sent.add);

    expect(find.textContaining('Shuffle'), findsNothing);
    expect(sent, isEmpty);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Dislike'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('Phase 1 card has no overflow on a small phone width', (
    tester,
  ) async {
    final longName = Map<String, dynamic>.from(_direction)
      ..['direction_name'] =
          'A Very Long Festive Direction Name That Must Never Resize The Card'
      ..['style_archetype'] =
          'A Very Long Festive Direction Name That Must Never Resize The Card';

    await _pumpBoard(
      tester,
      use85Layout: true,
      width: 286,
      direction: longName,
    );

    expect(tester.takeException(), isNull);
  });

  test('pre-fix visual evidence remains available', () {
    expect(
      File('test/goldens/visual_board_phase1_before.png').existsSync(),
      isTrue,
    );
  });

  testWidgets('golden: Phase 1 board-first card', (tester) async {
    await _pumpGolden(tester, use85Layout: true);
    await expectLater(
      find.byKey(const ValueKey('visual-board-golden')),
      matchesGoldenFile('goldens/visual_board_phase1_after.png'),
    );
  });

  testWidgets('density: footwear is visually zoomed more than the top', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 320);
    final shoe = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('vscale-shoe-1')),
    );
    final top = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('vscale-kurta-1')),
    );
    final shoeScale = shoe.transform.getMaxScaleOnAxis();
    final topScale = top.transform.getMaxScaleOnAxis();
    expect(shoeScale, greaterThan(topScale));
    expect(shoeScale, greaterThan(1.30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('density: no overflow + actions intact on wide 430px board', (
    tester,
  ) async {
    await _pumpBoard(
      tester,
      use85Layout: true,
      width: 390,
      surface: const Size(430, 900),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Save'), findsOneWidget);
    expect(find.textContaining('Shuffle'), findsNothing);
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Dislike'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('density: no overflow + actions intact on narrow 286px board', (
    tester,
  ) async {
    await _pumpBoard(tester, use85Layout: true, width: 286);
    expect(tester.takeException(), isNull);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}

Future<void> _pumpConnectedBoard(
  WidgetTester tester, {
  required Future<StyleBoardShuffleResult> Function(StyleBoardState)
  shuffleCall,
  OutfitBoardTap? onTapBoard,
}) async {
  await _withFixtureImages(() async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(
        child: Scaffold(
          body: Center(
            child: AhviOutfitBoardCard(
              direction: {..._direction, 'scenario': 'build_outfit'},
              width: 390,
              onSendMessage: (_) {},
              shuffleCall: shuffleCall,
              onTapBoard: onTapBoard,
            ),
          ),
        ),
      ),
    );
    await _settleFixtureImages(tester);
  });
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  required bool use85Layout,
  double width = 320,
  Map<String, dynamic>? direction,
  List<Map<String, dynamic>>? directions,
  ValueChanged<String>? onSendMessage,
  Size surface = const Size(390, 760),
}) async {
  await _withFixtureImages(() async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: VisualDirectionCarousel(
              directions: directions ?? [direction ?? _direction],
              cardWidth: width,
              curationReveal: false,
              use85Layout: use85Layout,
              onSendMessage: onSendMessage ?? (_) {},
              editorialCover: const {
                'direction_name': 'Legacy Editorial Cover',
                'occasion_label': 'Haldi',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required bool use85Layout,
}) async {
  await _withFixtureImages(() async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(
        child: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('visual-board-golden'),
            child: ColoredBox(
              color: const Color(0xFFF8F6FA),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(15),
                child: VisualDirectionCarousel(
                  directions: [_direction],
                  cardWidth: 390,
                  curationReveal: false,
                  use85Layout: use85Layout,
                  onSendMessage: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settleFixtureImages(tester);
  });
}

Future<void> _settleFixtureImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pumpAndSettle();
}

Widget _testApp({required Widget child, TextScaler? textScaler}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      extensions: [AppThemeTokens.light(_accent)],
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler ?? MediaQuery.of(context).textScaler,
        ),
        child: child,
      ),
    ),
  );
}
