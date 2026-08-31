import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

const savedBoardAcceptedFields = <String>{
  'userId',
  'imageUrl',
  'itemIds',
  'occasion',
  'masterGarment',
  'outfitItems',
};

const savedBoardBuckets = <String>{
  'party_looks',
  'office_fits',
  'vacation',
  'occasion',
  'everything_else',
};

const _savedBoardV1Schema = 'ahvi_saved_board_v1';
const _savedBoardV2Schema = 'ahvi_saved_board_v2';

class SavedBoardPersistenceException implements Exception {
  final String reason;
  final String userMessage;

  const SavedBoardPersistenceException(this.reason, this.userMessage);

  @override
  String toString() => reason;
}

class SavedBoardSelection {
  final String bucket;
  final bool isFavourite;

  const SavedBoardSelection({required this.bucket, this.isFavourite = false});
}

class SavedBoardContent {
  final String bucket;
  final bool isFavourite;
  final String boardId;
  final List<String> itemIds;
  final String masterGarment;
  final String outfitItems;

  const SavedBoardContent({
    required this.bucket,
    required this.isFavourite,
    required this.boardId,
    required this.itemIds,
    required this.masterGarment,
    required this.outfitItems,
  });
}

String canonicalSavedBoardBucket(Object? value) {
  final raw = (value ?? '').toString().trim().toLowerCase();
  final key = raw.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  if (savedBoardBuckets.contains(key)) return key;
  if (RegExp(
    r'(^|_)(office|work|business|professional|corporate|meeting|interview)($|_)',
  ).hasMatch(key)) {
    return 'office_fits';
  }
  if (RegExp(
    r'(^|_)(party|night_out|nightout|cocktail|club|celebration)($|_)',
  ).hasMatch(key)) {
    return 'party_looks';
  }
  if (RegExp(
    r'(^|_)(vacation|travel|beach|resort|holiday|trip|airport)($|_)',
  ).hasMatch(key)) {
    return 'vacation';
  }
  if (RegExp(
    r'(^|_)(wedding|festival|festive|traditional|ethnic|formal_event|formal|ceremony|occasion)($|_)',
  ).hasMatch(key)) {
    return 'occasion';
  }
  return 'everything_else';
}

String inferSavedBoardBucket(Map<String, dynamic> board) {
  final text = <Object?>[
    board['occasion'],
    board['title'],
    board['style_direction'],
    board['vibe'],
    board['prompt'],
    board['prompt_interpretation'],
  ].whereType<Object>().join(' ');
  return canonicalSavedBoardBucket(text);
}

