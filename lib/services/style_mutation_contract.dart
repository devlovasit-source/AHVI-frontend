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
    'title',
    'board_title',
    'boardTitle',
    'selected_archetype',
    'selectedArchetype',
    'archetype',
    'style_archetype',
    'style_strategy',
    'short_note',
    'shortNote',
    'why_it_works',
    'whyItWorks',
    'why_this_works',
    'explanation',
    'reason',
    'description',
    'styling_tip',
    'stylingTip',
    'style_tip',
    'style_note',
    'styleNote',
    'styling_note',
    'story',
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
  'styling_tip',
  'stylingTip',
  'style_tip',
  'style_note',
  'styleNote',
  'styling_note',
];

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

bool _hasFreshNarrative(
  Map<String, dynamic> board,
  List<String> aliases, {
  String? storyField,
}) {
  if (aliases.any((key) => !_isBlankNarrativeValue(key, board[key]))) {
    return true;
  }
  final story = board['story'];
  if (storyField != null && story is Map) {
    final value = story[storyField];
    return value is String && value.trim().isNotEmpty;
  }
  return false;
}

bool _hasFreshTitle(
  Map<String, dynamic> board,
  Map<String, dynamic> previousBoard,
) {
  const explicitAliases = [
    'title',
    'board_title',
    'boardTitle',
    'selected_archetype',
    'selectedArchetype',
  ];
  if (_hasFreshNarrative(board, explicitAliases, storyField: 'headline')) {
    return true;
  }
  // Keep the curated title when a mutation only echoes a generic archetype.
  final previousHasExplicitTitle = _hasFreshNarrative(
    previousBoard,
    explicitAliases,
    storyField: 'headline',
  );
  return !previousHasExplicitTitle &&
      _hasFreshNarrative(board, const ['archetype', 'style_archetype', 'style_strategy']);
}

/// Retains narrative fields omitted by a board mutation without allowing a
/// stale high-priority alias to shadow fresh copy under another alias.
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
  final previousStory = previousBoard['story'];

  return boards.map((board) {
    final merged = Map<String, dynamic>.from(board);
    final boardId = (merged['board_id'] ?? merged['boardId'] ?? '')
        .toString()
        .trim();
    final sameBoard =
        singleBoardResponse || (boardId.isNotEmpty && boardId == previousId);
    if (!sameBoard) return merged;

    final groups = <({List<String> aliases, String? storyField})>[
      (aliases: _kTitleAliases, storyField: 'headline'),
      (aliases: _kWhyAliases, storyField: 'why'),
      (aliases: _kTipAliases, storyField: 'tip'),
    ];
    for (final group in groups) {
      final hasFresh = group.storyField == 'headline'
          ? _hasFreshTitle(merged, previousBoard)
          : _hasFreshNarrative(
              merged,
              group.aliases,
              storyField: group.storyField,
            );
      if (hasFresh) {
        continue;
      }
      for (final key in group.aliases) {
        if (_isBlankNarrativeValue(key, merged[key]) &&
            previousBoard[key] != null) {
          merged[key] = previousBoard[key];
        }
      }
      if (previousStory is Map) {
        final storyField = group.storyField!;
        final story = merged['story'] is Map
            ? Map<String, dynamic>.from(merged['story'] as Map)
            : <String, dynamic>{};
        final storyValue = previousStory[storyField];
        if (storyValue is String && storyValue.trim().isNotEmpty) {
          final currentStoryValue = story[storyField];
          if (currentStoryValue == null ||
              (currentStoryValue is String &&
                  currentStoryValue.trim().isEmpty)) {
            story[storyField] = storyValue;
            merged['story'] = story;
          }
        }
      }
    }
    return merged;
  }).toList(growable: false);
}
