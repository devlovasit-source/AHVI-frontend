import 'package:flutter/foundation.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';

AhviParsedResponse parseAhviResponse(Map<String, dynamic> response) {
  debugPrint('AHVI_RESPONSE_KEYS: ${response.keys.toList()}');

  final parsed = AhviResponse.fromMap(response);
  final rawMessage = response['message'];
  final data = _dataMap(response);
  final text =
      (response['message_text'] ??
              response['response'] ??
              (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
              '')
          .toString();
  final blocks = <AhviResponseBlock>[];

  // Style V2: open-ended structured advice (body proportion / color / occasion).
  for (final advType in const [
    'body_proportion_advice',
    'color_advice',
    'occasion_advice',
  ]) {
    final adv = _blockByType(response, advType);
    if (adv.isNotEmpty) {
      blocks.add(AhviResponseBlock(type: AhviBlockType.styleAdvice, data: adv));
    }
  }

  // Style V2: transition plan (keep/swap/add) renders first.
  final transitionPlan = _blockByType(response, 'transition_plan');
  if (transitionPlan.isNotEmpty) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.transitionPlan,
        data: transitionPlan,
      ),
    );
  }

  // PATCH 1: Suppress duplicate text card if the new board is present.
  const bool kVisualBoard85Enabled = bool.fromEnvironment(
    'ENABLE_VISUAL_BOARD_85_LAYOUT',
    defaultValue: true,
  );
  var visualDirections = _extractVisualDirections(response, data);
  // Render wardrobe boards (style_boards/rendered_boards/outfits) through the
  // SAME editorial flat-lay as catalog directions. When the backend ships only
  // style_boards (e.g. "use my wardrobe" / weak_occasion_match), convert them
  // to the visual_directions shape so the look is consistent everywhere.
  var convertedWardrobeBoards = false;
  if (visualDirections.isEmpty) {
    final wardrobeBoards = _extractStyleBoards(response, data);
    if (wardrobeBoards.isNotEmpty) {
      visualDirections = wardrobeBoards.map(_styleBoardToDirection).toList();
      convertedWardrobeBoards = true;
    }
  }
  final hasVisualDirections = visualDirections.isNotEmpty;
  final hasVisualBoard =
      AhviVisualBoard.isVisualBoard(response) ||
      response['visual_board'] != null ||
      response['visualBoard'] != null ||
      data['visual_board'] != null ||
      data['visualBoard'] != null;

  // Visual inspiration board.
  final visualInspiration = _extractVisualInspiration(response, data);
  if (visualInspiration.isNotEmpty &&
      !(kVisualBoard85Enabled && (hasVisualDirections || hasVisualBoard))) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.visualInspiration,
        data: visualInspiration,
      ),
    );
  }

  if (hasVisualDirections) {
    final editorialCover = _extractEditorialCover(response, data);
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.visualDirections,
        data: {
          'directions': visualDirections,
          'visual_directions': visualDirections,
          if (editorialCover.isNotEmpty) 'editorial_cover': editorialCover,
        },
      ),
    );
  }

  if (AhviVisualBoard.isVisualBoard(response)) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.visualBoard,
        data: {'board': AhviVisualBoard.fromJson(response)},
      ),
    );
  } else {
    final visualBoard = response['visual_board'] ?? response['visualBoard'];
    if (visualBoard is Map) {
      final boardMap = Map<String, dynamic>.from(visualBoard);
      blocks.add(
        AhviResponseBlock(
          type: AhviBlockType.visualBoard,
          data: {'board': AhviVisualBoard.fromJson(boardMap)},
        ),
      );
    }
  }

  final wardrobeGap = _extractWardrobeGap(response, data);
  if (wardrobeGap.isNotEmpty) {
    blocks.add(
      AhviResponseBlock(type: AhviBlockType.wardrobeGap, data: wardrobeGap),
    );
  }

  final image = _extractImage(response, data);
  if (image.isNotEmpty) {
    blocks.add(AhviResponseBlock(type: AhviBlockType.image, data: image));
  }

  final planBlock = _extractPlanBlock(response, data);
  if (planBlock != null) blocks.add(planBlock);

  final sharedModuleCard = hasVisualDirections
      ? null
      : AhviModuleCard.fromResponse(response);
  if (sharedModuleCard != null) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.moduleCards,
        data: {'module_card': sharedModuleCard},
      ),
    );
  } else {
    final moduleCards = _extractModuleCards(
      response,
      data,
      suppressVisualDirectionCards: hasVisualDirections,
    );
    if (moduleCards.isNotEmpty) {
      blocks.add(
        AhviResponseBlock(
          type: _looksLikeChecklist(response, data)
              ? AhviBlockType.checklist
              : AhviBlockType.moduleCards,
          data: {'cards': moduleCards},
        ),
      );
    }
  }

  if (!_looksLikeModuleResponse(response, data) && !convertedWardrobeBoards) {
    final styleBoards = _extractStyleBoards(response, data);
    if (styleBoards.isNotEmpty) {
      blocks.add(
        AhviResponseBlock(
          type: AhviBlockType.styleBoards,
          data: {'boards': styleBoards},
        ),
      );
    }
  }

  // Style V2: "why this fits you" stylist reasoning, after directions.
  final stylistReasoning = _blockByType(response, 'stylist_reasoning');
  if (!hasVisualDirections &&
      !_hasStyleBoardBlock(blocks) &&
      stylistReasoning.isNotEmpty &&
      (stylistReasoning['archetype'] ?? '').toString().trim().isNotEmpty) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.stylistReasoning,
        data: stylistReasoning,
      ),
    );
  }

  // Style V2: missing-piece intelligence renders AFTER boards.
  final missingPiece = _extractMissingPiece(response, data);
  if (missingPiece.isNotEmpty) {
    blocks.add(
      AhviResponseBlock(type: AhviBlockType.missingPiece, data: missingPiece),
    );
  }

  debugPrint('AHVI_PARSED_BLOCKS: ${blocks.map((e) => e.type).toList()}');

  return AhviParsedResponse(
    text: text,
    chips: parsed.chips.map((chip) => chip.toJson()).toList(),
    blocks: blocks,
    boardId: response['board_ids']?.toString(),
    packId: response['pack_ids']?.toString(),
  );
}