bool isValidSavedBoardHttpUrl(Object? value) {
  final uri = Uri.tryParse((value ?? '').toString().trim());
  return uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

SavedBoardContent buildSavedBoardContent({
  required Map<String, dynamic> board,
  required List<Map<String, dynamic>> items,
  required SavedBoardSelection selection,
  required String title,
  required String originalOccasion,
}) {
  final bucket = canonicalSavedBoardBucket(selection.bucket);
  final revision = _int(board['revision']) ?? 1;
  final sourcePolicy = _text(board['source_policy'] ?? board['sourcePolicy']);
  final compactItems = <Map<String, dynamic>>[];
  for (final item in items) {
    compactItems.add(_compactItem(item));
  }
  if (compactItems.isEmpty) {
    throw const SavedBoardPersistenceException(
      'missing_items',
      'This look has no items that can be saved.',
    );
  }
  final itemIds = compactItems
      .map((item) => item['id'] as String)
      .toList(growable: false);
  if (itemIds.toSet().length != itemIds.length) {
    throw const SavedBoardPersistenceException(
      'duplicate_item_ids',
      'This look contains duplicate items and cannot be reopened safely.',
    );
  }
  final rawBoardId = _text(board['board_id'] ?? board['boardId']);
  final interactionMode = _text(
    board['interaction_mode'] ?? board['interactionMode'] ?? board['scenario'],
  );
  var anchorItemId = _text(
    board['anchor_item_id'] ??
        board['anchorItemId'] ??
        board['originating_item_id'] ??
        board['originatingItemId'],
  );
  if (anchorItemId.isEmpty && interactionMode == 'style_this') {
    for (final item in compactItems) {
      if (item['locked'] == true || item['anchor'] == true) {
        anchorItemId = _text(item['id']);
        break;
      }
    }
  }
  if (interactionMode == 'style_this' &&
      (anchorItemId.isEmpty || !itemIds.contains(anchorItemId))) {
    throw const SavedBoardPersistenceException(
      'missing_style_this_anchor',
      'This Style This look is missing its selected item and cannot be saved safely.',
    );
  }
  final boardId = _isStableId(rawBoardId)
      ? rawBoardId
      : _derivedBoardId(
          title: title,
          occasion: originalOccasion,
          itemIds: itemIds,
        );
  final layoutMode = _text(
    board['layout_mode'] ?? board['layoutMode'],
    fallback: _inferLayoutMode(compactItems),
  );
  final master = <String, dynamic>{
    'schema': _savedBoardV2Schema,
    'board_id': boardId,
    'revision': revision,
    'source_policy': sourcePolicy == 'shared_assets'
        ? 'style_asset'
        : sourcePolicy,
    'title': title.trim().isEmpty ? 'Saved Look' : title.trim(),
    'bucket': bucket,
    'original_occasion': originalOccasion.trim(),
    'is_favourite': selection.isFavourite,
    'layout_mode': layoutMode,
    if (interactionMode == 'style_this') ...{
      'scenario': 'style_this',
      'interaction_mode': 'style_this',
      'anchor_item_id': anchorItemId,
    },
  };
  final masterJson = jsonEncode(master);
  if (masterJson.length > 100000) {
    throw const SavedBoardPersistenceException(
      'master_garment_too_large',
      'This look contains too much board information to save.',
    );
  }

  var outfitJson = jsonEncode(compactItems);
  if (outfitJson.length > 10000) {
    for (final item in compactItems) {
      item.remove('name');
    }
    outfitJson = jsonEncode(compactItems);
  }
  if (outfitJson.length > 10000) {
    throw const SavedBoardPersistenceException(
      'outfit_items_too_large',
      'This look contains too much item information to save.',
    );
  }

  return SavedBoardContent(
    bucket: bucket,
    isFavourite: selection.isFavourite,
    boardId: boardId,
    itemIds: itemIds,
    masterGarment: masterJson,
    outfitItems: outfitJson,
  );
}

Map<String, dynamic> buildSavedBoardPayload({
  required String userId,
  required String imageUrl,
  required SavedBoardContent content,
}) {
  final cleanUserId = userId.trim();
  if (cleanUserId.isEmpty || cleanUserId.length > 52) {
    throw const SavedBoardPersistenceException(
      'invalid_user_id',
      'Your session could not be validated. Please sign in again.',
    );
  }
  final cleanImageUrl = imageUrl.trim();
  if (!isValidSavedBoardHttpUrl(cleanImageUrl)) {
    throw const SavedBoardPersistenceException(
      'invalid_image_url',
      'This look does not have a valid image to save.',
    );
  }
  if (!savedBoardBuckets.contains(content.bucket) ||
      content.bucket.length > 50) {
    throw const SavedBoardPersistenceException(
      'invalid_bucket',
      'Please choose a valid board category.',
    );
  }
  if (content.itemIds.isEmpty ||
      content.itemIds.length > 500 ||
      content.itemIds.toSet().length != content.itemIds.length ||
      content.itemIds.any((id) => !_isStableId(id) || id.length > 500)) {
    throw const SavedBoardPersistenceException(
      'invalid_item_ids',
      'This look contains an item that cannot be reopened.',
    );
  }
  if (content.masterGarment.length > 100000) {
    throw const SavedBoardPersistenceException(
      'master_garment_too_large',
      'This look contains too much board information to save.',
    );
  }
  if (content.outfitItems.length > 10000) {
    throw const SavedBoardPersistenceException(
      'outfit_items_too_large',
      'This look contains too much item information to save.',
    );
  }
  return <String, dynamic>{
    'userId': cleanUserId,
    'imageUrl': cleanImageUrl,
    'itemIds': content.itemIds,
    'occasion': content.bucket,
    'masterGarment': content.masterGarment,
    'outfitItems': content.outfitItems,
  };
}

Map<String, dynamic> expandSavedBoardData(Map<String, dynamic> data) {
  final master = _decodeMap(data['masterGarment']);
  if (master?['schema'] == _savedBoardV2Schema) {
    if (data['outfitItems'] == null && data['items'] is Iterable) {
      return Map<String, dynamic>.from(data);
    }
    final rawItems = _decodeList(data['outfitItems']);
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = _text(item['id']);
      if (id.isEmpty) continue;
      final expanded = <String, dynamic>{
        'item_id': id,
        'role': _text(item['role']),
        if (_text(item['source']).isNotEmpty) 'source': _text(item['source']),
        if (_text(item['name']).isNotEmpty) 'name': _text(item['name']),
        'image_url': _text(item['image_url']),
        'selected_field': _text(item['selected_field']),
        'source_kind': _text(item['source_kind']),
        'expected_transparent': item['expected_transparent'] == true,
        for (final key in const [
          'slot',
          'board_role',
          'category',
          'sub_category',
          'masked_url',
          'normalized_url',
          'board_image_url',
          'asset_cutout_url',
          'asset_masked_url',
          'original_image_url',
          'board_status',
          'cutout_status',
          'image_status',
        ])
          if (_text(item[key]).isNotEmpty) key: _text(item[key]),
      };
      if (_hasCompactPosition(item)) {
        expanded['position'] = {
          'x': item['x'],
          'y': item['y'],
          'width': item['w'],
          'height': item['h'],
          if (item['s'] != null) 'scale': item['s'],
          if (item['r'] != null) 'rotation': item['r'],
          if (item['z'] != null) 'z': item['z'],
        };
      }
      byId[id] = expanded;
    }
    final storedIds = data['itemIds'];
    final orderedIds = storedIds is Iterable
        ? storedIds.map((id) => id.toString()).toList(growable: false)
        : byId.keys.toList(growable: false);
    final orderedItems = <Map<String, dynamic>>[
      for (final id in orderedIds)
        if (byId[id] != null) byId[id]!,
    ];
    final expanded = <String, dynamic>{
      ...data,
      ...master!,
      'source_policy': master['source_policy'] == 'shared_assets'
          ? 'style_asset'
          : master['source_policy'],
      'occasion': master['original_occasion'] ?? data['occasion'],
      'bucket': canonicalSavedBoardBucket(master['bucket'] ?? data['occasion']),
      'is_favourite': master['is_favourite'] == true,
      'items': orderedItems,
      'board_items': orderedItems,
      'itemIds': orderedIds,
    };
    expanded.remove('outfitItems');
    return expanded;
  }

  Map<String, dynamic>? canonical;
  final descriptionEnvelope = _decodeMap(data['outfitDescription']);
  if (descriptionEnvelope?['schema'] == _savedBoardV1Schema) {
    canonical = _decodeMap(descriptionEnvelope?['board']);
  }
  canonical ??= _decodeMap(data['board_payload']);
  canonical ??= _decodeMap(data['boardPayload']);
  final expanded = canonical == null
      ? Map<String, dynamic>.from(data)
      : <String, dynamic>{...data, ...canonical};
  expanded['bucket'] = canonicalSavedBoardBucket(
    expanded['bucket'] ?? expanded['occasion'],
  );
  expanded['is_favourite'] = master?.containsKey('is_favourite') == true
      ? master!['is_favourite'] == true
      : expanded['is_favourite'] == true || expanded['isFavourite'] == true;
  return expanded;
}

