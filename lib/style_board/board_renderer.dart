import 'package:flutter/material.dart';

import 'package:myapp/widgets/offline_image.dart';
import 'board_layout_engine.dart';
import 'board_models.dart';

const _privateWearAliases = {
  'boxer',
  'boxer shorts',
  'briefs',
  'brief',
  'underwear',
  'undergarment',
  'innerwear',
  'trunks',
  'sports trunk',
  'compression shorts',
  'compression short',
  'base layer',
  'thermal inner',
  'lingerie',
  'sleep shorts',
  'pajama',
  'pyjama',
  'lounge shorts',
};

// Garment-identifying fields only — NOT prose (why_it_works / styling tips /
// story). The board's LLM copy legitimately says "base layer" / "layer this",
// and scanning the whole board blob false-flagged every look as private wear,
// suppressing it to the empty "Regenerate look" placeholder. Mirrors the
// backend fix in services/wardrobe_suitability.py:is_private_wear_item.
const _garmentIdentityFields = <String>[
  'name', 'label', 'title', 'garment_type', 'type',
  'category', 'sub_category', 'subcategory',
  'normalizedCategory', 'normalized_category',
  'normalizedSubCategory', 'normalized_sub_category',
  'style_role',
];

bool _itemIsPrivateWear(Map item) {
  final blob =
      ' ${_garmentIdentityFields.map((k) => item[k]?.toString() ?? '').join(' ').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  // Word-boundary match so "brief" doesn't fire on "briefly" and "base layer"
  // doesn't fire on prose.
  return _privateWearAliases.any((alias) => blob.contains(' $alias '));
}

bool _containsPrivateWear(Map<String, dynamic> value) {
  final items = value['items'];
  if (items is! List) return false;
  return items.any((r) => r is Map && _itemIsPrivateWear(r));
}

class StyleBoardBody extends StatelessWidget {
  final StyleBoardData board;
  final Color tileColor;
  final Color accessoryTileColor;

  const StyleBoardBody({
    super.key,
    required this.board,
    this.tileColor = const Color(0xFFF7F4EE),
    this.accessoryTileColor = const Color(0xFFF1ECE3),
  });

  @override
  Widget build(BuildContext context) {
    final layout = BoardLayoutEngine.resolve(board);
    final mainFlex = layout.mode == BoardLayoutMode.accessoryHeavy ? 4 : 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: mainFlex,
          child: _MainSection(layout: layout, tileColor: tileColor),
        ),
        if (layout.accessories.isNotEmpty) ...[
          const SizedBox(height: 10),
          _AccessorySection(
            items: layout.accessories,
            height: layout.accessorySectionHeight,
            columns: layout.accessoryColumns,
            tileColor: accessoryTileColor,
          ),
        ],
      ],
    );
  }
}

class _MainSection extends StatelessWidget {
  final BoardLayoutResult layout;
  final Color tileColor;

  const _MainSection({required this.layout, required this.tileColor});

  @override
  Widget build(BuildContext context) {
    switch (layout.mode) {
      case BoardLayoutMode.dress:
        return _dressMode();
      case BoardLayoutMode.outerwearLayered:
        return _outerwearLayeredMode();
      case BoardLayoutMode.tripletClassic:
        return _tripletClassicMode();
      case BoardLayoutMode.pairWithFoot:
        return _pairWithFootMode();
      case BoardLayoutMode.accessoryHeavy:
        return _accessoryHeavyMode();
      case BoardLayoutMode.singleItem:
        return _singleItemMode();
      case BoardLayoutMode.empty:
        return _EmptyState();
    }
  }

  Widget _dressMode() {
    final hero = layout.hero!;
    final outerwear = layout.outerwear;
    final footwear = layout.footwear;
    final sideItems = <StyleBoardItem>[?outerwear, ?footwear];
    if (sideItems.isEmpty) {
      return _ItemTile(item: hero, color: tileColor);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _ItemTile(item: hero, color: tileColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Column(
            children: [
              for (var i = 0; i < sideItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Expanded(
                  child: _ItemTile(item: sideItems[i], color: tileColor),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _outerwearLayeredMode() {
    final outer = layout.outerwear!;
    final top = layout.top!;
    final bottom = layout.bottom!;
    final footwear = layout.footwear;

    final leftStack = Column(
      children: [
        Expanded(
          flex: 3,
          child: _ItemTile(item: outer, color: tileColor),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 2,
          child: _ItemTile(item: top, color: tileColor),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: _ItemTile(item: bottom, color: tileColor),
        ),
      ],
    );

    if (footwear == null) return leftStack;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: leftStack),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _ItemTile(item: footwear, color: tileColor),
        ),
      ],
    );
  }

  Widget _tripletClassicMode() {
    final top = layout.top!;
    final bottom = layout.bottom!;
    final footwear = layout.footwear;

    final stack = Column(
      children: [
        Expanded(
          child: _ItemTile(item: top, color: tileColor),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _ItemTile(item: bottom, color: tileColor),
        ),
      ],
    );

    if (footwear == null) return stack;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: stack),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _ItemTile(item: footwear, color: tileColor),
        ),
      ],
    );
  }

  Widget _pairWithFootMode() {
    final main = layout.outerwear ?? layout.top ?? layout.bottom;
    final foot = layout.footwear!;
    if (main == null) return _ItemTile(item: foot, color: tileColor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ItemTile(item: main, color: tileColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ItemTile(item: foot, color: tileColor),
        ),
      ],
    );
  }

  Widget _accessoryHeavyMode() {
    final mains = <StyleBoardItem>[
      if (layout.outerwear != null) layout.outerwear!,
      if (layout.top != null) layout.top!,
      if (layout.bottom != null) layout.bottom!,
      if (layout.footwear != null) layout.footwear!,
    ];
    if (mains.isEmpty) return _EmptyState();
    if (mains.length == 1) {
      return _ItemTile(item: mains.first, color: tileColor);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < mains.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ItemTile(item: mains[i], color: tileColor),
          ),
        ],
      ],
    );
  }

  Widget _singleItemMode() {
    final pick =
        layout.outerwear ??
        layout.top ??
        layout.bottom ??
        layout.footwear ??
        layout.hero;
    if (pick == null) return _EmptyState();
    return _ItemTile(item: pick, color: tileColor);
  }
}

