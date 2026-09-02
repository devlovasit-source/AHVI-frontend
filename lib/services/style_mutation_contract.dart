/// Shared frontend contract for conversational mutations of an existing board.
/// This only selects the established legacy mutation endpoint; semantic intent
/// and replacement selection remain backend responsibilities.
bool isStyleBoardMutationPrompt(String value) {
  final text = value.toLowerCase().trim();
  if (text.isEmpty) return false;
  const roleTerms = [
    'shoe',
    'shoes',
    'footwear',
    'sneaker',
    'sneakers',
    'loafer',
    'loafers',
    'boot',
    'boots',
    'jacket',
    'blazer',
    'outerwear',
    'shirt',
    'top',
    'bottom',
    'trouser',
    'pants',
    'dress',
    'accessory',
    'accessories',
  ];
  if (!roleTerms.any(text.contains)) return false;
  return RegExp(
        r'\b(replace|change|swap|switch|make|give me)\b',
      ).hasMatch(text) ||
      text.contains('instead');
}

Map<String, dynamic>? styleMutationStateFromBoard(
  Map<String, dynamic> board, {
  Map<String, dynamic>? responseState,
}) {
  final state = <String, dynamic>{...?responseState, ...board};
  final boardId = (state['board_id'] ?? state['boardId'] ?? '')
      .toString()
      .trim();
  final revision = state['revision'];
  final rawItems = state['board_items'] ?? state['items'];
  if (boardId.isEmpty ||
      revision is! num ||
      revision < 1 ||
      rawItems is! List ||
      rawItems.isEmpty) {
    return null;
  }
  final items = rawItems
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
  if (items.isEmpty) return null;
  final result = <String, dynamic>{
    'board_id': boardId,
    'revision': revision,
    'board_items': items,
    'items': items,
  };
  for (final key in [
    'source_policy',
    'source_mode',
    'interaction_mode',
    'scenario',
    'occasion',
    'date_context',
    'daypart',
    'activity',
    'activity_type',
    'venue',
    'positive_constraints',
    'negative_constraints',
    'active_constraints',
    'semantic_constraints',
    'style_adjustments',
    'resolved_context',
    'locked_item_ids',
    'protected_item_ids',
    'anchor_item_ids',
    'board_content_hash',
    // Narrative/title fields. A board mutation (e.g. "change footwear")
    // only swaps the requested role's item(s); it must not silently drop
    // the board's title, rationale, or styling tip. These are round-tripped
    // through the mutation state so the legacy mutation endpoint — which
    // treats this state as the board it echoes back — has them to return,
    // and so the card renderer still has them if it doesn't.
    'title',
    'board_title',
    'boardTitle',
    'selected_archetype',
    'selectedArchetype',
    'archetype',
    'style_archetype',
    'style_strategy',
    // "Why it works" — every fallback key the card renderer checks.
    'short_note',
    'shortNote',
    'why_it_works',
    'whyItWorks',
    'why_this_works',
    'explanation',
    'reason',
    'description',
    // "Styling tip" — every fallback key the card renderer checks.
    'styling_tip',
    'stylingTip',
    'style_tip',
    'style_note',
    'styleNote',
    'styling_note',
  ]) {
    if (state[key] != null) result[key] = state[key];
  }
  if (result['source_policy'] == null && result['source_mode'] != null) {
    result['source_policy'] = result['source_mode'];
  }
  return result;
}

/// Resolves a board collection only when ownership is explicit or unambiguous.
/// A multi-board response without an active board must not silently select the
/// first historical board.
Map<String, dynamic>? styleMutationStateFromBoards(
  List<Map<String, dynamic>> boards, {
  Map<String, dynamic>? responseState,
  String? activeBoardId,
}) {
  if (boards.isEmpty) return null;
  final requestedId = activeBoardId?.trim() ?? '';
  final board = requestedId.isNotEmpty
      ? boards.where((candidate) {
          return (candidate['board_id'] ?? candidate['boardId'] ?? '')
                  .toString()
                  .trim() ==
              requestedId;
        }).firstOrNull
      : boards.length == 1
      ? boards.single
      : null;
  if (board == null) return null;
  final responseBoardId = (responseState?['board_id'] ??
          responseState?['boardId'] ??
          '')
      .toString()
      .trim();
  final boardId = (board['board_id'] ?? board['boardId'] ?? '')
      .toString()
      .trim();
  final stateForBoard = responseBoardId.isEmpty || responseBoardId == boardId
      ? responseState
      : null;
  return styleMutationStateFromBoard(board, responseState: stateForBoard);
}
/// Semantic groups of aliases the outfit board card falls back through, in
/// the same precedence order the card renderer checks them. Grouped (rather
/// than one flat list) so [retainBoardNarrative] can decide per *topic* —
/// title, "why it works", "styling tip" — whether the mutation response
/// already has fresh content, instead of deciding per individual key.
const _kTitleAliases = [
  'title',
  'board_title',
  'boardTitle',
  'selected_archetype',
  'selectedArchetype',
  'archetype',
  'style_archetype',
  'style_strategy',
];

