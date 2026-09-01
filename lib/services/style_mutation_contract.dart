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