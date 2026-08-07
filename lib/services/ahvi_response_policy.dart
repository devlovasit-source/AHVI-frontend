import 'package:flutter/foundation.dart';

const Set<String> ahviBoardAuthorizedRoutes = {
  'visual_inspiration',
  'wardrobe_style',
  // P0 canonical response_mode alias for wardrobe_style.
  'wardrobe_recommendation',
  'style_this',
  'build_outfit',
};

const Set<String> ahviBoardSuppressedRoutes = {
  'style_advice',
  'style_pairing',
  'missing_pieces',
  'supportive_conversation',
  'medical_urgent',
  'diagnosis_request',
  'general_chat',
  'clarification',
  'error',
  // P0 canonical response_mode values that must never render Style boards.
  'text_only',
  'calendar_navigation',
  'calendar_action',
  'planner_action',
};

class AhviBoardCollection {
  final String path;
  final List<Map<String, dynamic>> boards;
  final int rawCount;
  final int dedupDroppedCount;

  const AhviBoardCollection({
    required this.path,
    required this.boards,
    this.rawCount = 0,
    this.dedupDroppedCount = 0,
  });

  bool get isValid => boards.isNotEmpty;
}

class AhviResponseControls {
  final bool save;
  final bool share;
  final bool like;
  final bool dislike;
  final bool lock;
  final bool shuffle;
  final bool undo;
  final bool buildOutfit;

  const AhviResponseControls({
    required this.save,
    required this.share,
    required this.like,
    required this.dislike,
    required this.lock,
    required this.shuffle,
    required this.undo,
    required this.buildOutfit,
  });
}

class AhviResponsePolicy {
  final String route;
  final String mode;
  final String intent;
  final String action;
  final String boardPolicy;
  final String interactionMode;
  final String safetyLevel;
  final Map<String, dynamic> conversationSignals;
  final String responseVerbosity;
  final String responseComplexity;
  final bool? _backendCanLock;
  final bool? _backendCanShuffle;
  final bool? _backendAnchorLocked;

  const AhviResponsePolicy({
    required this.route,
    required this.mode,
    required this.intent,
    required this.action,
    required this.boardPolicy,
    required this.interactionMode,
    required this.safetyLevel,
    required this.conversationSignals,
    required this.responseVerbosity,
    required this.responseComplexity,
    required bool? backendCanLock,
    required bool? backendCanShuffle,
    required bool? backendAnchorLocked,
  }) : _backendCanLock = backendCanLock,
       _backendCanShuffle = backendCanShuffle,
       _backendAnchorLocked = backendAnchorLocked;

  factory AhviResponsePolicy.fromResponse(Map<String, dynamic> response) {
    final data = _asMap(response['data']);
    final metadata = _asMap(response['metadata'] ?? response['meta']);
    final routing = _asMap(response['routing']);
    final sources = [response, data, routing, metadata];

    dynamic value(String key) {
      for (final source in sources) {
        if (source.containsKey(key) && source[key] != null) return source[key];
      }
      return null;
    }

    final signals = _asMap(value('conversation_signals'));
    final policy = value('board_policy');
    // P0: canonical `response_mode` wins over everything. `route` remains
    // navigation-only; `mode` and `intent` are legacy fallbacks.
    var resolvedRoute = _normalize(value('response_mode'));
    if (resolvedRoute.isEmpty ||
        (!ahviBoardAuthorizedRoutes.contains(resolvedRoute) &&
            !ahviBoardSuppressedRoutes.contains(resolvedRoute))) {
      resolvedRoute = _normalize(value('route'));
    }
    if (resolvedRoute.isEmpty ||
        (!ahviBoardAuthorizedRoutes.contains(resolvedRoute) &&
            !ahviBoardSuppressedRoutes.contains(resolvedRoute))) {
      resolvedRoute = '';
      for (final candidate in [value('mode'), value('intent')]) {
        final normalized = _normalize(candidate);
        if (ahviBoardAuthorizedRoutes.contains(normalized) ||
            ahviBoardSuppressedRoutes.contains(normalized)) {
          resolvedRoute = normalized;
          break;
        }
      }
    }
    return AhviResponsePolicy(
      route: resolvedRoute,
      mode: _normalize(value('mode')),
      intent: _normalize(value('intent')),
      action: _normalize(value('action')),
      boardPolicy: _policyName(policy),
      interactionMode: _normalize(value('interaction_mode')),
      safetyLevel: _normalize(value('safety_level')),
      conversationSignals: signals,
      responseVerbosity: _normalize(value('response_verbosity')),
      responseComplexity: _normalize(value('response_complexity')),
      backendCanLock: _boolValue(value('can_lock')),
      backendCanShuffle: _boolValue(value('can_shuffle')),
      backendAnchorLocked: _boolValue(value('anchor_locked')),
    );
  }

