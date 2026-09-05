import 'package:flutter/material.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/theme/theme_tokens.dart';

@immutable
class AhviUnifiedOutfitGridItem {
  final String id;
  final String name;
  final String category;
  final String resolvedImageUrl;
  final String sourceKind;
  final bool isTransparent;
  final bool isAnchor;
  final bool isLocked;
  final bool isPlaceholder;
  final bool isLoading;

  const AhviUnifiedOutfitGridItem({
    required this.id,
    required this.name,
    required this.category,
    required this.resolvedImageUrl,
    this.sourceKind = '',
    this.isTransparent = false,
    this.isAnchor = false,
    this.isLocked = false,
    this.isPlaceholder = false,
    this.isLoading = false,
  });

  factory AhviUnifiedOutfitGridItem.fromStyleBoardItem(
    StyleBoardItem item, {
    bool isAnchor = false,
    bool? isLocked,
    String surface = 'unified_outfit_grid',
  }) {
    final resolved = item.resolveImage(surface: surface);
    final parsedField = item.raw['_image_field']?.toString().trim() ?? '';
    final useParsedImage =
        resolved.url == null &&
        parsedField.isNotEmpty &&
        parsedField != 'none' &&
        item.imageUrl.isNotEmpty;
    return AhviUnifiedOutfitGridItem(
      id: item.itemId,
      name: item.name,
      category: item.category.isNotEmpty ? item.category : item.slot,
      resolvedImageUrl: resolved.url ?? (useParsedImage ? item.imageUrl : ''),
      sourceKind: useParsedImage
          ? (item.raw['_image_source_kind']?.toString() ?? '')
          : resolved.sourceKind,
      isTransparent: useParsedImage
          ? item.raw['_image_expected_transparent'] == true
          : resolved.expectedTransparent,
      isAnchor: isAnchor,
      isLocked: isLocked ?? item.isLocked,
      isLoading: item.isRegenerating,
    );
  }
}

/// The shared garment body extracted from StyleBoardsScreen._buildUnifiedGrid.
/// Surface shells own titles, reasoning, actions, and mutation state.
class AhviUnifiedOutfitGrid extends StatelessWidget {
  static const gridKey = ValueKey<String>('ahvi-unified-outfit-grid');
  static const double gap = 10;
  static const double _maxCardExtent = 140;
  // Cap at 2x so a high-DPI device doesn't decode a 1500-3000px source
  // cutout at native resolution for a ~140px card (mirrors daily_wear.dart's
  // chat-image _cacheWidth cap).
  static const double _maxDecodeDpr = 2.0;

  final List<AhviUnifiedOutfitGridItem> items;
  final ValueChanged<String>? onItemTap;
  final ValueChanged<String>? onToggleLock;
  final ImageProvider<Object> Function(String url)? imageProviderBuilder;

  /// Shows the item name (max 2 lines) below each tile. Off by default so
  /// Style Boards / Saved Boards / Style This keep their existing collage
  /// appearance unchanged -- only Daily Wear opts in.
  final bool showItemLabels;

