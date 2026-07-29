import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as appwrite_models;

import 'package:myapp/widgets/offline_image.dart';
import 'saved_board_images.dart';
import 'board_renderer.dart';
import 'editorial_board_renderer.dart';

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
      return Map<String, dynamic>.from(
        (source as appwrite_models.Document).data,
      );
    }
    if (source is Map) {
      final data = (source as Map)['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(source as Map);
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
    final raw = _data['itemIds'] ?? _data['item_ids'] ?? const [];
    final out = <Map<String, dynamic>>[];
    if (raw is Iterable) {
      for (final id in raw) {
        final key = id.toString();
        final item = wardrobeById[key];
        if (item != null) out.add(item);
      }
    }
    if (out.isNotEmpty) return out;

    final savedItems = _savedBoardItems(_data);
    if (savedItems.isNotEmpty) return savedItems;

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
    return out.where((item) {
      final url =
          (item['imageUrl'] ??
                  item['image_url'] ??
                  item['masked_url'] ??
                  item['maskedUrl'] ??
                  item['url'] ??
                  item['thumbnailUrl'])
              ?.toString()
              .trim() ??
          '';
      return url.isNotEmpty;
    }).toList();
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
        'title': occasion.isEmpty ? 'Saved Look' : occasion,
        'occasion': occasion,
        'items': items,
      };
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          color: const Color(0xFFFFFCF5),
          padding: const EdgeInsets.all(8),
          child: EditorialBoardCanvas(board: boardDataFromMap(boardMap)),
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
