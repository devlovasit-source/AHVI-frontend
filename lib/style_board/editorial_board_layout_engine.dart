import 'dart:math' as math;

import 'board_models.dart';

/// Position information for a board item in the layout
class BoardItemPosition {
  final double top;
  final double left;
  final double width;
  final double height;
  final double rotation; // In radians
  final int zIndex;
  
  BoardItemPosition({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    required this.zIndex,
  });
}

class EditorialBoardLayoutEngine {
  static EditorialLayoutResult resolve(
    StyleBoardData board, {
    required double width,
    required double height,
  }) {
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

    if (dress != null) {
      return _dressFocused(
        dress: dress,
        footwear: footwear,
        outerwear: outerwear,
        accessories: accessories,
        width: width,
        height: height,
      );
    }

    if (top != null && bottom != null && footwear != null) {
      if (accessories.length <= 2) {
        return _classicThreePlusAccessory(
          top: top,
          bottom: bottom,
          footwear: footwear,
          outerwear: outerwear,
          accessories: accessories,
          width: width,
          height: height,
        );
      }

      return _accessoryHeavy(
        mainItems: <StyleBoardItem>[
          if (outerwear != null) outerwear,
          top,
          bottom,
          footwear,
        ],
        accessories: accessories,
        width: width,
        height: height,
      );
    }

    return _generic(items: board.items, width: width, height: height);
  }

  /// Convenience method that converts BoardItemPlacement to BoardItemPosition format
  /// Useful for UI frameworks that expect top/left coordinates instead of x/y
  static List<BoardItemPosition> calculateLayout(
    List<StyleBoardItem> items, {
    required double width,
    required double height,
  }) {
    final board = StyleBoardData(items: items);
    final result = resolve(board, width: width, height: height);
    
    return result.placements
        .map((placement) => BoardItemPosition(
          top: placement.y,
          left: placement.x,
          width: placement.width,
          height: placement.height,
          rotation: placement.rotation,
          zIndex: placement.zIndex,
        ))
        .toList();
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

  static EditorialLayoutResult _classicThreePlusAccessory({
    required StyleBoardItem top,
    required StyleBoardItem bottom,
    required StyleBoardItem footwear,
    required StyleBoardItem? outerwear,
    required List<StyleBoardItem> accessories,
    required double width,
    required double height,
  }) {
    final placements = <BoardItemPlacement>[
      BoardItemPlacement(
        item: top,
        x: width * 0.02,
        y: height * 0.11,
        width: width * 0.45,
        height: height * 0.44,
        rotation: -0.035,
        zIndex: 2,
      ),
      BoardItemPlacement(
        item: bottom,
        x: width * 0.45,
        y: height * 0.03,
        width: width * 0.51,
        height: height * 0.70,
        rotation: 0.015,
        zIndex: 1,
      ),
      BoardItemPlacement(
        item: footwear,
        x: width * 0.02,
        y: height * 0.58,
        width: width * 0.52,
        height: height * 0.32,
        rotation: -0.03,
        zIndex: 3,
      ),
    ];

    if (outerwear != null) {
      placements.add(
        BoardItemPlacement(
          item: outerwear,
          x: width * 0.02,
          y: height * 0.03,
          width: width * 0.42,
          height: height * 0.48,
          rotation: 0.03,
          zIndex: 0,
        ),
      );
    }

    for (var i = 0; i < math.min(accessories.length, 2); i++) {
      placements.add(
        BoardItemPlacement(
          item: accessories[i],
          x: width * (i == 0 ? 0.68 : 0.55),
          y: height * (i == 0 ? 0.68 : 0.80),
          width: width * 0.23,
          height: height * 0.18,
          rotation: i == 0 ? 0.06 : -0.04,
          zIndex: 4,
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
    final placements = <BoardItemPlacement>[
      BoardItemPlacement(
        item: dress,
        x: width * 0.18,
        y: height * 0.04,
        width: width * 0.60,
        height: height * 0.70,
        rotation: 0.01,
        zIndex: 2,
      ),
    ];

    if (outerwear != null) {
      placements.add(
        BoardItemPlacement(
          item: outerwear,
          x: width * 0.02,
          y: height * 0.10,
          width: width * 0.36,
          height: height * 0.48,
          rotation: -0.04,
          zIndex: 1,
        ),
      );
    }

    if (footwear != null) {
      placements.add(
        BoardItemPlacement(
          item: footwear,
          x: width * 0.06,
          y: height * 0.68,
          width: width * 0.42,
          height: height * 0.25,
          rotation: -0.02,
          zIndex: 3,
        ),
      );
    }

    for (var i = 0; i < math.min(accessories.length, 3); i++) {
      placements.add(
        BoardItemPlacement(
          item: accessories[i],
          x: width * (0.68 - (i % 2) * 0.16),
          y: height * (0.68 + (i ~/ 2) * 0.14),
          width: width * 0.20,
          height: height * 0.16,
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
    final mainTemplates = <_Template>[
      const _Template(0.03, 0.10, 0.38, 0.36, -0.03, 2),
      const _Template(0.44, 0.05, 0.48, 0.58, 0.02, 1),
      const _Template(0.05, 0.56, 0.46, 0.26, -0.02, 3),
      const _Template(0.54, 0.48, 0.34, 0.30, 0.03, 2),
    ];

    for (var i = 0; i < math.min(mainItems.length, mainTemplates.length); i++) {
      placements.add(mainTemplates[i].place(mainItems[i], width, height));
    }

    final accessoryTemplates = <_Template>[
      const _Template(0.58, 0.68, 0.18, 0.14, 0.05, 5),
      const _Template(0.77, 0.68, 0.18, 0.14, -0.04, 5),
      const _Template(0.58, 0.82, 0.18, 0.14, -0.02, 5),
      const _Template(0.77, 0.82, 0.18, 0.14, 0.03, 5),
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
    final templates = <_Template>[
      const _Template(0.05, 0.08, 0.42, 0.38, -0.03, 1),
      const _Template(0.48, 0.08, 0.42, 0.45, 0.02, 1),
      const _Template(0.10, 0.53, 0.46, 0.30, -0.02, 2),
      const _Template(0.58, 0.55, 0.28, 0.24, 0.04, 3),
      const _Template(0.63, 0.78, 0.22, 0.16, -0.03, 3),
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
}

class _Template {
  final double x;
  final double y;
  final double w;
  final double h;
  final double rotation;
  final int z;

  const _Template(this.x, this.y, this.w, this.h, this.rotation, this.z);

  BoardItemPlacement place(StyleBoardItem item, double width, double height) {
    return BoardItemPlacement(
      item: item,
      x: width * x,
      y: height * y,
      width: width * w,
      height: height * h,
      rotation: rotation,
      zIndex: z,
    );
  }
}