bool _hasStyleBoardBlock(List<AhviResponseBlock> blocks) {
  return blocks.any((block) => block.type == AhviBlockType.styleBoards);
}

Map<String, dynamic> _dataMap(Map<String, dynamic> response) {
  final data = response['data'];
  return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

/// Find a typed block (matching `type == wanted`) inside response["blocks"].
Map<String, dynamic> _blockByType(
  Map<String, dynamic> response,
  String wanted,
) {
  final raw = response['blocks'];
  if (raw is List) {
    for (final b in raw) {
      if (b is Map && (b['type'] ?? '').toString() == wanted) {
        return Map<String, dynamic>.from(b);
      }
    }
  }
  return const {};
}

Map<String, dynamic> _extractVisualInspiration(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final direct =
      response['visual_inspiration_board'] ?? data['visual_inspiration_board'];
  if (direct is Map && direct.isNotEmpty) {
    return Map<String, dynamic>.from(direct);
  }
  return _blockByType(response, 'visual_inspiration_board');
}

Map<String, dynamic> _extractMissingPiece(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final direct =
      response['missing_piece_intelligence'] ??
      data['missing_piece_intelligence'];
  if (direct is Map && direct.isNotEmpty) {
    final m = Map<String, dynamic>.from(direct);
    if (_mapList(m['missing_items']).isNotEmpty) return m;
  }
  final block = _blockByType(response, 'missing_piece_intelligence');
  if (block.isNotEmpty && _mapList(block['missing_items']).isNotEmpty) {
    return block;
  }
  return const {};
}

List<Map<String, dynamic>> _extractVisualDirections(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  return _mapList(
    response['visual_directions'] ??
        response['visualDirections'] ??
        data['visual_directions'] ??
        data['visualDirections'],
  );
}

/// Magazine-cover header surfaced above the direction cards. Backend ships
/// this on the style-reasoning response (additive); falls back to {} when
/// the payload is older.
Map<String, dynamic> _extractEditorialCover(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  for (final value in [
    response['editorial_cover'],
    response['editorialCover'],
    data['editorial_cover'],
    data['editorialCover'],
  ]) {
    if (value is Map && value.isNotEmpty) {
      return Map<String, dynamic>.from(value);
    }
  }
  return const {};
}

/// Convert a wardrobe style_board (cards/outfits with role-tagged items) into
/// the visual_directions shape so it renders through the editorial flat-lay
/// board, matching catalog directions. Items already carry role/slot + image.
Map<String, dynamic> _styleBoardToDirection(Map<String, dynamic> board) {
  final items = _mapList(
    board['items'] ?? board['board_items'] ?? board['composition_items'],
  );
  final boardItems = items
      .map((it) {
        final image =
            it['image_url'] ??
            it['imageUrl'] ??
            it['normalized_url'] ??
            it['normalizedUrl'] ??
            it['masked_url'] ??
            it['maskedUrl'];
        return <String, dynamic>{
          ...it,
          'name': it['name'] ?? it['title'] ?? it['label'],
          'role': it['role'] ?? it['slot'] ?? it['category'],
          'image_url': image,
          if (it['board_image_url'] != null)
            'board_image_url': it['board_image_url'],
        };
      })
      .where((it) => (it['image_url']?.toString().trim().isNotEmpty ?? false))
      .toList();
  return <String, dynamic>{
    ...board,
    'direction_name': board['title'] ?? board['name'],
    'title': board['title'] ?? board['name'],
    'why_it_works':
        board['explanation'] ?? board['why_it_works'] ?? board['style_reason'],
    'occasion': board['occasion'],
    'board_items': boardItems,
    'hero_piece': boardItems.isNotEmpty ? boardItems.first['name'] : null,
  };
}

List<Map<String, dynamic>> _extractStyleBoards(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  for (final value in [
    response['style_boards'],
    response['rendered_boards'],
    response['outfits'],
    data['style_boards'],
    data['rendered_boards'],
    data['outfits'],
  ]) {
    final boards = _mapList(value);
    if (boards.isNotEmpty) return boards;
  }
  return const [];
}

List<Map<String, dynamic>> _extractModuleCards(
  Map<String, dynamic> response,
  Map<String, dynamic> data, {
  bool suppressVisualDirectionCards = false,
}) {
  final out = <Map<String, dynamic>>[];
  void add(dynamic value) {
    if (value is Map) out.add(Map<String, dynamic>.from(value));
  }

  add(response['card']);
  add(response['moduleCard']);
  add(data['card']);
  add(data['moduleCard']);
  final visualSections = _mapList(
    response['visual_sections'] ??
        response['visualSections'] ??
        data['visual_sections'] ??
        data['visualSections'],
  );
  if (visualSections.isNotEmpty) {
    out.add({
      'type': 'visual_packing_checklist',
      'title':
          response['title'] ?? data['title'] ?? 'Carry-on Packing Checklist',
      'subtitle':
          data['duration_label'] ??
          response['subtitle'] ??
          data['subtitle'] ??
          '',
      'visual_sections': visualSections,
      'actions':
          response['quick_actions'] ??
          response['chips'] ??
          data['quick_actions'],
    });
    return out;
  }
  out.addAll(_mapList(response['cards']));
  out.addAll(_mapList(response['module_cards']));
  out.addAll(_mapList(response['moduleCards']));
  out.addAll(_mapList(data['cards']));
  out.addAll(_mapList(data['module_cards']));
  out.addAll(_mapList(data['moduleCards']));

  if (out.isEmpty && _looksLikeModuleResponse(response, data)) {
    out.add(response);
  }
  if (!suppressVisualDirectionCards) return out;
  return out
      .where((card) {
        final type = (card['type'] ?? '').toString().toLowerCase().trim();
        return type != 'visual_direction' && type != 'style_reasoning';
      })
      .toList(growable: false);
}

Map<String, dynamic> _extractWardrobeGap(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final gap =
      response['wardrobe_gap'] ??
      response['wardrobeGap'] ??
      data['wardrobe_gap'] ??
      data['wardrobeGap'];
  if (gap is Map) return Map<String, dynamic>.from(gap);
  final missing = _mapList(response['missing_items'] ?? data['missing_items']);
  if (missing.isEmpty) return const {};
  return {
    'missing_items': missing,
    'message': response['message_text'] ?? response['response'],
  };
}

Map<String, dynamic> _extractImage(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final url =
      response['image_url'] ??
      response['imageUrl'] ??
      response['url'] ??
      data['image_url'] ??
      data['imageUrl'] ??
      data['url'];
  final text = url?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return const {};
  return {'image_url': text};
}

AhviResponseBlock? _extractPlanBlock(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final plan = response['plan'] ?? data['plan'];
  if (plan is Map) {
    return AhviResponseBlock(
      type: AhviBlockType.plan,
      data: {
        'cards': [Map<String, dynamic>.from(plan)],
      },
    );
  }
  final checklist =
      response['travel_checklist'] ??
      response['checklist'] ??
      data['travel_checklist'] ??
      data['checklist'];
  final checklistCards = _mapList(checklist);
  if (checklistCards.isNotEmpty) {
    return AhviResponseBlock(
      type: AhviBlockType.checklist,
      data: {'cards': checklistCards},
    );
  }
  if (checklist is List) {
    return AhviResponseBlock(
      type: AhviBlockType.checklist,
      data: {
        'cards': [
          {'title': 'Checklist', 'items': checklist},
        ],
      },
    );
  }
  return null;
}

bool _looksLikeChecklist(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final type = (response['type'] ?? data['type'] ?? '')
      .toString()
      .toLowerCase();
  final intent = (response['intent'] ?? data['intent'] ?? '')
      .toString()
      .toLowerCase();
  return type.contains('checklist') ||
      intent == 'plan_pack' ||
      intent == 'open_checklist' ||
      intent == 'weather_prep';
}

bool _looksLikeModuleResponse(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  final type = (response['type'] ?? data['type'] ?? '')
      .toString()
      .toLowerCase();
  final responseType =
      (response['response_type'] ?? data['response_type'] ?? '').toString();
  final intent = (response['intent'] ?? data['intent'] ?? '')
      .toString()
      .toLowerCase();
  final module =
      (response['module'] ??
              response['domain'] ??
              data['module'] ??
              data['domain'] ??
              '')
          .toString()
          .toLowerCase();
  return responseType == 'module_card' ||
      type.contains('checklist') ||
      type == 'module_response' ||
      type == 'module_card' ||
      intent == 'plan_pack' ||
      module == 'planner' ||
      module == 'calendar' ||
      module == 'bills' ||
      module == 'medicines' ||
      module == 'meals' ||
      module == 'workout' ||
      module == 'skincare';
}