const _kWhyAliases = [
  // "Why it works" — every fallback key the card renderer checks.
  'short_note',
  'shortNote',
  'why_it_works',
  'whyItWorks',
  'why_this_works',
  'explanation',
  'reason',
  'description',
];

const _kTipAliases = [
  // "Styling tip" — every fallback key the card renderer checks.
  'styling_tip',
  'stylingTip',
  'style_tip',
  'style_note',
  'styleNote',
  'styling_note',
];

const _kNarrativeGroups = [_kTitleAliases, _kWhyAliases, _kTipAliases];

/// `style_strategy` is a nested strategy Map, not a plain title string — a
/// mutation response can carry `style_strategy: {}` (or one with unrelated
/// fields) purely as scaffolding, with no actual replacement title inside
/// it. Treating any non-null Map there as "fresh" would block backfill for
/// the whole title group and drop the previous board's real title, so it
/// only counts as fresh when it actually carries one of these fields.
const _kStyleStrategyTitleFields = [
  'archetype',
  'archetype_name',
  'direction_title',
  'directionTitle',
  'direction',
];

bool _isBlankNarrativeValue(String key, dynamic value) {
  if (key == 'style_strategy' && value is Map) {
    return !value.keys.any((field) {
      if (!_kStyleStrategyTitleFields.contains(field)) return false;
      final fieldValue = value[field];
      return fieldValue is String && fieldValue.trim().isNotEmpty;
    });
  }
  return value == null || (value is String && value.trim().isEmpty);
}

/// A board mutation (e.g. "change footwear") only swaps the requested
/// role's item(s). The legacy mutation endpoint can return a board that
/// omits the title/rationale/styling tip it was never asked to change —
/// backfill those from the board being mutated so the card doesn't fall
/// back to a generic title and blank "why it works"/"styling tip".
///
/// Backfill runs per semantic group ([_kTitleAliases] / [_kWhyAliases] /
/// [_kTipAliases]), not per individual alias key: if the response already
/// carries a fresh (non-blank) value under *any* alias in a group, the
/// whole group is left untouched. A per-key backfill could otherwise
/// insert a stale value under a higher-precedence alias (e.g. an old
/// `why_it_works`) that shadows a fresh value the response actually sent
/// under a lower-precedence alias (e.g. a new `explanation`), once the
/// card resolves which alias wins.
///
/// NOTE: the backend does not reliably echo back a stable board_id across
/// a mutation turn (it may mint a fresh id on every response), so id
/// matching can't be the primary signal here. This is only called from a
/// single-active-board mutation flow (the ambiguous-board case is already
/// intercepted earlier and asks the user which board to update), so when
/// there is exactly one board in the response it is safe to assume it is
/// the board being mutated regardless of what id it carries. With more
/// than one board in the response, an id match is required — an empty or
/// missing board_id on a multi-board response must NOT be treated as a
/// match, or every untagged board in that response would silently inherit
/// the same previous board's narrative.
List<Map<String, dynamic>> retainBoardNarrative(
  List<Map<String, dynamic>> boards,
  Map<String, dynamic>? previousBoard,
) {
  if (previousBoard == null || boards.isEmpty) return boards;
  final singleBoardResponse = boards.length == 1;
  final previousId =
      (previousBoard['board_id'] ?? previousBoard['boardId'] ?? '')
          .toString()
          .trim();
  return boards.map((board) {
    final merged = Map<String, dynamic>.from(board);
    final boardId = (merged['board_id'] ?? merged['boardId'] ?? '')
        .toString()
        .trim();
    final sameBoard =
        singleBoardResponse || (boardId.isNotEmpty && boardId == previousId);
    if (!sameBoard) return merged;
    for (final group in _kNarrativeGroups) {
      final hasFreshValue = group.any(
        (key) => !_isBlankNarrativeValue(key, merged[key]),
      );
      if (hasFreshValue) continue;
      for (final key in group) {
        if (_isBlankNarrativeValue(key, merged[key]) &&
            previousBoard[key] != null) {
          merged[key] = previousBoard[key];
        }
      }
    }
    return merged;
  }).toList(growable: false);
}