import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'board_models.dart';

/// Editorial flat-lay layout engine.
///
/// Goal: outfit cutouts must occupy ~75-85% of the 9:16 board canvas while
/// still reading as a premium editorial flat-lay (overlap, slight rotation,
/// role-aware placement) — never a centred cluster floating in white space.
///
/// Cutout image dimensions are unknown at layout time (they only arrive after
/// the network image loads), so each role is sized from a typical garment
/// aspect ratio [_arForRole]. Matching the box aspect ratio to the garment's
/// natural shape keeps `BoxFit.contain` from leaving large empty gutters inside
/// each box — the main reason the old boards looked half-empty.
class EditorialBoardLayoutEngine {
  /// Typical garment aspect ratio as height / width. Used to derive a box
  /// height from its width so the contained cutout fills the box. Conservative
  /// (slightly tall) values keep garments from being clipped.
  static double _arForRole(BoardItemRole role) {
    switch (role) {
      case BoardItemRole.top:
        return 1.18; // shirts/tops: a touch taller than square
      case BoardItemRole.bottom:
        return 1.55; // jeans/trousers: tall and narrow
      case BoardItemRole.dress:
        return 1.70; // dresses/gowns: tallest
      case BoardItemRole.outerwear:
        return 1.35; // jackets/coats
      case BoardItemRole.footwear:
        return 0.62; // shoes: wide and short
      case BoardItemRole.accessory:
        return 1.05; // bags/watches: near-square
      case BoardItemRole.unknown:
        return 1.20;
    }
  }

  static EditorialLayoutResult resolve(
    StyleBoardData board, {
    required double width,
    required double height,
  }) {
    // Guard: a degenerate canvas (zero / NaN / Infinity) can crash Positioned.
    if (!_finitePositive(width) || !_finitePositive(height)) {
      return const EditorialLayoutResult(
        mode: EditorialLayoutMode.empty,
        placements: <BoardItemPlacement>[],
      );
    }

    final top = _firstOf(board.items, BoardItemRole.top);
    final bottom = _firstOf(board.items, BoardItemRole.bottom);
    final footwear = _firstOf(board.items, BoardItemRole.footwear);
    final dress = _firstOf(board.items, BoardItemRole.dress);
    final outerwear = _firstOf(board.items, BoardItemRole.outerwear);
    final accessories = board.items
        .where((e) => e.role == BoardItemRole.accessory)
        .toList(growable: false);

    if (board.items.isEmpty) {
      return const EditorialLayoutResult(
        mode: EditorialLayoutMode.empty,
        placements: <BoardItemPlacement>[],
      );
    }

    final EditorialLayoutResult raw;
    if (dress != null) {
      raw = _dressFocused(
        dress: dress,
        footwear: footwear,
        outerwear: outerwear,
        accessories: accessories,
        width: width,
        height: height,
      );
    } else if (top != null && bottom != null && footwear != null) {
      if (accessories.length <= 2) {
        raw = _classicThreePlusAccessory(
          top: top,
          bottom: bottom,
          footwear: footwear,
          outerwear: outerwear,
          accessories: accessories,
          width: width,
          height: height,
        );
      } else {
        raw = _accessoryHeavy(
          mainItems: <StyleBoardItem>[
            ?outerwear,
            top,
            bottom,
            footwear,
          ],
          accessories: accessories,
          width: width,
          height: height,
        );
      }
    } else {
      raw = _generic(items: board.items, width: width, height: height);
    }

    // Enforce safe zones, then sanitize any non-finite/overflowing geometry.
    final safe = _applySafeZone(raw.placements, width, height);
    final sane = _sanitize(safe, width, height);
    // Coverage-gated composition pass: only sparse boards get enlarged; a dense
    // template (the common 3-piece already fills ~85%) is returned untouched.
    final dense = _normalizeComposition(sane, width, height);
    final finalPlacements = _sanitize(
      _applySafeZone(dense, width, height),
      width,
      height,
    );
    _logLayout(raw.mode, finalPlacements, width, height);
    return EditorialLayoutResult(mode: raw.mode, placements: finalPlacements);
  }

