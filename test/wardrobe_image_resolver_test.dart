import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_renderer.dart';
import 'package:myapp/style_board/saved_board_images.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

void main() {
  setUp(resetWardrobeImageDiagnosticCache);

  test('validated wardrobe cutout wins over board and every fallback', () {
    final board = resolveWardrobeImage({
      'item_id': 'item-1',
      'board_status': 'cutout_ready',
      'board_image_url': 'https://test/board.png',
      'cutout_status': 'ready',
      'cutout_url': 'https://test/cutout.png',
      'masked_url': 'https://test/masked.png',
      'normalized_url': 'https://test/catalog.png',
      'image_url': 'https://test/original.jpg',
    });

    expect(board.url, 'https://test/cutout.png');
    expect(board.sourceKind, 'validated_cutout');
    expect(board.validated, isTrue);
    expect(board.shouldFrame, isFalse);
  });

  test('masked and processed images beat catalogue and original fallbacks', () {
    final masked = resolveWardrobeImage({
      'masked_url': 'https://test/masked.png',
      'image_status': 'rmbg_complete',
      'transparent_image_url': 'https://test/processed.png',
      'normalized_url': 'https://test/catalog.png',
      'image_url': 'https://test/original.jpg',
    });
    final processed = resolveWardrobeImage({
      'transparent_image_url': 'https://test/processed.png',
      'cutout_status': 'ready',
      'normalized_url': 'https://test/catalog.png',
      'image_url': 'https://test/original.jpg',
    });

    expect(masked.url, 'https://test/masked.png');
    expect(masked.sourceKind, 'validated_cutout');
    expect(processed.url, 'https://test/processed.png');
    expect(processed.sourceKind, 'processed_cutout');
  });

  test('grid stays catalog-first; board is cutout-first for a masked cutout', () {
    final raw = {
      'item_id': 'wp-shirt',
      'masked_url': 'https://test/wardrobe_wp.png',
      'image_status': 'rmbg_complete',
      'normalized_url': 'https://test/catalog_wp.png',
      'selected_field': 'masked_url',
      'source_kind': 'legacy_masked_cutout',
      'expected_transparent': true,
    };
    // Wardrobe grid keeps catalog-first (polished, consistent photography).
    final grid = resolveWardrobeImage(raw, surface: 'wardrobe_grid');
    expect(grid.url, 'https://test/catalog_wp.png');
    expect(grid.sourceKind, 'catalog_fallback');
    // Board surfaces are cutout-first: the transparent masked cutout wins so
    // the garment renders frameless and full-size (policy: prefer cutouts on
    // boards; rawCutoutIsSafe already filters genuinely broken cutouts).
    for (final surface in ['style_board_render', 'style_this_request']) {
      final r = resolveWardrobeImage(raw, surface: surface);
      expect(r.url, 'https://test/wardrobe_wp.png', reason: surface);
      expect(r.sourceKind,
          anyOf('validated_cutout', 'legacy_masked_cutout'), reason: surface);
      expect(r.shouldFrame, isFalse, reason: surface);
    }
  });

  test('grid catalog-first only fires for a real catalog_* object', () {
    // A non-catalog normalized url must NOT hijack the masked cutout.
    final grid = resolveWardrobeImage({
      'masked_url': 'https://test/masked.png',
      'image_status': 'rmbg_complete',
      'normalized_url': 'https://test/normalized.png',
    }, surface: 'wardrobe_grid');
    expect(grid.url, 'https://test/masked.png');
  });

  test('style asset source alone does not validate its board image', () {
    final result = resolveWardrobeImage({
      'source': 'style_asset',
      'board_image_url': 'https://test/shared-cutout.png',
      'normalized_url': 'https://test/catalog.png',
    });

    expect(result.sourceKind, 'catalog_fallback');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  test('masked URL equal to original is demoted and framed', () {
    final result = resolveWardrobeImage({
      'masked_url': 'https://test/original.jpg',
      'image_url': 'https://test/original.jpg',
    });

    expect(result.sourceKind, 'original');
    expect(result.shouldFrame, isTrue);
    expect(result.expectedTransparent, isFalse);
  });

  test('catalogue object in masked URL is a framed fallback', () {
    final result = resolveWardrobeImage({
      'masked_url':
          'https://storage.test/buckets/wardrobe/files/catalog_item-1.png/view?project=test',
    });

    expect(result.field, 'masked_url');
    expect(result.sourceKind, 'catalog_fallback');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  test('safe distinct legacy masked field remains an unframed cutout', () {
    final result = resolveWardrobeImage({
      'masked_url': 'https://storage.test/files/wardrobe_item-1.png',
    });

    expect(result.sourceKind, 'legacy_masked_cutout');
    expect(result.expectedTransparent, isTrue);
    expect(result.shouldFrame, isFalse);
  });

  test('legacy masked camel alias remains an unframed cutout', () {
    final result = resolveWardrobeImage({
      'maskedUrl':
          'https://storage.test/files/wardrobe_item-1_cutout_v12.png/view',
    });

    expect(result.sourceKind, 'legacy_masked_cutout');
    expect(result.expectedTransparent, isTrue);
    expect(result.shouldFrame, isFalse);
  });

  test('normalized catalogue URL remains a framed fallback', () {
    final result = resolveWardrobeImage({
      'normalized_url': 'https://storage.test/files/catalog_item-1.jpg',
    });

    expect(result.sourceKind, 'catalog_fallback');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  test('board image without validated provenance uses framed catalogue', () {
    final result = resolveWardrobeImage({
      'item_id': 'item-board-untrusted',
      'board_image_url': 'https://test/white-board.png',
      'normalized_url': 'https://test/catalog-item.jpg',
      'image_url': 'https://test/original.jpg',
    });

    expect(result.url, 'https://test/catalog-item.jpg');
    expect(result.field, 'normalized_url');
    expect(result.sourceKind, 'catalog_fallback');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  test('validated board cutout remains transparent', () {
    final result = resolveWardrobeImage({
      'item_id': 'item-board-validated',
      'board_status': 'cutout_ready',
      'board_image_url': 'https://test/validated-board.png',
      'normalized_url': 'https://test/catalog-item.jpg',
    });

    expect(result.url, 'https://test/validated-board.png');
    expect(result.sourceKind, 'validated_cutout');
    expect(result.expectedTransparent, isTrue);
    expect(result.shouldFrame, isFalse);
  });

  test('wardrobe validated mask overrides untrusted board image', () {
    final result = resolveWardrobeImage(
      {
        'item_id': 'item-matched',
        'board_image_url': 'https://test/untrusted-board.png',
      },
      wardrobeRecord: {
        r'$id': 'item-matched',
        'image_status': 'rmbg_complete',
        'masked_url': 'https://test/validated-mask.png',
        'normalized_url': 'https://test/catalog-item.jpg',
      },
    );

    expect(result.url, 'https://test/validated-mask.png');
    expect(result.field, 'masked_url');
    expect(result.sourceKind, 'validated_cutout');
    expect(result.expectedTransparent, isTrue);
    expect(result.shouldFrame, isFalse);
  });

  test('validated status cannot make an original alias transparent', () {
    final raw = resolveWardrobeImage({
      'image_status': 'rmbg_complete',
      'masked_image_url': 'https://test/original-white.jpg',
      'image_url': 'https://test/original-white.jpg',
    });
    final matched = resolveWardrobeImage(
      {'item_id': 'same-original'},
      wardrobeRecord: {
        r'$id': 'same-original',
        'image_status': 'rmbg_complete',
        'masked_url': 'https://test/original-white.jpg',
        'image_url': 'https://test/original-white.jpg',
      },
    );

    for (final result in [raw, matched]) {
      expect(result.url, 'https://test/original-white.jpg');
      expect(result.sourceKind, 'original');
      expect(result.expectedTransparent, isFalse);
      expect(result.shouldFrame, isTrue);
    }
  });

  test('processed fields that alias the original remain framed', () {
    for (final field in [
      'board_image_url',
      'cutout_url',
      'rmbg_url',
      'transparent_image_url',
      'processed_url',
    ]) {
      final result = resolveWardrobeImage({
        'board_status': 'cutout_ready',
        'cutout_status': 'ready',
        'image_status': 'rmbg_complete',
        field: 'https://test/original-white.jpg',
        'image_url': 'https://test/original-white.jpg',
      });

      expect(result.sourceKind, 'original', reason: field);
      expect(result.expectedTransparent, isFalse, reason: field);
      expect(result.shouldFrame, isTrue, reason: field);
    }
  });

  test('processed fields that alias an ordinary catalog URL remain framed', () {
    for (final field in [
      'board_image_url',
      'cutout_url',
      'masked_url',
      'rmbg_url',
      'transparent_image_url',
      'processed_url',
    ]) {
      final result = resolveWardrobeImage({
        'board_status': 'cutout_ready',
        'cutout_status': 'ready',
        'image_status': 'rmbg_complete',
        field: 'https://test/product-123.png',
        'normalized_url': 'https://test/product-123.png',
      });

      expect(result.sourceKind, 'catalog_fallback', reason: field);
      expect(result.expectedTransparent, isFalse, reason: field);
      expect(result.shouldFrame, isTrue, reason: field);
    }
  });

  test('cross-record catalog aliases remain framed', () {
    final rawAlias = resolveWardrobeImage(
      {
        'item_id': 'raw-alias',
        'image_status': 'rmbg_complete',
        'processed_url': 'https://test/wardrobe-product.png',
      },
      wardrobeRecord: {
        r'$id': 'raw-alias',
        'normalized_url': 'https://test/wardrobe-product.png',
      },
    );
    final wardrobeAlias = resolveWardrobeImage(
      {
        'item_id': 'wardrobe-alias',
        'normalized_url': 'https://test/raw-product.png',
      },
      wardrobeRecord: {
        r'$id': 'wardrobe-alias',
        'image_status': 'rmbg_complete',
        'masked_url': 'https://test/raw-product.png',
      },
    );
    final frozenAlias = resolveWardrobeImage(
      {
        'item_id': 'frozen-alias',
        'image_url': 'https://test/frozen-product.png',
        'selected_field': 'processed_url',
        'source_kind': 'processed_cutout',
        'expected_transparent': true,
      },
      wardrobeRecord: {
        r'$id': 'frozen-alias',
        'normalized_url': 'https://test/frozen-product.png',
      },
    );

    for (final result in [rawAlias, wardrobeAlias]) {
      expect(result.sourceKind, 'catalog_fallback');
      expect(result.expectedTransparent, isFalse);
      expect(result.shouldFrame, isTrue);
    }

    // frozenAlias's wardrobeRecord normalized_url is byte-identical to the
    // raw record's image_url -- the backend never produced a distinct
    // processed asset for this item. The resolver must not admit that as
    // catalog_fallback (see the isOriginalAlias guard on the two
    // unconditional normalized_url fallback candidates); it degrades to the
    // raw original instead, exactly like any other real alias case.
    expect(frozenAlias.sourceKind, 'original');
    expect(frozenAlias.field, 'image_url');
    expect(frozenAlias.expectedTransparent, isFalse);
  });

  test('cross-record original aliases remain framed across signed URLs', () {
    final result = resolveWardrobeImage(
      {
        'item_id': 'cross-original',
        'image_url': 'https://storage.test/files/product.png?token=old',
      },
      wardrobeRecord: {
        r'$id': 'cross-original',
        'image_status': 'rmbg_complete',
        'masked_url': 'https://storage.test/files/product.png?token=new',
      },
    );

    expect(result.sourceKind, 'original');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  test('asset cutout beats raw style asset image', () {
    final result = resolveWardrobeImage({
      'item_id': 'asset-1',
      'source': 'style_asset',
      'asset_cutout_url': 'https://test/asset-cutout.png',
      'image_url': 'https://test/asset-raw.jpg',
    });

    expect(result.url, 'https://test/asset-cutout.png');
    expect(result.field, 'asset_cutout_url');
    expect(result.sourceKind, 'style_asset_cutout');
    expect(result.expectedTransparent, isTrue);
    expect(result.requiresFrame, isFalse);
  });

  test('asset cutout that aliases raw image remains framed', () {
    final result = resolveWardrobeImage({
      'source': 'style_asset',
      'asset_cutout_url': 'https://test/asset.jpg',
      'image_url': 'https://test/asset.jpg',
    });

    expect(result.sourceKind, 'style_asset_original');
    expect(result.expectedTransparent, isFalse);
    expect(result.requiresFrame, isTrue);
  });

  test('wardrobe map indexes every stable id alias', () {
    final record = <String, dynamic>{
      r'$id': 'document-id',
      'item_id': 'backend-item-id',
      'imageId': 'image-id',
    };
    final map = buildWardrobeImageMap([record]);

    expect(map['document-id'], same(record));
    expect(map['backend-item-id'], same(record));
    expect(map['image-id'], same(record));
  });

  test('catalog object inside board image remains framed', () {
    final result = resolveWardrobeImage({
      'item_id': 'item-catalog-board',
      'board_image_url': 'https://test/files/catalog_item-7.png/view',
    });

    expect(result.field, 'board_image_url');
    expect(result.sourceKind, 'catalog_fallback');
    expect(result.expectedTransparent, isFalse);
    expect(result.shouldFrame, isTrue);
  });

  // Regression: a footwear wardrobe item whose backend record never got a
  // distinct catalog/cutout asset -- normalized_url was aliased to the same
  // raw upload as image_url (a cropped mirror/floor photo). Live-reproduced
  // on the "Refined Ease" style board: the raw photo was labeled
  // catalog_fallback and rendered directly on the board.
  test('a normalized_url aliasing the raw upload is never admitted on a board surface', () {
    final result = resolveWardrobeImage(
      {
        'item_id': 'footwear-bad-data',
        'image_url': 'https://test/raw-shoe-photo.jpg',
        'normalized_url': 'https://test/raw-shoe-photo.jpg',
      },
      surface: 'style_board_active_unified_grid',
    );

    // Board surfaces drop raw/original candidates entirely -- with no other
    // safe source, the item must resolve to no image (renderer omits it),
    // never the raw photo mislabeled as a safe catalog fallback.
    expect(result.url, isNull);
    expect(result.sourceKind, isNot('catalog_fallback'));
  });

  test('a genuinely distinct normalized_url is still admitted on a board surface', () {
    final result = resolveWardrobeImage(
      {
        'item_id': 'footwear-good-data',
        'image_url': 'https://test/raw-shoe-photo.jpg',
        'normalized_url': 'https://test/processed-shoe-cutout.jpg',
      },
      surface: 'style_board_active_unified_grid',
    );

    expect(result.field, 'normalized_url');
    expect(result.url, 'https://test/processed-shoe-cutout.jpg');
    expect(result.sourceKind, 'catalog_fallback');
  });

  test('share reparse preserves resolution, stable id, and layout', () {
    final hydrated = resolveStyleBoardItemImage(
      {
        'item_id': 'item-share',
        'role': 'top',
        'name': 'Share shirt',
        'board_image_url': 'https://test/untrusted-board.png',
        'normalized_url': 'https://test/stale-catalog.jpg',
        'position': {
          'x': 0.1,
          'y': 0.2,
          'width': 0.5,
          'height': 0.4,
          'rotation': -0.02,
        },
      },
      {
        'item-share': {
          r'$id': 'item-share',
          'normalized_url': 'https://test/catalog-share.jpg',
        },
      },
      surface: 'style_board_live',
      emitDiagnostic: false,
    );
    final shareItem = StyleBoardItem.fromJson(hydrated);

    expect(shareItem.itemId, 'item-share');
    expect(shareItem.imageUrl, 'https://test/catalog-share.jpg');
    expect(shareItem.shouldFrame, isTrue);
    expect(shareItem.position?.x, 0.1);
    expect(shareItem.position?.rotation, -0.02);
  });

  test('all board surfaces preserve the same selected image decision', () {
    final raw = <String, dynamic>{
      'item_id': 'surface-item',
      'role': 'top',
      'source': 'style_asset',
      'asset_cutout_url': 'https://test/surface-cutout.png',
      'image_url': 'https://test/surface-original.jpg',
    };
    Map<String, dynamic> current = raw;
    final decisions = <String>[];
    for (final surface in [
      'style_board_live',
      'style_board_saved',
      'style_board_reopened',
      'style_board_share',
      'style_this',
      'build_outfit',
      'style_board_cover',
      'style_board_shuffle',
    ]) {
      current = resolveStyleBoardItemImage(
        current,
        const {},
        surface: surface,
        emitDiagnostic: false,
      );
      decisions.add(
        '${current['image_url']}|${current['source_kind']}|'
        '${current['expected_transparent']}',
      );
    }

    expect(decisions.toSet(), hasLength(1));
    expect(current['item_id'], 'surface-item');
    expect(current['source_kind'], 'style_asset_cutout');
  });

  test('unvalidated catalogue fallback is retained as a framed tile', () {
    final data = boardDataFromMap({
      'items': [
        {
          'item_id': 'anchor-1',
          'name': 'Anchored shirt',
          'category': 'Tops',
          'normalized_url': 'https://test/catalog.png',
        },
      ],
    });

    expect(data.items, hasLength(1));
    expect(data.items.single.imageUrl, 'https://test/catalog.png');
    expect(data.items.single.shouldFrame, isTrue);
  });

  test('StyleBoardItem canonicalizes rendering to the validated cutout', () {
    final item = StyleBoardItem.fromJson({
      'item_id': 'item-2',
      'name': 'Shirt',
      'slot': 'top',
      'board_status': 'cutout_ready',
      'board_image_url': 'https://test/board.png',
      'image_url': 'https://test/original.jpg',
    });

    expect(item.imageUrl, 'https://test/board.png');
    expect(item.resolveImage().sourceKind, 'validated_cutout');
    expect(item.resolveImage().url, 'https://test/board.png');
    expect(item.shouldFrame, isFalse);
    expect(item.toContractJson(), isNot(contains('_image_should_frame')));
  });

  test('canonical reconstruction retains every style asset candidate', () {
    final item = StyleBoardItem.fromJson({
      'item_id': 'asset-canonical',
      'name': 'Asset top',
      'role': 'top',
      'source': 'style_asset',
      'asset_cutout_url': 'https://test/asset-cutout.png',
      'asset_masked_url': 'https://test/asset-mask.png',
      'board_image_url': 'https://test/asset-board.jpg',
      'normalized_url': 'https://test/asset-catalog.jpg',
      'masked_url': 'https://test/legacy-mask.png',
      'image_url': 'https://test/asset-original.jpg',
    });
    final contract = item.toContractJson();

    expect(contract['asset_cutout_url'], 'https://test/asset-cutout.png');
    expect(contract['asset_masked_url'], 'https://test/asset-mask.png');
    expect(contract['board_image_url'], 'https://test/asset-board.jpg');
    expect(contract['normalized_url'], 'https://test/asset-catalog.jpg');
    expect(contract['masked_url'], 'https://test/legacy-mask.png');
    expect(contract['image_url'], 'https://test/asset-cutout.png');
    expect(item.itemId, 'asset-canonical');
  });

  test('saved-board extraction uses the shared cutout-first policy', () {
    final urls = extractSavedBoardImages({
      'items': [
        {
          'item_id': 'item-3',
          'cutout_status': 'ready',
          'cutout_url': 'https://test/cutout.png',
          'normalized_url': 'https://test/catalog.png',
        },
      ],
    });

    expect(urls, ['https://test/cutout.png']);
  });

  test('diagnostic contains metadata but never image URLs', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      resolveWardrobeImage({
        'item_id': 'item-4',
        'masked_url': 'https://secret.test/private-cutout.png?token=secret',
      }, surface: 'wardrobe_grid');
    } finally {
      debugPrint = previous;
    }

    final compare = messages.singleWhere(
      (message) => message.startsWith('AHVI_IMAGE_FIELD_COMPARE'),
    );
    final resolve = messages.singleWhere(
      (message) => message.startsWith('AHVI_WARDROBE_IMAGE_RESOLVE'),
    );
    expect(compare, contains('item_id=item-4'));
    expect(compare, matches(RegExp(r'masked_url_fp=[0-9a-f]{8}')));
    expect(compare, contains('selected_field=masked_url'));
    expect(resolve, contains('surface=wardrobe_grid'));
    expect(
      messages.singleWhere(
        (message) => message.startsWith('AHVI_IMAGE_SELECTION_DECISION'),
      ),
      contains('requires_frame=false'),
    );
    expect(
      messages.every((message) => !message.contains('secret.test')),
      isTrue,
    );
    expect(messages.every((message) => !message.contains('token=')), isTrue);
  });
}