class _AccessorySection extends StatelessWidget {
  final List<StyleBoardItem> items;
  final double height;
  final int columns;
  final Color tileColor;

  const _AccessorySection({
    required this.items,
    required this.height,
    required this.columns,
    required this.tileColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemBuilder: (_, i) =>
            _ItemTile(item: items[i], color: tileColor, compact: true),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final StyleBoardItem item;
  final Color color;
  final bool compact;

  const _ItemTile({
    required this.item,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      child: Container(
        color: color,
        padding: EdgeInsets.all(compact ? 4 : 8),
        child: item.imageUrl.isEmpty
            ? _placeholder()
            : OfflineImage(
                imageUrl: item.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Text(
        item.name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'No outfit items',
        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Returns the first valid transparent-PNG URL for a board item, or empty string.
/// Priority: board_image_url → transparent_image_url → cutout_url (if ready)
///   → image_url if board_status == cutout_ready.
/// Never falls back to normalized/original opaque product images.
String _selectTransparentUrl(Map<String, dynamic> m, {required String name}) {
  for (final key in const <String>[
    'board_image_url',
    'boardImageUrl',
    'transparent_image_url',
    'transparentImageUrl',
  ]) {
    final v = m[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final cutoutStatus =
      (m['cutout_status'] ?? m['cutoutStatus'] ?? '').toString().toLowerCase().trim();
  final cutoutUrl = (m['cutout_url'] ?? m['cutoutUrl'] ?? '').toString().trim();
  if (cutoutUrl.isNotEmpty && cutoutStatus == 'ready') return cutoutUrl;

  final boardStatus =
      (m['board_status'] ?? m['boardStatus'] ?? '').toString().toLowerCase().trim();
  if (boardStatus == 'cutout_ready') {
    final imageUrl = (m['image_url'] ?? m['imageUrl'] ?? '').toString().trim();
    if (imageUrl.isNotEmpty) return imageUrl;
  }

  debugPrint(
    'AHVI_BOARD_ASSET_SKIPPED_NON_TRANSPARENT '
    'name=$name '
    'attempted_url_fields=[board_image_url,transparent_image_url,cutout_url,image_url(board_status=cutout_ready)] '
    'cutout_status=$cutoutStatus '
    'board_status=$boardStatus '
    'reason=no_transparent_png_available',
  );
  return '';
}

StyleBoardData boardDataFromMap(Map<String, dynamic> board) {
  if (_containsPrivateWear(board)) {
    return const StyleBoardData(
      title: 'Regenerate look',
      occasion: '',
      whyItWorks: 'This look included a private-wear item, so AHVI suppressed it.',
      items: [],
    );
  }
  final rawItems = board['items'] as List? ?? const [];
  final items = <StyleBoardItem>[];
  for (final r in rawItems) {
    if (r is! Map) continue;
    final m = Map<String, dynamic>.from(r);
    final name =
        (m['name'] ?? m['label'] ?? m['title'] ?? m['category'] ?? 'Item')
            .toString();
    final imageUrl = _selectTransparentUrl(m, name: name);
    // Skip items with no transparent PNG — never fall back to opaque tiles.
    if (imageUrl.isEmpty) continue;
    final category =
        (m['category'] ??
                m['sub_category'] ??
                m['subcategory'] ??
                m['type'] ??
                '')
            .toString();
    final id = (m[r'$id'] ?? m['id'] ?? m['item_id'] ?? name).toString();
    items.add(
      StyleBoardItem(
        id: id,
        name: name,
        imageUrl: imageUrl,
        category: category,
        role: BoardLayoutEngine.resolveRole(category, name: name),
        raw: m,
      ),
    );
  }
  final rawStory = board['story'];
  final story = rawStory is Map
      ? BoardStory.fromJson(Map<String, dynamic>.from(rawStory))
      : const BoardStory();
  final styleMetadata = board['style_metadata'] is Map
      ? Map<String, dynamic>.from(board['style_metadata'] as Map)
      : const <String, dynamic>{};
  return StyleBoardData(
    title:
        (board['title'] ?? board['look_name'] ?? board['name'] ?? 'Styled Look')
            .toString(),
    styleArchetype:
        (board['style_archetype'] ?? styleMetadata['style_archetype'])
            ?.toString(),
    boardRole: (board['board_role'] ?? styleMetadata['board_role'])?.toString(),
    occasion: (board['occasion'] ?? board['intent'] ?? '').toString(),
    whyItWorks:
        (board['why_it_works'] ??
                board['whyItWorks'] ??
                board['explanation'] ??
                '')
            .toString(),
    items: items,
    story: story.isEmpty ? null : story,
    stylingTip: (board['styling_tip'] ?? board['stylingTip'])?.toString(),
  );
}