  const AhviUnifiedOutfitGrid({
    super.key,
    required this.items,
    this.onItemTap,
    this.onToggleLock,
    this.imageProviderBuilder,
    this.showItemLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final visibleItems = items.take(8).toList(growable: false);
    if (showItemLabels) {
      return KeyedSubtree(
        key: gridKey,
        child: _labeledGrid(context, visibleItems),
      );
    }
    return KeyedSubtree(
      key: gridKey,
      child: switch (visibleItems.length) {
        1 || 2 => _layoutSmall(context, visibleItems),
        3 => _layout3(context, visibleItems),
        4 => _layout4(context, visibleItems),
        5 => _layout5(context, visibleItems),
        6 => _layout6(context, visibleItems),
        7 => _layout7(context, visibleItems),
        _ => _layout8(context, visibleItems),
      },
    );
  }

  /// Plain uniform grid used only when [showItemLabels] is true. The
  /// collage layouts below (_layout3.._layout8) pack tiles into
  /// irregular, tightly-cropped shapes with no room for text -- retrofitting
  /// per-item labels into them would mean clipped/overlaid names, so labelled
  /// surfaces get simple equal-size tiles instead.
  Widget _labeledGrid(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppThemeTokens>();
    final textColor = tokens?.textPrimary ?? theme.colorScheme.onSurface;
    final labelStyle = (theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12))
        .copyWith(color: textColor, fontWeight: FontWeight.w600, height: 1.2);
    // Text scales with accessibility settings, so the reserved height below
    // each image must scale with it too or a 2-line name at a large text
    // scale overflows the tile instead of just wrapping.
    final textScaler = MediaQuery.textScalerOf(context);
    final lineHeight = (labelStyle.fontSize ?? 12) * (labelStyle.height ?? 1.2);
    const labelTopGap = 6.0;
    // +2 buffer: TextPainter's actual line-box height can round up a
    // fraction of a pixel past this estimate, which would otherwise trip a
    // RenderFlex overflow by well under a pixel.
    final labelReserve = textScaler.scale(lineHeight) * 2 + labelTopGap + 2;
    return LayoutBuilder(
      builder: (_, box) {
        final columns = items.length <= 1 ? 1 : 2;
        final cellWidth = _cappedCellWidth(box.maxWidth, gap, columns);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: cellWidth + labelReserve,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => SizedBox(
            width: cellWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: cellWidth,
                  child: _itemCard(context, items[i]),
                ),
                const SizedBox(height: labelTopGap),
                Text(
                  _labelFor(items[i]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// display_name/name/title already resolved by StyleBoardItem.fromJson;
  /// category is the only remaining fallback when no usable name exists.
  String _labelFor(AhviUnifiedOutfitGridItem item) {
    final name = item.name.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'item') return name;
    final category = item.category.trim();
    return category.isNotEmpty ? category : 'Item';
  }

  double _cappedCellWidth(double totalWidth, double gap, int columns) {
    final raw = (totalWidth - gap * (columns - 1)) / columns;
    return raw < _maxCardExtent ? raw : _maxCardExtent;
  }

  Widget _layoutSmall(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final n = items.length;
      final cellWidth = _cappedCellWidth(box.maxWidth, gap, n);
      return Center(
        child: SizedBox(
          width: cellWidth * n + gap * (n - 1),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              childAspectRatio: 1.15,
            ),
            itemCount: n,
            itemBuilder: (_, i) => _itemCard(context, items[i]),
          ),
        ),
      );
    },
  );

  Widget _layout3(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final cellWidth = _cappedCellWidth(box.maxWidth, gap, 2);
      final totalHeight = cellWidth * 2 + gap;
      return Center(
        child: SizedBox(
          width: cellWidth * 2 + gap,
          height: totalHeight,
          child: Row(
            children: [
              SizedBox(
                width: cellWidth,
                height: totalHeight,
                child: _itemCard(context, items[0]),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: cellWidth,
                child: Column(
                  children: [
                    SizedBox(
                      height: cellWidth,
                      child: _itemCard(context, items[1]),
                    ),
                    const SizedBox(height: gap),
                    SizedBox(
                      height: cellWidth,
                      child: _itemCard(context, items[2]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _layout4(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final cellWidth = _cappedCellWidth(box.maxWidth, gap, 2);
      return Center(
        child: SizedBox(
          width: cellWidth * 2 + gap,
          child: Column(
            children: [
              _row(context, items.sublist(0, 2), cellWidth),
              const SizedBox(height: gap),
              _row(context, items.sublist(2, 4), cellWidth),
            ],
          ),
        ),
      );
    },
  );

  Widget _layout5(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final width = box.maxWidth;
      final topLeftWidth = width * 0.42 - gap / 2;
      final topHeight = topLeftWidth / 0.72;
      final remainingWidth = width - topLeftWidth - gap;
      final topRightWidth = remainingWidth * 0.72;
      final topRightHeight = topHeight * 0.88;
      final bottomWidth = (width - 2 * gap) / 3;
      return Column(
        children: [
          SizedBox(
            height: topHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: topLeftWidth,
                  child: _itemCard(context, items[0]),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: remainingWidth,
                  child: Center(
                    child: SizedBox(
                      width: topRightWidth,
                      height: topRightHeight,
                      child: _itemCard(context, items[1]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          _row(context, items.sublist(2, 5), bottomWidth),
        ],
      );
    },
  );

  Widget _layout6(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final cellWidth = (box.maxWidth - 2 * gap) / 3;
      return Column(
        children: [
          _row(context, items.sublist(0, 3), cellWidth),
          const SizedBox(height: gap),
          _row(context, items.sublist(3, 6), cellWidth),
        ],
      );
    },
  );

  Widget _layout7(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final cellWidth = (box.maxWidth - 2 * gap) / 3;
      return SizedBox(
        height: cellWidth * 3 + 2 * gap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _column(context, items.sublist(0, 2), cellWidth),
            const SizedBox(width: gap),
            _column(context, items.sublist(2, 4), cellWidth),
            const SizedBox(width: gap),
            _column(context, items.sublist(4, 7), cellWidth),
          ],
        ),
      );
    },
  );

  Widget _layout8(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> items,
  ) => LayoutBuilder(
    builder: (_, box) {
      final width = box.maxWidth;
      final topLeftWidth = width * 0.30 - gap * 2 / 3;
      final topCenterWidth = width * 0.42 - gap * 2 / 3;
      final topRightWidth = width - topLeftWidth - topCenterWidth - 2 * gap;
      final bottomItemWidth = (width - topLeftWidth - 3 * gap) / 3;
      return Column(
        children: [
          SizedBox(
            height: topCenterWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: topLeftWidth,
                  child: _itemCard(context, items[0]),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: topCenterWidth,
                  child: _itemCard(context, items[1]),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: topRightWidth,
                  child: Column(
                    children: [
                      Expanded(child: _itemCard(context, items[2])),
                      const SizedBox(height: gap),
                      Expanded(child: _itemCard(context, items[3])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          SizedBox(
            height: bottomItemWidth,
            child: Row(
              children: [
                SizedBox(
                  width: topLeftWidth,
                  child: _itemCard(context, items[4]),
                ),
                const SizedBox(width: gap),
                for (var i = 5; i < 8; i++) ...[
                  SizedBox(
                    width: bottomItemWidth,
                    child: _itemCard(context, items[i]),
                  ),
                  if (i < 7) const SizedBox(width: gap),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _row(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> row,
    double extent,
  ) => Row(
    children: [
      for (var i = 0; i < row.length; i++) ...[
        SizedBox(
          width: extent,
          height: extent,
          child: _itemCard(context, row[i]),
        ),
        if (i < row.length - 1) const SizedBox(width: gap),
      ],
    ],
  );

  Widget _column(
    BuildContext context,
    List<AhviUnifiedOutfitGridItem> column,
    double extent,
  ) => SizedBox(
    width: extent,
    child: Column(
      children: [
        for (var i = 0; i < column.length; i++) ...[
          SizedBox(height: extent, child: _itemCard(context, column[i])),
          if (i < column.length - 1) const SizedBox(height: gap),
        ],
      ],
    ),
  );

  Widget _itemCard(BuildContext context, AhviUnifiedOutfitGridItem item) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppThemeTokens>();
    final accent = tokens?.accent.primary ?? theme.colorScheme.primary;
    final background =
        tokens?.backgroundSecondary ?? theme.colorScheme.surfaceContainerLowest;
    final muted = tokens?.mutedText ?? theme.colorScheme.onSurfaceVariant;
    final imageUrl = item.resolvedImageUrl.trim();
    return GestureDetector(
      key: ValueKey<String>(item.id),
      onTap: onItemTap == null ? null : () => onItemTap!(item.id),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: item.isLocked ? accent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: background,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: LayoutBuilder(
                  builder: (cardContext, constraints) => Image(
                    image:
                        imageProviderBuilder?.call(imageUrl) ??
                        _decodeSizedProvider(cardContext, constraints, imageUrl),
                    fit: BoxFit.contain,
                    frameBuilder: (context, child, frame, synchronous) =>
                        synchronous || frame != null
                        ? child
                            : _placeholder(accent, muted, loading: true),
                    errorBuilder: (context, error, stackTrace) =>
                        _placeholder(accent, muted),
                  ),
                ),
              )
            else
              _placeholder(accent, muted, recommended: item.isPlaceholder),
            if (item.isLoading)
              ColoredBox(
                color: Colors.white.withValues(alpha: 0.25),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (onToggleLock != null)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  key: ValueKey<String>('lock-${item.id}'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => onToggleLock!(item.id),
                  icon: Icon(
                    item.isLocked
                        ? Icons.lock_rounded
                        : Icons.lock_outline_rounded,
                    size: 19,
                  ),
                  tooltip: item.isLocked
                      ? 'Locked ${item.name}'
                      : 'Lock ${item.name}',
                ),
              ),
            if (item.isLocked)
              Positioned(
                left: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      'Locked',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Decodes [url] at the card's actual rendered size (DPR-capped) instead
  /// of native resolution, via [ResizeImagePolicy.fit] so a non-square card
  /// never distorts the source's aspect ratio -- same URL, same resolver
  /// output, just a cheaper decode target. Falls back to an unresized
  /// [NetworkImage] when constraints aren't usable (e.g. unbounded in a
  /// test harness).
  static ImageProvider _decodeSizedProvider(
    BuildContext context,
    BoxConstraints constraints,
    String url,
  ) {
    final provider = NetworkImage(url);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cappedDpr = dpr.isFinite && dpr > 0
        ? dpr.clamp(1.0, _maxDecodeDpr)
        : _maxDecodeDpr;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final cacheWidth = width.isFinite && width > 0
        ? (width * cappedDpr).round()
        : null;
    final cacheHeight = height.isFinite && height > 0
        ? (height * cappedDpr).round()
        : null;
    if (cacheWidth == null && cacheHeight == null) return provider;
    return ResizeImage(
      provider,
      width: cacheWidth,
      height: cacheHeight,
      policy: ResizeImagePolicy.fit,
    );
  }

  Widget _placeholder(
    Color accent,
    Color muted, {
    bool loading = false,
    bool recommended = false,
  }) => Center(
    child: loading
        ? SizedBox.square(
            key: const ValueKey<String>('unified-grid-image-loading'),
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: accent,
            ),
          )
        : Icon(
            recommended ? Icons.auto_awesome : Icons.checkroom,
            color: recommended ? Colors.amber : muted,
            size: 28,
          ),
  );
}
