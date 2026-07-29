import 'dart:convert';

List<String> extractSavedBoardImages(Map<String, dynamic> data) {
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
    for (final key in const [
      'normalized_url',
      'normalizedUrl',
      'masked_url',
      'maskedUrl',
      'imageUrl',
      'image_url',
      'url',
      'thumbnailUrl',
    ]) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        addUrl(value);
        return;
      }
    }
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