bool savedBoardIsFavourite(Map<String, dynamic> data) =>
    expandSavedBoardData(data)['is_favourite'] == true;

String savedBoardMasterGarmentWithFavourite(
  Map<String, dynamic> data,
  bool isFavourite,
) {
  final master = _decodeMap(data['masterGarment']) ?? <String, dynamic>{};
  master['is_favourite'] = isFavourite;
  return jsonEncode(master);
}

bool savedBoardMatchesFilter(Map<String, dynamic> data, String filter) {
  final expanded = expandSavedBoardData(data);
  if (filter == 'all') return true;
  if (filter == 'favourites') return expanded['is_favourite'] == true;
  return canonicalSavedBoardBucket(
        expanded['bucket'] ?? expanded['occasion'],
      ) ==
      filter;
}

Map<String, dynamic> savedBoardReopenParity(
  Map<String, dynamic> data, {
  Iterable<Map<String, dynamic>>? renderedItems,
}) {
  final expanded = expandSavedBoardData(data);
  final ids = (expanded['itemIds'] is Iterable)
      ? (expanded['itemIds'] as Iterable).map((id) => id.toString()).toList()
      : const <String>[];
  final items = expanded['items'] is Iterable
      ? (expanded['items'] as Iterable).whereType<Map>().toList()
      : const <Map>[];
  final itemIds = items
      .map((item) => _text(item['item_id'] ?? item['id']))
      .toList();
  final rendered = renderedItems?.toList(growable: false);
  final provenanceOk = items.every(
    (item) =>
        _text(item['selected_field']).isNotEmpty &&
        _text(item['source_kind']).isNotEmpty &&
        item['expected_transparent'] is bool,
  );
  final renderedIds = rendered
      ?.map((item) => _text(item['item_id'] ?? item['id']))
      .toList(growable: false);
  final renderedProvenanceOk =
      rendered == null ||
      (rendered.length == items.length &&
          List.generate(items.length, (index) {
            final stored = items[index];
            final actual = rendered[index];
            return _text(stored['image_url']) == _text(actual['image_url']) &&
                _text(stored['selected_field']) ==
                    _text(actual['selected_field']) &&
                _text(stored['source_kind']) == _text(actual['source_kind']) &&
                stored['expected_transparent'] ==
                    actual['expected_transparent'];
          }).every((matches) => matches));
  return {
    'board_id': _text(expanded['board_id'] ?? expanded['boardId']),
    'item_count_match':
        (ids.isEmpty || ids.length == items.length) &&
        (rendered == null || rendered.length == items.length),
    'item_order_match':
        (ids.isEmpty || _listEquals(ids, itemIds)) &&
        (renderedIds == null || _listEquals(itemIds, renderedIds)),
    'source_policy_match': _text(
      expanded['source_policy'] ?? expanded['sourcePolicy'],
    ).isNotEmpty,
    'image_provenance_match':
        items.isEmpty || (provenanceOk && renderedProvenanceOk),
    'bucket': canonicalSavedBoardBucket(
      expanded['bucket'] ?? expanded['occasion'],
    ),
    'is_favourite': expanded['is_favourite'] == true,
  };
}