  static StyleBoardItem? _firstOf(
    List<StyleBoardItem> items,
    BoardItemRole role,
  ) {
    for (final item in items) {
      if (item.role == role) return item;
    }
    return null;
  }

  /// Box height for [role] at the given box [boxWidth], capped so the box never
  /// exceeds [maxHeight] of canvas (prevents tall garments overflowing).
  static double _boxHeight(
    BoardItemRole role,
    double boxWidth,
    double maxHeight,
  ) {
    final h = boxWidth * _arForRole(role);
    return h.clamp(0.0, maxHeight);
  }

  static EditorialLayoutResult _classicThreePlusAccessory({
    required StyleBoardItem top,
    required StyleBoardItem bottom,
    required StyleBoardItem footwear,
    required StyleBoardItem? outerwear,
    required List<StyleBoardItem> accessories,
    required double width,
    required double height,
  }) {
    final hasOuter = outerwear != null;
    final placements = <BoardItemPlacement>[];

    if (hasOuter) {
      // Layered look: outerwear is the large background/side anchor, the top
      // layers over it, jeans drop lower-right, footwear lower-left.
      final outerW = width * 0.58;
      placements.add(
        BoardItemPlacement(
          item: outerwear,
          x: width * 0.04,
          y: height * 0.04,
          width: outerW,
          height: _boxHeight(BoardItemRole.outerwear, outerW, height * 0.60),
          rotation: -0.03,
          zIndex: 0,
        ),
      );
      final topW = width * 0.46;
      placements.add(
        BoardItemPlacement(
          item: top,
          x: width * 0.16,
          y: height * 0.10,
          width: topW,
          height: _boxHeight(BoardItemRole.top, topW, height * 0.42),
          rotation: -0.015,
          zIndex: 2,
        ),
      );
      final botW = width * 0.48;
      placements.add(
        BoardItemPlacement(
          item: bottom,
          x: width * 0.46,
          y: height * 0.42,
          width: botW,
          height: _boxHeight(BoardItemRole.bottom, botW, height * 0.50),
          rotation: 0.01,
          zIndex: 1,
        ),
      );
    } else {
      // Pure 3-piece flat-lay. Hero top spans the upper canvas, jeans pulled UP
      // and right to overlap the top's hem (kills the dead vertical gap), shoes
      // anchor lower-left. Widths are aggressive (~0.62 / 0.50) and heights are
      // AR-matched so each cutout fills its box edge-to-edge.
      final topW = width * 0.62;
      placements.add(
        BoardItemPlacement(
          item: top,
          x: width * 0.15,
          y: height * 0.07,
          width: topW,
          height: _boxHeight(BoardItemRole.top, topW, height * 0.52),
          rotation: -0.02,
          zIndex: 2,
        ),
      );
      final botW = width * 0.50;
      placements.add(
        BoardItemPlacement(
          item: bottom,
          x: width * 0.45,
          y: height * 0.40,
          width: botW,
          height: _boxHeight(BoardItemRole.bottom, botW, height * 0.52),
          rotation: 0.015,
          zIndex: 1,
        ),
      );
    }

    final footW = width * 0.46;
    placements.add(
      BoardItemPlacement(
        item: footwear,
        x: width * 0.10,
        y: height * 0.70,
        width: footW,
        height: _boxHeight(BoardItemRole.footwear, footW, height * 0.22),
        rotation: -0.03,
        zIndex: 3,
      ),
    );

    for (var i = 0; i < math.min(accessories.length, 2); i++) {
      // i==0 = small jewelry/accessory mid-right; i==1 = bag/extra upper-right,
      // a touch larger but never dominant. Both kept off the main garments.
      final accW = width * (i == 0 ? 0.17 : 0.22);
      placements.add(
        BoardItemPlacement(
          item: accessories[i],
          x: width * (i == 0 ? 0.70 : 0.68),
          y: height * (i == 0 ? 0.40 : 0.18),
          width: accW,
          height: _boxHeight(BoardItemRole.accessory, accW, height * 0.22),
          rotation: i == 0 ? 0.06 : -0.04,
          zIndex: i == 0 ? 4 : 3,
        ),
      );
    }

    return EditorialLayoutResult(
      mode: EditorialLayoutMode.classicThreePlusAccessory,
      placements: _sorted(placements),
    );
  }

