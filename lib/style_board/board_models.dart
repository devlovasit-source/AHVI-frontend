import 'package:flutter/foundation.dart';

enum BoardItemRole {
  top,
  bottom,
  footwear,
  outerwear,
  dress,
  accessory,
  unknown,
}

@immutable
class StyleBoardItem {
  final String id;
  String get itemId => id;
  final String slot;
  final String boardRole;
  final String source;
  final String accessoryType;
  final String name;
  final String imageUrl;
  final String maskedUrl;
  final String boardImageUrl;
  final String normalizedUrl;
  final String category;
  final String subCategory;
  final BoardItemRole role;
  final BoardPosition? position;
  final bool isLocked;
  final bool isRegenerating;
  final Map<String, dynamic> raw;

  const StyleBoardItem({
    required this.id,
    this.slot = '',
    this.boardRole = '',
    this.source = 'unknown',
    this.accessoryType = '',
    required this.name,
    required this.imageUrl,
    this.maskedUrl = '',
    this.boardImageUrl = '',
    this.normalizedUrl = '',
    required this.category,
    this.subCategory = '',
    required this.role,
    this.position,
    this.isLocked = false,
    this.isRegenerating = false,
    this.raw = const <String, dynamic>{},
  });

  factory StyleBoardItem.fromJson(Map<String, dynamic> json) {
    final itemId = _firstText(json, const [
      'item_id',
      'id',
      r'$id',
      'itemId',
      'image_id',
      'asset_id',
    ]);
    final slot = _firstText(json, const ['slot', 'role']);
    final role = boardItemRoleFromText(slot);
    return StyleBoardItem(
      id: itemId,
      slot: slot.toLowerCase(),
      boardRole: _firstText(json, const ['board_role', 'boardRole']),
      source: _canonicalSource(json['source']),
      accessoryType: _firstText(json, const [
        'accessory_type',
        'accessoryType',
      ]),
      name: _firstText(json, const [
        'name',
        'title',
        'label',
      ], fallback: 'Item'),
      category: _firstText(json, const ['category']),
      subCategory: _firstText(json, const [
        'sub_category',
        'subCategory',
        'subcategory',
      ]),
      imageUrl: _firstText(json, const ['image_url', 'imageUrl']),
      maskedUrl: _firstText(json, const ['masked_url', 'maskedUrl']),
      boardImageUrl: _firstText(json, const [
        'board_image_url',
        'boardImageUrl',
      ]),
      normalizedUrl: _firstText(json, const [
        'normalized_url',
        'normalizedUrl',
      ]),
      role: role,
      position: BoardPosition.fromItemJson(json),
      isLocked: json['locked'] == true || json['is_locked'] == true,
      raw: Map<String, dynamic>.from(json),
    );
  }