Map<String, dynamic> _compactItem(Map<String, dynamic> raw) {
  final id = _text(
    raw['item_id'] ??
        raw['id'] ??
        raw[r'$id'] ??
        raw['itemId'] ??
        raw['wardrobe_item_id'] ??
        raw['wardrobeItemId'],
  );
  if (!_isStableId(id)) {
    throw const SavedBoardPersistenceException(
      'invalid_item_ids',
      'This look contains an item that cannot be reopened.',
    );
  }
  final role = _text(raw['role'] ?? raw['slot']).toLowerCase();
  if (role.isEmpty || role == 'unknown') {
    throw const SavedBoardPersistenceException(
      'invalid_item_role',
      'This look contains an item without a stable role.',
    );
  }
  // Must reproduce the same board surface used for the live on-screen
  // render (e.g. daily_wear.dart's _savedDailyWearItems / style_board.dart's
  // canonical board build) -- freezing under the default 'wardrobe' surface
  // here would apply wardrobe-grid rules (no board-safety guard, no
  // cutout-first ranking) and could freeze a different image than what the
  // user actually saw and chose to save.
  final resolved = resolveWardrobeImage(
    raw,
    surface: 'style_board_saved',
    emitDiagnostic: false,
  );
  if (!isValidSavedBoardHttpUrl(resolved.url)) {
    throw const SavedBoardPersistenceException(
      'invalid_item_image',
      'This look contains an item without a valid image.',
    );
  }
  final item = <String, dynamic>{
    'id': id,
    'role': role,
    if (_text(
      raw['source'] ?? raw['item_source'] ?? raw['itemSource'],
    ).isNotEmpty)
      'source': _text(raw['source'] ?? raw['item_source'] ?? raw['itemSource']),
    if (_text(raw['name'] ?? raw['title']).isNotEmpty)
      'name': _text(raw['name'] ?? raw['title']),
    'image_url': resolved.url,
    'selected_field': resolved.field,
    'source_kind': resolved.sourceKind,
    'expected_transparent': resolved.expectedTransparent,
    for (final key in const [
      'slot',
      'board_role',
      'category',
      'sub_category',
      'masked_url',
      'normalized_url',
      'board_image_url',
      'asset_cutout_url',
      'asset_masked_url',
      'original_image_url',
      'board_status',
      'cutout_status',
      'image_status',
    ])
      if (_text(raw[key]).isNotEmpty) key: _text(raw[key]),
  };
  final position = raw['position'] is Map
      ? Map<String, dynamic>.from(raw['position'] as Map)
      : raw;
  final x = _number(position['x']);
  final y = _number(position['y']);
  final w = _number(position['width'] ?? position['w']);
  final h = _number(position['height'] ?? position['h']);
  if (x != null && y != null && w != null && h != null) {
    item.addAll({'x': x, 'y': y, 'w': w, 'h': h});
    final scale = _number(position['scale']);
    if (scale != null) item['s'] = scale;
    final rotation = _number(position['rotation']);
    if (rotation != null) item['r'] = rotation;
    final z = _int(position['z']);
    if (z != null) item['z'] = z;
  }
  return item;
}

