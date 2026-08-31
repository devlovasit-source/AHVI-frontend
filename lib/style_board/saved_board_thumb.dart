import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as appwrite_models;

import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';
import 'package:myapp/widgets/offline_image.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';
import 'saved_board_images.dart';
import 'saved_board_persistence.dart';
import 'board_renderer.dart';

class SavedBoardThumb extends StatelessWidget {
  /// Either an Appwrite Document or a `{id, data}` raw map.
  final dynamic source;
  final Map<String, Map<String, dynamic>> wardrobeById;
  final BorderRadius radius;

  const SavedBoardThumb({
    super.key,
    required this.source,
    required this.wardrobeById,
    this.radius = const BorderRadius.all(Radius.circular(16)),
  });

  Map<String, dynamic> get _data {
    if (source is appwrite_models.Document) {
      return expandSavedBoardData(
        Map<String, dynamic>.from((source as appwrite_models.Document).data),
      );
    }
    if (source is Map) {
      final data = (source as Map)['data'];
      if (data is Map) {
        return expandSavedBoardData(Map<String, dynamic>.from(data));
      }
      return expandSavedBoardData(Map<String, dynamic>.from(source as Map));
    }
    return const {};
  }

  // Backwards-compat constructor for callers passing `doc:`.
  factory SavedBoardThumb.fromDoc({
    Key? key,
    required appwrite_models.Document doc,
    required Map<String, Map<String, dynamic>> wardrobeById,
    BorderRadius radius = const BorderRadius.all(Radius.circular(16)),
  }) => SavedBoardThumb(
    key: key,
    source: doc,
    wardrobeById: wardrobeById,
    radius: radius,
  );

  List<Map<String, dynamic>> _hydrateItems() {
    final savedItems = _savedBoardItems(_data);
    if (savedItems.isNotEmpty) {
      return savedItems
          .map(
            (item) => resolveStyleBoardItemImage(
              item,
              wardrobeById,
              surface: 'style_board_saved',
            ),
          )
          .toList(growable: false);
    }

    final raw = _data['itemIds'] ?? _data['item_ids'] ?? const [];
    final out = <Map<String, dynamic>>[];
    if (raw is Iterable) {
      for (final id in raw) {
        final key = id.toString();
        final item = wardrobeById[key];
        if (item != null) {
          out.add(
            resolveStyleBoardItemImage(
              item,
              wardrobeById,
              surface: 'style_board_saved',
            ),
          );
        }
      }
    }
    if (out.isNotEmpty) return out;

    final images = extractSavedBoardImages(_data);
    if (images.length < 2) return const [];
    for (var i = 0; i < images.length; i++) {
      out.add({
        'id': 'saved-board-image-$i',
        'name': 'Item ${i + 1}',
        'imageUrl': images[i],
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _savedBoardItems(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    void addItems(Object? raw) {
      Object? items = raw;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          items = jsonDecode(raw);
        } catch (_) {
          items = null;
        }
      }
      if (items is! Iterable) return;
      for (final item in items) {
        if (item is Map) out.add(Map<String, dynamic>.from(item));
      }
    }

    Object? payload(Object? raw) {
      if (raw is Map) return raw;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          return decoded is Map ? decoded : null;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    addItems(data['outfitItems']);
    addItems(data['items']);
    final snakePayload = payload(data['board_payload']);
    if (snakePayload is Map) addItems(snakePayload['items']);
    final camelPayload = payload(data['boardPayload']);
    if (camelPayload is Map) addItems(camelPayload['items']);
    return out
        .where(
          (item) =>
              resolveWardrobeImage(
                item,
                surface: 'style_board_saved',
                itemId: (item['item_id'] ?? item['id'] ?? item[r'$id'] ?? '')
                    .toString(),
              ).url !=
              null,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final images = extractSavedBoardImages(data);
    final imageUrl = images.isNotEmpty ? images.first : '';
    final items = _hydrateItems();

    if (items.length >= 2) {
      final occasion = (data['title'] ?? data['occasion'] ?? '').toString();
      final boardMap = <String, dynamic>{
        ...data,
        'title': occasion.isEmpty ? 'Saved Look' : occasion,
        'occasion': occasion,
        'items': items,
      };
      // Uniform per-item-count grid (same layout system as the live Style
      // This card's AhviUnifiedOutfitGrid) instead of the varied
      // role-driven "premium" editorial templates, so every saved board
      // reads with the same predictable composition regardless of which
      // garment roles it happens to contain. FittedBox contains it safely:
      // the grid's layouts size themselves from width alone and can exceed
      // a fixed-height box (e.g. the detail sheet's 340px canvas) on wider
      // screens, so this guarantees no overflow without touching those
      // fixed boxes.
      final board = boardDataFromMap(boardMap);
      final gridItems = board.items
          .map(
            (item) => AhviUnifiedOutfitGridItem.fromStyleBoardItem(
              item,
              surface: 'style_board_saved',
            ),
          )
          .toList(growable: false);
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          color: const Color(0xFFFFFCF5),
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.contain,
            // FittedBox gives its child unbounded constraints to measure
            // natural size, but AhviUnifiedOutfitGrid's LayoutBuilder-based
            // layouts (e.g. the 5-item layout) do width arithmetic like
            // `total - part - gap` that becomes Infinity - Infinity = NaN
            // under unbounded width. A fixed reference width sidesteps
            // that; FittedBox still scales the result to fit the box
            // (same fix already used in shareable_outfit_board.dart).
            child: SizedBox(
              width: 320,
              child: AhviUnifiedOutfitGrid(items: gridItems),
            ),
          ),
        ),
      );
    }

    if (imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: OfflineImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        color: const Color(0xFFF1ECE3),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.black38),
      ),
    );
  }
}