  String get displayImageUrl {
    for (final value in [boardImageUrl, normalizedUrl, maskedUrl, imageUrl]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  bool get hasStableIdentity => id.trim().isNotEmpty;
  bool get isLockable =>
      hasStableIdentity &&
      source != 'unknown' &&
      role != BoardItemRole.unknown &&
      (position?.isUsable ?? false);

  StyleBoardItem copyWith({bool? isLocked, bool? isRegenerating}) =>
      StyleBoardItem(
        id: id,
        slot: slot,
        boardRole: boardRole,
        source: source,
        accessoryType: accessoryType,
        name: name,
        imageUrl: imageUrl,
        maskedUrl: maskedUrl,
        boardImageUrl: boardImageUrl,
        normalizedUrl: normalizedUrl,
        category: category,
        subCategory: subCategory,
        role: role,
        position: position,
        isLocked: isLocked ?? this.isLocked,
        isRegenerating: isRegenerating ?? this.isRegenerating,
        raw: raw,
      );

  Map<String, dynamic> toContractJson() {
    final value = Map<String, dynamic>.from(raw);
    value.addAll({
      'item_id': id,
      'slot': slot,
      'role': role.name,
      'board_role': boardRole,
      'source': source,
      'accessory_type': accessoryType,
      'name': name,
      'category': category,
      'sub_category': subCategory,
      'image_url': imageUrl,
      'masked_url': maskedUrl,
      'board_image_url': boardImageUrl,
      'normalized_url': normalizedUrl,
      'locked': isLocked,
    });
    if (position != null) value['position'] = position!.toJson();
    value.removeWhere((_, item) => item == null || item == '');
    return value;
  }
}

@immutable
class BoardPosition {
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final double? scale;
  final double? rotation;
  final int? z;

  const BoardPosition({
    this.x,
    this.y,
    this.width,
    this.height,
    this.scale,
    this.rotation,
    this.z,
  });

  factory BoardPosition.fromItemJson(Map<String, dynamic> json) {
    final nested = json['position'];
    final source = nested is Map ? Map<String, dynamic>.from(nested) : json;
    final position = BoardPosition(
      x: _double(source['x']),
      y: _double(source['y']),
      width: _double(source['width']),
      height: _double(source['height']),
      scale: _double(source['scale']),
      rotation: _double(source['rotation']),
      z: _int(source['z']),
    );
    return position.hasAnyValue ? position : const BoardPosition();
  }

  bool get hasAnyValue =>
      [x, y, width, height, scale, rotation, z].any((v) => v != null);
  bool get isUsable =>
      x != null && y != null && width != null && height != null;
  Map<String, dynamic> toJson() => {
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (scale != null) 'scale': scale,
    if (rotation != null) 'rotation': rotation,
    if (z != null) 'z': z,
  };
}

BoardItemRole boardItemRoleFromText(String value) =>
    switch (value.trim().toLowerCase()) {
      'top' => BoardItemRole.top,
      'bottom' => BoardItemRole.bottom,
      'footwear' => BoardItemRole.footwear,
      'outerwear' => BoardItemRole.outerwear,
      'dress' => BoardItemRole.dress,
      'accessory' ||
      'bag' ||
      'watch' ||
      'belt' ||
      'necklace' ||
      'bracelet' ||
      'ring' ||
      'earring' ||
      'eyewear' ||
      'headwear' => BoardItemRole.accessory,
      _ => BoardItemRole.unknown,
    };

String _firstText(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String _canonicalSource(dynamic value) =>
    switch (value?.toString().trim().toLowerCase()) {
      'wardrobe' || 'user_wardrobe' || 'uploaded' || 'closet' => 'wardrobe',
      'style_asset' ||
      'asset' ||
      'asset_library' ||
      'curated' ||
      'style-library' ||
      'style_library' => 'style_asset',
      'catalog' || 'commerce' => 'catalog',
      'generated' => 'generated',
      _ => 'unknown',
    };
double? _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
int? _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

/// Premium board story object emitted by the backend `board_storyteller`.
///
/// Every field is nullable so the UI can degrade gracefully when the backend
/// does not yet supply story data.
@immutable
class BoardStory {
  final String? headline;
  final String? summary;
  final String? why;
  final String? personalNote;
  final String? occasionFit;
  final String? tip;
  final String? role;

  const BoardStory({
    this.headline,
    this.summary,
    this.why,
    this.personalNote,
    this.occasionFit,
    this.tip,
    this.role,
  });

  factory BoardStory.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BoardStory();
    String? read(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return BoardStory(
      headline: read('headline'),
      summary: read('summary'),
      why: read('why'),
      personalNote: read('personal_note'),
      occasionFit: read('occasion_fit'),
      tip: read('tip'),
      role: read('role'),
    );
  }

  bool get isEmpty =>
      (headline == null || headline!.isEmpty) &&
      (summary == null || summary!.isEmpty) &&
      (why == null || why!.isEmpty) &&
      (personalNote == null || personalNote!.isEmpty) &&
      (occasionFit == null || occasionFit!.isEmpty) &&
      (tip == null || tip!.isEmpty) &&
      (role == null || role!.isEmpty);

  bool get hasExpandableContent =>
      (why != null && why!.isNotEmpty) ||
      (personalNote != null && personalNote!.isNotEmpty) ||
      (occasionFit != null && occasionFit!.isNotEmpty) ||
      (tip != null && tip!.isNotEmpty);
}

@immutable
class StyleBoardData {
  final String boardId;
  final int revision;
  final String title;
  final String? styleArchetype;
  final String? boardRole;
  final String? occasion;
  final String? whyItWorks;
  final List<StyleBoardItem> items;
  final BoardStory? story;
  final String? stylingTip;

  const StyleBoardData({
    this.boardId = '',
    this.revision = 0,
    required this.title,
    this.styleArchetype,
    this.boardRole,
    this.occasion,
    this.whyItWorks,
    required this.items,
    this.story,
    this.stylingTip,
  });

  /// Preferred short copy for collapsed cards.
  String? get summaryText =>
      story?.summary ??
      whyItWorks ??
      (occasion?.isNotEmpty == true ? occasion : null);

  /// Preferred long copy for expanded "why this works".
  String? get whyText => story?.why ?? whyItWorks;

  /// Preferred copy for styling tip rows.
  String? get tipText => story?.tip ?? stylingTip;

  /// Preferred role badge (e.g. "Safest polished option").
  String? get roleLabel => boardRole ?? story?.role ?? occasion;
}

/// Existing/legacy section layout modes. Keep while older board renderers migrate.
enum BoardLayoutMode {
  dress,
  outerwearLayered,
  tripletClassic,
  pairWithFoot,
  accessoryHeavy,
  singleItem,
  empty,
}

@immutable
class BoardLayoutResult {
  final BoardLayoutMode mode;
  final StyleBoardItem? hero;
  final StyleBoardItem? outerwear;
  final StyleBoardItem? top;
  final StyleBoardItem? bottom;
  final StyleBoardItem? footwear;
  final List<StyleBoardItem> accessories;
  final double accessorySectionHeight;
  final int accessoryColumns;

  const BoardLayoutResult({
    required this.mode,
    required this.hero,
    required this.outerwear,
    required this.top,
    required this.bottom,
    required this.footwear,
    required this.accessories,
    required this.accessorySectionHeight,
    required this.accessoryColumns,
  });
}

/// New editorial/freeform layout modes for Pinterest-style flat-lay boards.
enum EditorialLayoutMode {
  classicThreePlusAccessory,
  dressFocused,
  outerwearLayered,
  accessoryHeavy,
  generic,
  empty,
}

@immutable
class BoardItemPlacement {
  final StyleBoardItem item;

  /// Absolute pixel values computed by LayoutBuilder.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Rotation in radians. Keep small values like -0.04 or 0.05.
  final double rotation;

  /// Higher zIndex appears above lower zIndex.
  final int zIndex;

  const BoardItemPlacement({
    required this.item,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.zIndex = 0,
  });

  BoardItemPlacement copyWith({
    StyleBoardItem? item,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
  }) {
    return BoardItemPlacement(
      item: item ?? this.item,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}

@immutable
class EditorialLayoutResult {
  final EditorialLayoutMode mode;
  final List<BoardItemPlacement> placements;

  const EditorialLayoutResult({required this.mode, required this.placements});

  bool get isEmpty => placements.isEmpty;
}