String _inferLayoutMode(List<Map<String, dynamic>> items) {
  final roles = items.map((item) => item['role']).toList();
  if (roles.contains('dress')) return 'dressFocused';
  if (roles.contains('top') &&
      roles.contains('bottom') &&
      roles.contains('footwear')) {
    return roles.where((role) => role == 'accessory').length > 2
        ? 'accessoryHeavy'
        : 'classicThreePlusAccessory';
  }
  return 'generic';
}

bool _isStableId(String value) =>
    value.isNotEmpty &&
    !value.toLowerCase().startsWith('outfit_card_') &&
    !value.toLowerCase().startsWith('saved-board-image-');

String _derivedBoardId({
  required String title,
  required String occasion,
  required List<String> itemIds,
}) {
  final identity = jsonEncode({
    'title': title.trim().toLowerCase(),
    'occasion': occasion.trim().toLowerCase(),
    'item_ids': itemIds,
  });
  return 'saved_${sha256.convert(utf8.encode(identity)).toString().substring(0, 32)}';
}

bool _hasCompactPosition(Map<String, dynamic> item) =>
    item['x'] is num &&
    item['y'] is num &&
    item['w'] is num &&
    item['h'] is num;

Map<String, dynamic>? _decodeMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is! String || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

List<dynamic> _decodeList(Object? raw) {
  if (raw is List) return raw;
  if (raw is! String || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  } catch (_) {
    return const [];
  }
}

String _text(Object? value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

int? _int(Object? value) => value is int ? value : int.tryParse('$value');
num? _number(Object? value) => value is num ? value : num.tryParse('$value');

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