  bool get hasCanonicalRoute => route.isNotEmpty;

  bool get isSafetySensitive =>
      route == 'medical_urgent' ||
      route == 'diagnosis_request' ||
      safetyLevel == 'urgent' ||
      safetyLevel == 'high' ||
      _truthy(conversationSignals['safety_sensitive']);

  bool get textPrimary =>
      isSafetySensitive ||
      route == 'text_only' ||
      route == 'style_advice' ||
      route == 'style_pairing' ||
      route == 'missing_pieces' ||
      route == 'supportive_conversation' ||
      route == 'general_chat' ||
      route == 'clarification' ||
      route == 'error';

  bool get technicalMetadataHidden => true;

  bool get styleCtasAllowed =>
      !isSafetySensitive && route != 'diagnosis_request';

  bool get boardRouteAuthorized =>
      (ahviBoardAuthorizedRoutes.contains(route) ||
          (route == 'style_advice' &&
              boardPolicy.isNotEmpty &&
              _boardPolicyAllows)) &&
      _boardPolicyAllows;

  bool hasValidatedAnchorIn(Map<String, dynamic> response) {
    final data = _asMap(response['data']);
    final anchor =
        response['anchor_item'] ??
        response['anchorItem'] ??
        data['anchor_item'] ??
        data['anchorItem'];
    final anchorMap = _asMap(anchor);
    final anchorId = _firstText([
      anchorMap['item_id'],
      anchorMap['id'],
      anchorMap[r'$id'],
      response['anchor_item_id'],
      data['anchor_item_id'],
    ]);
    final locked = _boolValue(
      response['anchor_locked'] ?? data['anchor_locked'],
    );
    return anchorId.isNotEmpty && (locked != false);
  }

  bool get mayRenderBoards => boardRouteAuthorized;

  bool canRenderBoards(Map<String, dynamic> response) =>
      mayRenderBoards &&
      (route != 'style_this' || hasValidatedAnchorIn(response));

  AhviResponseControls controlsFor(Map<String, dynamic> response) {
    final anchorValid = route != 'style_this' || hasValidatedAnchorIn(response);
    final canSave = mayRenderBoards && anchorValid;
    final canShare = mayRenderBoards && anchorValid;
    final isRecommendation =
        route == 'visual_inspiration' ||
        route == 'wardrobe_style' ||
        (route == 'style_advice' && boardRouteAuthorized);
    final isStyleThis = route == 'style_this';
    final isBuildOutfit = route == 'build_outfit';
    final isMutableBoard = isStyleThis || isBuildOutfit;
    return AhviResponseControls(
      save: canSave,
      share: canShare,
      like: isRecommendation,
      dislike: isRecommendation,
      lock:
          isMutableBoard &&
          (isBuildOutfit || (_backendCanLock ?? true)) &&
          anchorValid,
      shuffle:
          isMutableBoard &&
          (isBuildOutfit || (_backendCanShuffle ?? true)) &&
          anchorValid,
      undo: isMutableBoard && anchorValid,
      buildOutfit: isBuildOutfit,
    );
  }