  static EditorialLayoutResult _dressFocused({
    required StyleBoardItem dress,
    required StyleBoardItem? footwear,
    required StyleBoardItem? outerwear,
    required List<StyleBoardItem> accessories,
    required double width,
    required double height,
  }) {
    final dressW = width * 0.64;
    final placements = <BoardItemPlacement>[
      BoardItemPlacement(
        item: dress,
        x: width * 0.16,
        y: height * 0.04,
        width: dressW,
        height: _boxHeight(BoardItemRole.dress, dressW, height * 0.74),
        rotation: 0.01,
        zIndex: 2,
      ),
    ];

    if (outerwear != null) {
      final outerW = width * 0.40;
      placements.add(
        BoardItemPlacement(
          item: outerwear,
          x: width * 0.01,
          y: height * 0.10,
          width: outerW,
          height: _boxHeight(BoardItemRole.outerwear, outerW, height * 0.50),
          rotation: -0.04,
          zIndex: 1,
        ),
      );
    }

    if (footwear != null) {
      final footW = width * 0.44;
      placements.add(
        BoardItemPlacement(
          item: footwear,
          x: width * 0.06,
          y: height * 0.71,
          width: footW,
          height: _boxHeight(BoardItemRole.footwear, footW, height * 0.20),
          rotation: -0.02,
          zIndex: 3,
        ),
      );
    }

    for (var i = 0; i < math.min(accessories.length, 3); i++) {
      final accW = width * 0.20;
      placements.add(
        BoardItemPlacement(
          item: accessories[i],
          x: width * (0.70 - (i % 2) * 0.16),
          y: height * (0.66 + (i ~/ 2) * 0.14),
          width: accW,
          height: _boxHeight(BoardItemRole.accessory, accW, height * 0.18),
          rotation: i.isEven ? 0.05 : -0.04,
          zIndex: 4,
        ),
      );
    }

    return EditorialLayoutResult(
      mode: EditorialLayoutMode.dressFocused,
      placements: _sorted(placements),
    );
  }

  static EditorialLayoutResult _accessoryHeavy({
    required List<StyleBoardItem> mainItems,
    required List<StyleBoardItem> accessories,
    required double width,
    required double height,
  }) {
    final placements = <BoardItemPlacement>[];
    // Main garments take the upper ~70% in a 2-column editorial block; the
    // accessory cluster sits lower-right. Wider than the old template so the
    // canvas still fills even with many small items.
    final mainTemplates = <_Template>[
      const _Template(0.02, 0.06, 0.42, -0.03, 2),
      const _Template(0.46, 0.04, 0.50, 0.02, 1),
      const _Template(0.04, 0.42, 0.46, -0.02, 3),
      const _Template(0.52, 0.44, 0.40, 0.03, 2),
    ];

    for (var i = 0; i < math.min(mainItems.length, mainTemplates.length); i++) {
      placements.add(mainTemplates[i].place(mainItems[i], width, height));
    }

    final accessoryTemplates = <_Template>[
      const _Template(0.56, 0.70, 0.20, 0.05, 5),
      const _Template(0.78, 0.70, 0.20, -0.04, 5),
      const _Template(0.56, 0.84, 0.20, -0.02, 5),
      const _Template(0.78, 0.84, 0.20, 0.03, 5),
    ];

    for (
      var i = 0;
      i < math.min(accessories.length, accessoryTemplates.length);
      i++
    ) {
      placements.add(
        accessoryTemplates[i].place(accessories[i], width, height),
      );
    }

    return EditorialLayoutResult(
      mode: EditorialLayoutMode.accessoryHeavy,
      placements: _sorted(placements),
    );
  }

