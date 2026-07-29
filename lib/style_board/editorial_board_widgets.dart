import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'board_models.dart';

/// Central per-role visual zoom applied to each garment cutout INSIDE its
/// existing placement box. Transparent-PNG cutouts leave the visible garment
/// small inside the image rectangle (footwear worst), so a mild role-aware zoom
/// lifts visible density without touching layout rectangles, card size, action
/// bars or board behaviour. Aspect ratio is preserved (uniform scale).
double editorialVisualScaleForRole(BoardItemRole role) {
  switch (role) {
    case BoardItemRole.top:
      return 1.15;
    case BoardItemRole.bottom:
      return 1.10;
    case BoardItemRole.dress:
      return 1.12;
    case BoardItemRole.outerwear:
      return 1.12;
    case BoardItemRole.footwear:
      return 1.38; // shoes carry the most transparent padding
    case BoardItemRole.accessory:
      return 1.16; // bags / jewellery collapse into accessory
    case BoardItemRole.unknown:
      return 1.08;
  }
}

/// Zoom anchor per role. Bottoms anchor to the top so the waistband stays put
/// and the zoom grows downward; every other role zooms about its centre.
Alignment editorialAlignmentForRole(BoardItemRole role) {
  switch (role) {
    case BoardItemRole.bottom:
      return Alignment.topCenter;
    case BoardItemRole.top:
    case BoardItemRole.dress:
    case BoardItemRole.outerwear:
    case BoardItemRole.footwear:
    case BoardItemRole.accessory:
    case BoardItemRole.unknown:
      return Alignment.center;
  }
}

class EditorialBoardItem extends StatelessWidget {
  final StyleBoardItem item;
  final double rotation;

  const EditorialBoardItem({super.key, required this.item, this.rotation = 0});

  @override
  Widget build(BuildContext context) {
    final garment = Image.network(
      item.imageUrl,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: Colors.black26,
        ),
      ),
    );
    final content = Transform.rotate(
      angle: rotation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft drop-shadow so a light/white cutout (white trousers, white
          // sneakers, off-white shirt) stays visible on the off-white board
          // canvas. The bare Image had zero separation and vanished into the
          // background, making the board look empty.
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(0, 4),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Image.network(
                  item.imageUrl,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  color: Colors.black.withValues(alpha: 0.22),
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          garment,
        ],
      ),
    );
    // Per-role visual zoom (paint-only): enlarges the visible cutout inside its
    // existing box. Layout size is unchanged, so the box, lock button and card
    // dimensions stay put; the canvas Stack (Clip.hardEdge) clips any bleed at
    // the board edge.
    return Transform.scale(
      key: item.hasStableIdentity
          ? ValueKey<String>('vscale-${item.itemId}')
          : null,
      scale: editorialVisualScaleForRole(item.role),
      alignment: editorialAlignmentForRole(item.role),
      filterQuality: FilterQuality.high,
      child: content,
    );
  }
}