  Map<String, dynamic> decorateBoard(
    Map<String, dynamic> board,
    Map<String, dynamic> response,
  ) {
    final controls = controlsFor(response);
    final data = _asMap(response['data']);
    final sourcePolicy = _firstText([
      response['source_policy'],
      data['source_policy'],
    ]);
    return {
      ...board,
      if (!board.containsKey('source_policy') && sourcePolicy.isNotEmpty)
        'source_policy': sourcePolicy,
      if ((board['interaction_mode'] ?? board['interactionMode']) == null &&
          interactionMode.isNotEmpty)
        'interaction_mode': interactionMode,
      if ((board['interaction_mode'] ?? board['interactionMode']) == null &&
          route == 'style_this')
        'interaction_mode': 'style_this',
      if ((board['interaction_mode'] ?? board['interactionMode']) == null &&
          route == 'build_outfit')
        'interaction_mode': 'build_outfit',
      if (!board.containsKey('can_lock')) 'can_lock': controls.lock,
      if (!board.containsKey('can_shuffle')) 'can_shuffle': controls.shuffle,
      if (!board.containsKey('anchor_locked'))
        'anchor_locked':
            _backendAnchorLocked ??
            (route == 'style_this' && hasValidatedAnchorIn(response)),
    };
  }

  AhviBoardCollection boardCollection(Map<String, dynamic> response) {
    if (!canRenderBoards(response)) {
      final predicates = <String>[];
      if (!hasCanonicalRoute) predicates.add('route_missing');
      if (!boardRouteAuthorized) predicates.add('board_route_unauthorized');
      if (!_boardPolicyAllows) predicates.add('board_policy_rejected');
      if (isSafetySensitive) predicates.add('safety_sensitive');
      if (route == 'style_this' && !hasValidatedAnchorIn(response)) {
        predicates.add('anchor_invalid');
      }
      debugPrint(
        'AHVI_LIVE_STYLE_REJECTION '
        'source_file=ahvi_response_policy.dart function=boardCollection '
        'resolved_route=${route.isEmpty ? 'none' : route} '
        'board_policy=${boardPolicy.isEmpty ? 'none' : boardPolicy} '
        'selected_alias=none raw_count=0 accepted_count=0 rejected_count=0 '
        'rejection_predicates=${predicates.isEmpty ? 'unknown' : predicates.join(',')} '
        'final_renderer=none final_rendered_count=0',
      );
      return const AhviBoardCollection(path: '', boards: []);
    }
    final data = _asMap(response['data']);
    final candidates = <({String path, dynamic value})>[
      (path: 'data.rendered_boards', value: data['rendered_boards']),
      (path: 'rendered_boards', value: response['rendered_boards']),
      (path: 'style_boards', value: response['style_boards']),
      (path: 'data.style_boards', value: data['style_boards']),
      (path: 'data.outfits', value: data['outfits']),
      (path: 'outfits', value: response['outfits']),
      (path: 'data.visual_directions', value: data['visual_directions']),
      (path: 'visual_directions', value: response['visual_directions']),
      (path: 'data.style_directions', value: data['style_directions']),
      (path: 'style_directions', value: response['style_directions']),
      (path: 'data.outfit', value: data['outfit']),
      (path: 'outfit', value: response['outfit']),
      // Cards remain a compatibility fallback, never the preferred board
      // renderer when a canonical board alias is available.
      (path: 'cards', value: response['cards']),
      (path: 'data.cards', value: data['cards']),
    ];
    final ranked =
        <
          ({
            String path,
            List<Map<String, dynamic>> boards,
            int rawCount,
            int dedupDroppedCount,
            int score,
            int order,
          })
        >[];
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final rawBoards = _asList(candidate.value);
      final normalized = _normalizeBoards(rawBoards);
      if (normalized.boards.isEmpty) continue;
      ranked.add((
        path: candidate.path,
        boards: normalized.boards
            .map((board) => decorateBoard(board, response))
            .toList(growable: false),
        rawCount: rawBoards.length,
        dedupDroppedCount: normalized.dedupDroppedCount,
        score: _boardCollectionScore(normalized.boards),
        order: index,
      ));
    }
    if (ranked.isNotEmpty) {
      ranked.sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.order.compareTo(b.order) : score;
      });
      final selected = ranked.first;
      final firstBoard = selected.boards.isEmpty
          ? const <String, dynamic>{}
          : selected.boards.first;
      final firstItems = _asList(
        firstBoard['board_items'] ?? firstBoard['items'],
      );
      final firstItem = firstItems.isEmpty
          ? const <String, dynamic>{}
          : firstItems.first;
      debugPrint(
        'AHVI_LIVE_STYLE_NORMALIZER '
        'source_file=ahvi_response_policy.dart function=boardCollection '
        'resolved_route=${route.isEmpty ? 'none' : route} '
        'board_policy=${boardPolicy.isEmpty ? 'none' : boardPolicy} '
        'selected_alias=${selected.path} raw_count=${selected.rawCount} '
        'accepted_count=${selected.boards.length} '
        'rejected_count=${selected.rawCount - selected.boards.length} '
        'rejection_predicates=none '
        'first_board_keys=${firstBoard.keys.join(',')} '
        'first_item_keys=${firstItem.keys.join(',')}',
      );
      return AhviBoardCollection(
        path: selected.path,
        boards: selected.boards,
        rawCount: selected.rawCount,
        dedupDroppedCount: selected.dedupDroppedCount,
      );
    }
    debugPrint(
      'AHVI_LIVE_STYLE_NORMALIZER '
      'source_file=ahvi_response_policy.dart function=boardCollection '
      'resolved_route=${route.isEmpty ? 'none' : route} '
      'board_policy=${boardPolicy.isEmpty ? 'none' : boardPolicy} '
      'selected_alias=none raw_count=0 accepted_count=0 rejected_count=0 '
      'rejection_predicates=no_valid_board_alias first_board_keys=none '
      'first_item_keys=none',
    );
    return const AhviBoardCollection(path: '', boards: []);
  }

  bool get _boardPolicyAllows {
    if (boardPolicy.isEmpty) return true;
    return const {
      'allow',
      'allowed',
      'authorized',
      'board',
      'boards',
      'render',
      'render_boards',
      'recommendation',
      'ownership_backed',
      'wardrobe',
      'style_this',
      'build_outfit',
    }.contains(boardPolicy);
  }

  static String _policyName(dynamic value) {
    if (value is Map) {
      for (final key in ['policy', 'name', 'type', 'mode']) {
        final text = _normalize(value[key]);
        if (text.isNotEmpty) return text;
      }
      final canRender = _boolValue(
        value['can_render'] ?? value['render_boards'] ?? value['authorized'],
      );
      if (canRender != null) return canRender ? 'allow' : 'suppress';
      return '';
    }
    if (value is bool) return value ? 'allow' : 'suppress';
    return _normalize(value);
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalize(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty || text == 'null') return '';
    return text.replaceAll(RegExp(r'[\s-]+'), '_');
  }

  static String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case 'yes':
        case '1':
          return true;
        case 'false':
        case 'no':
        case '0':
          return false;
      }
    }
    return null;
  }

  static bool _truthy(dynamic value) => _boolValue(value) == true;

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is List) return _mapList(value);
    if (value is Map) return [Map<String, dynamic>.from(value)];
    return const [];
  }

  static ({List<Map<String, dynamic>> boards, int dedupDroppedCount})
  _normalizeBoards(List<Map<String, dynamic>> rawBoards) {
    final boards = <Map<String, dynamic>>[];
    final seen = <String>{};
    var dedupDroppedCount = 0;
    for (var index = 0; index < rawBoards.length; index++) {
      final raw = rawBoards[index];
      final board = <String, dynamic>{...raw};
      final items = _asList(
        raw['board_items'] ??
            raw['boardItems'] ??
            raw['items'] ??
            raw['pieces'] ??
            raw['composition_items'],
      );
      if (!board.containsKey('board_items') && items.isNotEmpty) {
        board['board_items'] = items;
      }
      if (!board.containsKey('title') &&
          (board['name'] ?? board['label'] ?? board['direction_name']) !=
              null) {
        board['title'] =
            board['name'] ?? board['label'] ?? board['direction_name'];
      }
      final boardId = _firstText([
        board['board_id'],
        board['boardId'],
        board['id'],
      ]);
      if (boardId.isNotEmpty && !board.containsKey('board_id')) {
        board['board_id'] = boardId;
      }
      final identity = boardId.isNotEmpty
          ? 'id:$boardId'
          : _fallbackBoardIdentity(board, index);
      if (!seen.add(identity)) {
        dedupDroppedCount++;
        continue;
      }
      boards.add(board);
    }
    return (boards: boards, dedupDroppedCount: dedupDroppedCount);
  }

  static int _boardCollectionScore(List<Map<String, dynamic>> boards) {
    var score = boards.length * 100;
    for (final board in boards) {
      final items = _asList(board['board_items'] ?? board['items']);
      if (items.isNotEmpty) score += 20;
      if (_firstText([
        board['board_id'],
        board['boardId'],
        board['id'],
      ]).isNotEmpty) {
        score += 10;
      }
      if (_firstText([
        board['title'],
        board['name'],
        board['label'],
      ]).isNotEmpty) {
        score += 5;
      }
    }
    return score;
  }

  static String _fallbackBoardIdentity(Map<String, dynamic> board, int index) {
    final title = _firstText([board['title'], board['name'], board['label']]);
    final items = _asList(board['board_items'] ?? board['items'])
        .map(
          (item) => _firstText([
            item['item_id'],
            item['id'],
            item[r'$id'],
            item['name'],
            item['label'],
          ]),
        )
        .where((value) => value.isNotEmpty)
        .join('|');
    if (title.isEmpty && items.isEmpty) return 'missing:$index';
    return 'fallback:${title.toLowerCase()}|$items';
  }
}

