// Unit tests for the Style Board visual-density patch (Option A+):
//   1. per-role visual zoom constants (EditorialBoardItem);
//   2. coverage-gated composition normalisation (EditorialBoardLayoutEngine).
// Widget-level proofs (footwear renders larger, no overflow, actions present)
// live in visual_board_85_phase1_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/editorial_board_layout_engine.dart';
import 'package:myapp/style_board/editorial_board_widgets.dart';

StyleBoardItem _item(BoardItemRole role) => StyleBoardItem(
  id: '${role.name}-1',
  name: role.name,
  imageUrl: 'https://example.test/${role.name}.png',
  category: role.name,
  role: role,
);

BoardItemPlacement _p(
  BoardItemRole role,
  double x,
  double y,
  double w,
  double h,
) => BoardItemPlacement(
  item: _item(role),
  x: x,
  y: y,
  width: w,
  height: h,
);

void main() {
  const w = 390.0;
  const h = 487.5; // 4:5-ish canvas

  group('role visual scale constants', () {
    test('every role stays within safe zoom bounds', () {
      double s(BoardItemRole r) => editorialVisualScaleForRole(r);
      expect(s(BoardItemRole.top), inInclusiveRange(1.12, 1.18));
      expect(s(BoardItemRole.bottom), inInclusiveRange(1.08, 1.14));
      expect(s(BoardItemRole.footwear), inInclusiveRange(1.30, 1.45));
      expect(s(BoardItemRole.dress), inInclusiveRange(1.08, 1.15));
      expect(s(BoardItemRole.outerwear), inInclusiveRange(1.08, 1.18));
      expect(s(BoardItemRole.accessory), inInclusiveRange(1.12, 1.25));
      expect(s(BoardItemRole.unknown), inInclusiveRange(1.0, 1.12));
      // Never shrink.
      for (final r in BoardItemRole.values) {
        expect(s(r), greaterThanOrEqualTo(1.0));
      }
    });

    test('footwear is zoomed more than the top (fixes tiny shoe)', () {
      expect(
        editorialVisualScaleForRole(BoardItemRole.footwear),
        greaterThan(editorialVisualScaleForRole(BoardItemRole.top)),
      );
    });

    test('bottoms anchor top-centre, others centre', () {
      expect(
        editorialAlignmentForRole(BoardItemRole.bottom),
        Alignment.topCenter,
      );
      for (final r in [
        BoardItemRole.top,
        BoardItemRole.dress,
        BoardItemRole.outerwear,
        BoardItemRole.footwear,
        BoardItemRole.accessory,
      ]) {
        expect(editorialAlignmentForRole(r), Alignment.center);
      }
    });
  });

  group('composition normalisation (coverage-gated)', () {
    test('a dense board is NOT enlarged again', () {
      // Union ≈ 0.85w × 0.90h → already above thresholds.
      final dense = <BoardItemPlacement>[
        _p(BoardItemRole.top, 0.05 * w, 0.05 * h, 0.50 * w, 0.40 * h),
        _p(BoardItemRole.bottom, 0.45 * w, 0.05 * h, 0.45 * w, 0.40 * h),
        _p(BoardItemRole.footwear, 0.05 * w, 0.55 * h, 0.50 * w, 0.40 * h),
      ];
      final before = EditorialBoardLayoutEngine.unionCoverage(dense, w, h);
      expect(before.width, greaterThanOrEqualTo(0.78));
      expect(before.height, greaterThanOrEqualTo(0.74));

      final out = EditorialBoardLayoutEngine.debugNormalizeComposition(
        dense,
        w,
        h,
      );
      final after = EditorialBoardLayoutEngine.unionCoverage(out, w, h);
      expect(after.width, closeTo(before.width, 1e-6));
      expect(after.height, closeTo(before.height, 1e-6));
    });

    test('a sparse fallback board is normalised (coverage increases)', () {
      final sparse = <BoardItemPlacement>[
        _p(BoardItemRole.top, 0.30 * w, 0.30 * h, 0.20 * w, 0.15 * h),
        _p(BoardItemRole.footwear, 0.50 * w, 0.45 * h, 0.20 * w, 0.15 * h),
      ];
      final before = EditorialBoardLayoutEngine.unionCoverage(sparse, w, h);
      expect(before.width, lessThan(0.78));

      final out = EditorialBoardLayoutEngine.debugNormalizeComposition(
        sparse,
        w,
        h,
      );
      final after = EditorialBoardLayoutEngine.unionCoverage(out, w, h);
      expect(after.width, greaterThan(before.width));
      expect(after.height, greaterThan(before.height));
      // Never past the target coverage (bounded by max composition scale).
      expect(after.width, lessThanOrEqualTo(0.90));
      expect(after.height, lessThanOrEqualTo(0.90));
    });

    test('normalised rectangles stay finite and inside the canvas', () {
      final sparse = <BoardItemPlacement>[
        _p(BoardItemRole.top, 0.30 * w, 0.30 * h, 0.20 * w, 0.15 * h),
        _p(BoardItemRole.footwear, 0.50 * w, 0.45 * h, 0.20 * w, 0.15 * h),
      ];
      final out = EditorialBoardLayoutEngine.debugNormalizeComposition(
        sparse,
        w,
        h,
      );
      for (final p in out) {
        expect(p.x.isFinite && p.y.isFinite, isTrue);
        expect(p.width.isFinite && p.height.isFinite, isTrue);
        expect(p.width, greaterThan(0));
        expect(p.height, greaterThan(0));
        // Recentred composition may sit slightly proud before the downstream
        // _applySafeZone/_sanitize pass; assert it never explodes off-canvas.
        expect(p.x, greaterThanOrEqualTo(-1.0));
        expect(p.y, greaterThanOrEqualTo(-1.0));
        expect(p.x + p.width, lessThanOrEqualTo(w + 1.0));
        expect(p.y + p.height, lessThanOrEqualTo(h + 1.0));
      }
    });

    test('single-item / empty boards are left untouched', () {
      expect(
        EditorialBoardLayoutEngine.debugNormalizeComposition(
          const <BoardItemPlacement>[],
          w,
          h,
        ),
        isEmpty,
      );
      final one = <BoardItemPlacement>[
        _p(BoardItemRole.dress, 0.3 * w, 0.3 * h, 0.2 * w, 0.2 * h),
      ];
      final out = EditorialBoardLayoutEngine.debugNormalizeComposition(
        one,
        w,
        h,
      );
      expect(out.first.x, one.first.x);
      expect(out.first.width, one.first.width);
    });
  });
}
