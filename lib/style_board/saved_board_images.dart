import 'dart:convert';

import 'package:myapp/util/wardrobe_image_resolver.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';

List<String> extractSavedBoardImages(Map<String, dynamic> data) {
  data = expandSavedBoardData(data);
  final urls = <String>[];
  final seen = <String>{};

  void addUrl(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || seen.contains(value)) return;
    seen.add(value);
    urls.add(value);
  }

  void readItem(Object? raw) {
    if (raw is! Map) return;
    final item = Map<String, dynamic>.from(raw);
    final resolved = resolveWardrobeImage(
      item,
      surface: 'style_board_saved',
      itemId: (item['item_id'] ?? item['id'] ?? item[r'$id'] ?? '').toString(),
    );
    addUrl(resolved.url);
  }

  void readItems(Object? raw) {
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
      readItem(item);
    }
  }

  readItems(data['outfitItems']);
  readItems(data['items']);

  Object? asPayload(Object? raw) {
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

  final boardPayload = asPayload(data['board_payload']);
  if (boardPayload is Map) {
    readItems(boardPayload['items']);
  }

  final boardPayloadCamel = asPayload(data['boardPayload']);
  if (boardPayloadCamel is Map) {
    readItems(boardPayloadCamel['items']);
  }

  if (urls.isEmpty) {
    addUrl(data['thumbnailUrl']);
    addUrl(data['imageUrl']);
  }

  return urls;
}