/// Deprecated product entry points are filtered at the action boundary only.
/// Internal `visual_directions` and visual board payloads remain untouched.
bool isDeprecatedVisibleStyleAction(Object? value) {
  final text = value is Map
      ? (value['label'] ?? value['title'] ?? value['action'] ?? value['value'])
            .toString()
      : value?.toString() ?? '';
  final normalized = text.trim().toLowerCase().replaceAll('_', ' ');
  return normalized == 'visual inspiration' ||
      normalized.startsWith('show visual inspiration') ||
      normalized == 'show moodboard' ||
      normalized.startsWith('show moodboard ');
}

List<dynamic> filterDeprecatedVisibleStyleActions(Object? value) {
  if (value is! List) return const [];
  return value.where((item) => !isDeprecatedVisibleStyleAction(item)).toList();
}

class StyleActionContext {
  final String action;
  final String originalRequest;
  final String occasion;
  final String sessionId;
  final Map<String, dynamic>? selectedAnchor;
  final bool wardrobeOverride;
  final String previousPairingTarget;
  final String boardId;
  final String boardRevision;

  const StyleActionContext({
    required this.action,
    required this.originalRequest,
    required this.occasion,
    required this.sessionId,
    this.selectedAnchor,
    required this.wardrobeOverride,
    required this.previousPairingTarget,
    required this.boardId,
    required this.boardRevision,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'style_action': action,
    if (originalRequest.isNotEmpty) 'original_request': originalRequest,
    if (occasion.isNotEmpty) 'occasion': occasion,
    if (sessionId.isNotEmpty) 'session_id': sessionId,
    if (selectedAnchor != null) 'selected_anchor': selectedAnchor,
    if (selectedAnchor != null) 'selected_item': selectedAnchor,
    if (selectedAnchor != null) 'anchor_item': selectedAnchor,
    'wardrobe_override': wardrobeOverride,
    if (previousPairingTarget.isNotEmpty)
      'previous_pairing_target': previousPairingTarget,
    if (boardId.isNotEmpty) 'board_id': boardId,
    if (boardRevision.isNotEmpty) 'board_revision': boardRevision,
    if (boardRevision.isNotEmpty) 'revision': boardRevision,
  };
}

StyleActionContext? styleActionContextFromValue(
  String value, {
  String originalRequest = '',
  String occasion = '',
  String sessionId = '',
  Map<String, dynamic>? selectedAnchor,
  bool wardrobeOverride = false,
  String previousPairingTarget = '',
  String boardId = '',
  String boardRevision = '',
}) {
  final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
  String? action;
  if (normalized == 'use my wardrobe' ||
      normalized == 'use wardrobe' ||
      normalized == 'from my wardrobe' ||
      normalized.startsWith('use my wardrobe for ')) {
    action = 'use_my_wardrobe';
    wardrobeOverride = true;
  } else if (normalized == 'find missing pieces' ||
      normalized == 'missing pieces' ||
      normalized == 'find this' ||
      normalized.startsWith('find missing pieces for ')) {
    action = 'find_missing_pieces';
  } else if (normalized == 'style this' ||
      normalized.startsWith('style this ')) {
    action = 'style_this';
  } else if (normalized == 'build outfit' ||
      normalized.startsWith('build outfit ')) {
    action = 'build_outfit';
  }
  if (action == null) return null;

  var request = originalRequest.trim();
  if (request.isEmpty) {
    for (final prefix in const [
      'use my wardrobe for ',
      'use wardrobe for ',
      'from my wardrobe for ',
      'find missing pieces for ',
      'style this for ',
      'build outfit for ',
    ]) {
      if (normalized.startsWith(prefix)) {
        request = value.trim().substring(prefix.length).trim();
        break;
      }
    }
  }
  final resolvedOccasion = occasion.trim().isNotEmpty
      ? occasion.trim()
      : _occasionFromRequest(request);
  return StyleActionContext(
    action: action,
    originalRequest: request,
    occasion: resolvedOccasion,
    sessionId: sessionId.trim(),
    selectedAnchor: selectedAnchor,
    wardrobeOverride: wardrobeOverride,
    previousPairingTarget: previousPairingTarget.trim(),
    boardId: boardId.trim(),
    boardRevision: boardRevision.trim(),
  );
}

String _occasionFromRequest(String request) {
  final normalized = request.toLowerCase();
  for (final occasion in const [
    'office',
    'date',
    'party',
    'travel',
    'beach',
    'workout',
  ]) {
    if (normalized.contains(occasion)) return occasion;
  }
  return '';
}

class AhviResponseToken {
  final String sessionId;
  final int generation;

  const AhviResponseToken(this.sessionId, this.generation);
}

class AhviSessionGenerationGuard {
  int _generation = 0;

  AhviResponseToken capture(String sessionId) =>
      AhviResponseToken(sessionId, _generation);

  void invalidate() => _generation++;

  bool accepts(AhviResponseToken token, String currentSessionId) =>
      token.sessionId == currentSessionId && token.generation == _generation;

  @visibleForTesting
  int get generation => _generation;
}

class AhviClientCopy {
  static const connectionError =
      'I could not reach AHVI just now. Please try again.';
  static const timeout =
      'AHVI is taking a little longer than expected. Please try again.';
  static const emptyResponse =
      'I did not get a useful reply. Please try again.';
  static const requestError =
      'Something went wrong while I was working on that. Please try again.';
  static const noClosestOption =
      'I could not build a closest option from the available wardrobe.';
  static const addedOptions = 'I added a few more options.';
  static const existingOptions =
      'I showed the strongest options from this wardrobe.';

  const AhviClientCopy._();
}