  static EditorialLayoutResult _generic({
    required List<StyleBoardItem> items,
    required double width,
    required double height,
  }) {
    // Spread up to 6 items across the full canvas in a loose editorial grid.
    final templates = <_Template>[
      const _Template(0.04, 0.06, 0.48, -0.03, 1),
      const _Template(0.50, 0.06, 0.46, 0.02, 1),
      const _Template(0.06, 0.42, 0.48, -0.02, 2),
      const _Template(0.52, 0.42, 0.42, 0.04, 3),
      const _Template(0.10, 0.74, 0.40, -0.03, 3),
      const _Template(0.56, 0.76, 0.34, 0.03, 4),
    ];

    final placements = <BoardItemPlacement>[];
    for (var i = 0; i < math.min(items.length, templates.length); i++) {
      placements.add(templates[i].place(items[i], width, height));
    }

    return EditorialLayoutResult(
      mode: EditorialLayoutMode.generic,
      placements: _sorted(placements),
    );
  }

  static List<BoardItemPlacement> _sorted(List<BoardItemPlacement> placements) {
    return <BoardItemPlacement>[...placements]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  /// Enforce safe zones on every placement:
  ///   top 5%, sides 6%, bottom 10%.
  /// Items whose bottom exceeds the safe-bottom boundary are moved UP; items
  /// past the top/side margins are clamped to the margin. Boxes are only shrunk
  /// when they are physically too large to fit the safe band (last resort) so
  /// nothing is ever clipped outside the board.
  static List<BoardItemPlacement> _applySafeZone(
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) {
    final safeTopY = height * 0.05;
    final safeBottomY = height * 0.90;
    final safeLeftX = width * 0.06;
    final safeRightX = width * 0.94;
    final maxW = safeRightX - safeLeftX;
    final maxH = safeBottomY - safeTopY;

    return placements.map((p) {
      double w = p.width;
      double h = p.height;
      // Last-resort shrink: never wider/taller than the safe band.
      if (w > maxW) w = maxW;
      if (h > maxH) h = maxH;

      double x = p.x;
      double y = p.y;
      if (y + h > safeBottomY) y = safeBottomY - h;
      if (y < safeTopY) y = safeTopY;
      if (x + w > safeRightX) x = safeRightX - w;
      if (x < safeLeftX) x = safeLeftX;

      if (w == p.width && h == p.height && x == p.x && y == p.y) return p;
      return p.copyWith(x: x, y: y, width: w, height: h);
    }).toList();
  }

  /// Final guard: replace any non-finite geometry with safe values and clamp
  /// everything inside the canvas. Protects Positioned/Stack from NaN/Infinity
  /// (which throw at layout) when upstream math misbehaves.
  static List<BoardItemPlacement> _sanitize(
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) {
    return placements.map((p) {
      double w = _finitePositive(p.width) ? p.width : width * 0.3;
      double h = _finitePositive(p.height) ? p.height : height * 0.3;
      w = w.clamp(1.0, width);
      h = h.clamp(1.0, height);
      double x = p.x.isFinite ? p.x : 0.0;
      double y = p.y.isFinite ? p.y : 0.0;
      x = x.clamp(0.0, math.max(0.0, width - w));
      y = y.clamp(0.0, math.max(0.0, height - h));
      final rot = p.rotation.isFinite ? p.rotation : 0.0;
      if (w == p.width &&
          h == p.height &&
          x == p.x &&
          y == p.y &&
          rot == p.rotation) {
        return p;
      }
      return p.copyWith(x: x, y: y, width: w, height: h, rotation: rot);
    }).toList();
  }

  static void _logLayout(
    EditorialLayoutMode mode,
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) {
    if (!kDebugMode) return;
    for (final p in placements) {
      final scale = (p.width / width);
      debugPrint(
        'AHVI_BOARD_LAYOUT mode=${mode.name} '
        'role=${p.item.role.name} '
        'scale=${scale.toStringAsFixed(3)} '
        'x=${(p.x / width).toStringAsFixed(3)} '
        'y=${(p.y / height).toStringAsFixed(3)} '
        'w=${(p.width / width).toStringAsFixed(3)} '
        'h=${(p.height / height).toStringAsFixed(3)} '
        'z=${p.zIndex}',
      );
    }
  }

  // --- Composition density pass -----------------------------------------
  static const double _covWMin = 0.78;
  static const double _covHMin = 0.74;
  static const double _covWTarget = 0.88;
  static const double _covHTarget = 0.86;
  static const double _compMaxScale = 1.18;

  /// Fractional width/height coverage of the union of [placements] over the
  /// canvas. Exposed for tests.
  static ({double width, double height}) unionCoverage(
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) {
    if (placements.isEmpty ||
        !_finitePositive(width) ||
        !_finitePositive(height)) {
      return (width: 0.0, height: 0.0);
    }
    final b = _unionBounds(placements);
    final uw = (b[2] - b[0]).clamp(0.0, width);
    final uh = (b[3] - b[1]).clamp(0.0, height);
    return (width: uw / width, height: uh / height);
  }

  static List<double> _unionBounds(List<BoardItemPlacement> placements) {
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in placements) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x + p.width);
      maxY = math.max(maxY, p.y + p.height);
    }
    return <double>[minX, minY, maxX, maxY];
  }

  /// Uniformly scale + recentre the whole composition ONLY when its union
  /// covers too little of the canvas (width < [_covWMin] OR height < [_covHMin]).
  /// Dense boards are returned untouched. Never enlarges past [_compMaxScale];
  /// downstream _applySafeZone + _sanitize keep everything in-bounds.
  static List<BoardItemPlacement> _normalizeComposition(
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) {
    if (placements.length < 2 ||
        !_finitePositive(width) ||
        !_finitePositive(height)) {
      return placements;
    }
    final cov = unionCoverage(placements, width, height);
    if (cov.width >= _covWMin && cov.height >= _covHMin) return placements;
    if (cov.width <= 0 || cov.height <= 0) return placements;

    final scale = math
        .min(_covWTarget / cov.width, _covHTarget / cov.height)
        .clamp(1.0, _compMaxScale);
    if (scale <= 1.0) return placements;

    final b = _unionBounds(placements);
    final cx = (b[0] + b[2]) / 2;
    final cy = (b[1] + b[3]) / 2;
    final scaled = placements
        .map(
          (p) => p.copyWith(
            x: cx + (p.x - cx) * scale,
            y: cy + (p.y - cy) * scale,
            width: p.width * scale,
            height: p.height * scale,
          ),
        )
        .toList();

    // Recentre the enlarged union on the canvas centre.
    final nb = _unionBounds(scaled);
    final dx = width / 2 - (nb[0] + nb[2]) / 2;
    final dy = height / 2 - (nb[1] + nb[3]) / 2;
    return scaled.map((p) => p.copyWith(x: p.x + dx, y: p.y + dy)).toList();
  }

  /// Test hook for the composition pass.
  @visibleForTesting
  static List<BoardItemPlacement> debugNormalizeComposition(
    List<BoardItemPlacement> placements,
    double width,
    double height,
  ) => _normalizeComposition(placements, width, height);

  static bool _finitePositive(double v) => v.isFinite && v > 0;
}

class _Template {
  final double x;
  final double y;
  final double w;
  final double rotation;
  final int z;

  const _Template(this.x, this.y, this.w, this.rotation, this.z);

  /// Height is derived from the item's role aspect ratio (not a fixed fraction)
  /// so the contained cutout fills the box; capped to the lower canvas band.
  BoardItemPlacement place(StyleBoardItem item, double width, double height) {
    final boxW = width * w;
    final boxH = EditorialBoardLayoutEngine._boxHeight(
      item.role,
      boxW,
      height * 0.46,
    );
    return BoardItemPlacement(
      item: item,
      x: width * x,
      y: height * y,
      width: boxW,
      height: boxH,
      rotation: rotation,
      zIndex: z,
    );
  }
}
