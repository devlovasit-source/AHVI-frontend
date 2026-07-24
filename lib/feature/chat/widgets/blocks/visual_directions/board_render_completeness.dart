import 'package:myapp/style_board/board_models.dart';

/// Result of validating the FINAL rendered items of a board.
class BoardRenderCompleteness {
  final bool complete;
  final List<String> roles;
  final String structure; // 'separates' | 'one_piece' | ''
  final String reason; // '' when complete

  const BoardRenderCompleteness({
    required this.complete,
    required this.roles,
    required this.structure,
    required this.reason,
  });
}

bool _actsAsPrimaryOuterwear(StyleBoardItem item) {
  bool truthy(Object? v) =>
      v == true || v?.toString().toLowerCase() == 'true';
  final raw = item.raw;
  return truthy(raw['primary_outerwear']) ||
      truthy(raw['primaryOuterwear']) ||
      truthy(raw['acts_as_top']) ||
      truthy(raw['actsAsTop']) ||
      truthy(raw['is_primary_upper']);
}

/// Validate the final rendered items of a board.
///
/// Valid core structures:
///   Separates:  (top OR primary-outerwear) + bottom + footwear
///   One-piece:  dress (covers jumpsuit / ethnic one-piece) + footwear
///
/// Rules: accessories never satisfy a core role; an ordinary jacket does not
/// stand in for a missing top unless it is explicitly the primary upper
/// garment; items without a renderable image are ignored before validation.
BoardRenderCompleteness evaluateRenderCompleteness(List<StyleBoardItem> items) {
  final rendered =
      items.where((i) => i.displayImageUrl.trim().isNotEmpty).toList();
  final roles = rendered.map((i) => i.role).toList();
  final roleNames = roles.map((r) => r.name).toList();
  bool has(BoardItemRole r) => roles.contains(r);
  final primaryOuter = rendered.any(
    (i) => i.role == BoardItemRole.outerwear && _actsAsPrimaryOuterwear(i),
  );

  if (has(BoardItemRole.dress) && has(BoardItemRole.footwear)) {
    return BoardRenderCompleteness(
      complete: true,
      roles: roleNames,
      structure: 'one_piece',
      reason: '',
    );
  }

  final upperOk = has(BoardItemRole.top) || primaryOuter;
  if (upperOk && has(BoardItemRole.bottom) && has(BoardItemRole.footwear)) {
    return BoardRenderCompleteness(
      complete: true,
      roles: roleNames,
      structure: 'separates',
      reason: '',
    );
  }

  final missing = <String>[];
  if (has(BoardItemRole.dress)) {
    if (!has(BoardItemRole.footwear)) missing.add('footwear');
  } else {
    if (!upperOk) missing.add('top');
    if (!has(BoardItemRole.bottom)) missing.add('bottom');
    if (!has(BoardItemRole.footwear)) missing.add('footwear');
  }
  return BoardRenderCompleteness(
    complete: false,
    roles: roleNames,
    structure: '',
    reason:
        missing.isEmpty ? 'no_core_structure' : 'missing_${missing.join("_")}',
  );
}
