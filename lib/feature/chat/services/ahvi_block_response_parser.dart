import 'package:flutter/foundation.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/services/ahvi_response_policy.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';

AhviParsedResponse parseAhviResponse(Map<String, dynamic> response) {
  debugPrint('AHVI_RESPONSE_KEYS: ${response.keys.toList()}');

  final parsed = AhviResponse.fromMap(response);
  final responsePolicy = AhviResponsePolicy.fromResponse(response);
  final isPackingResponse = isAhviPackingEnvelope(response);
  final rawMessage = response['message'];
  final data = _dataMap(response);
  final isStyleThisResponse =
      (response['route'] ?? response['mode'] ?? '').toString().trim() ==
          'style_this';
  final hasStyleThisAnchor =
      !isStyleThisResponse || _anchorItemMap(response, data).isNotEmpty;
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
  var visualDirections = responsePolicy.canRenderBoards(response) &&
      !isPackingResponse
      ? _extractVisualDirections(response, data)
      : <Map<String, dynamic>>[];
  final hasStyleThisDirections =
      isStyleThisResponse &&
          _extractStyleThisDirections(response, data).isNotEmpty;
  // Style This ships its boards under top-level `style_directions` (not
  // `visual_directions`). Adapt them into the canonical visualDirections shape
  // so parseAhviResponse → AhviBlockRenderer → VisualDirectionCarousel →
  // AhviOutfitBoardCard renders them exactly like normal directions. Only runs
  // when there are no normal visual_directions, so that path is untouched.
  if (visualDirections.isEmpty &&
      responsePolicy.canRenderBoards(response) &&
      hasStyleThisAnchor &&
      responsePolicy.hasValidatedAnchorIn(response) &&
      !_looksLikeModuleResponse(response, data) &&
      !isPackingResponse) {
    final styleDirections = _extractStyleThisDirections(response, data);
    if (styleDirections.isNotEmpty) {
      final anchor = _anchorItemMap(response, data);
      final sourcePolicy = _validSourcePolicy(
        response['source_policy'] ?? data['source_policy'],
      );
      var index = 0;
      visualDirections = styleDirections
          .map(
            (dir) =>
            _styleDirectionToCanonical(dir, anchor, index++, sourcePolicy),
      )
          .map((board) => responsePolicy.decorateBoard(board, response))
          .where((board) {
        final expectedAnchor = _itemId(anchor);
        final boardAnchor = (board['anchor_item_id'] ?? '')
            .toString()
            .trim();
        final boardItems = _mapList(board['board_items']);
        final matches = boardItems
            .where((item) => _itemId(item) == expectedAnchor)
            .length;
        return expectedAnchor.isNotEmpty &&
            boardAnchor == expectedAnchor &&
            matches == 1;
      })
          .toList();
      debugPrint(
        'AHVI_STYLE_DIRECTION_ADAPTER source_field=style_directions '
            'direction_count=${styleDirections.length} '
            'mapped_block_count=${visualDirections.length}',
      );
    }
  }
  // Render wardrobe boards (style_boards/rendered_boards/outfits) through the
  // SAME editorial flat-lay as catalog directions. When the backend ships only
  // style_boards (e.g. "use my wardrobe" / weak_occasion_match), convert them
  // to the visual_directions shape so the look is consistent everywhere.
  var convertedWardrobeBoards = false;
  if (visualDirections.isEmpty &&
      responsePolicy.canRenderBoards(response) &&
      hasStyleThisAnchor &&
      !hasStyleThisDirections &&
      !_looksLikeModuleResponse(response, data) &&
      !isPackingResponse) {
    final wardrobeBoards = responsePolicy.boardCollection(response).boards;
    if (wardrobeBoards.isNotEmpty) {
      visualDirections = wardrobeBoards.map(_styleBoardToDirection).toList();
      convertedWardrobeBoards = true;
    }
  }
  if (isStyleThisResponse && !hasStyleThisAnchor) {
    visualDirections = <Map<String, dynamic>>[];
  }
  if (isStyleThisResponse && hasStyleThisAnchor && visualDirections.isNotEmpty) {
    final anchorId = _itemId(_anchorItemMap(response, data));
    if (anchorId.isNotEmpty) {
      visualDirections = visualDirections
          .map(
            (direction) => <String, dynamic>{
          ...direction,
          'anchor_item_id':
          direction['anchor_item_id'] ??
              direction['anchorItemId'] ??
              direction['selected_item_id'] ??
              direction['selectedItemId'] ??
              anchorId,
          'selected_item_id':
          direction['selected_item_id'] ??
              direction['selectedItemId'] ??
              direction['anchor_item_id'] ??
              direction['anchorItemId'] ??
              anchorId,
        },
      )
          .toList(growable: false);
    }
  }
  final hasVisualDirections = visualDirections.isNotEmpty;
  final hasVisualBoard =
      responsePolicy.canRenderBoards(response) &&
          !isPackingResponse &&
          (AhviVisualBoard.isVisualBoard(response) ||
              response['visual_board'] != null ||
              response['visualBoard'] != null ||
              data['visual_board'] != null ||
              data['visualBoard'] != null);

  // Visual inspiration board.
  final visualInspiration = _extractVisualInspiration(response, data);
  if (responsePolicy.canRenderBoards(response) &&
      !isPackingResponse &&
      visualInspiration.isNotEmpty &&
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

  if (hasVisualBoard && AhviVisualBoard.isVisualBoard(response)) {
    blocks.add(
      AhviResponseBlock(
        type: AhviBlockType.visualBoard,
        data: {'board': AhviVisualBoard.fromJson(response)},
      ),
    );
  } else {
    final visualBoard = response['visual_board'] ?? response['visualBoard'];
    if (hasVisualBoard && visualBoard is Map) {
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

  final suppressStructuredCards =
      responsePolicy.hasCanonicalRoute &&
          !responsePolicy.canRenderBoards(response);
  final sharedModuleCard = hasVisualDirections || suppressStructuredCards
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
    final moduleCards = suppressStructuredCards
        ? const <Map<String, dynamic>>[]
        : _extractModuleCards(
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

  if (responsePolicy.canRenderBoards(response) &&
      !isPackingResponse &&
      !_looksLikeModuleResponse(response, data) &&
      !convertedWardrobeBoards) {
    final styleBoards = responsePolicy.boardCollection(response).boards;
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
    chips: filterDeprecatedVisibleStyleActions(
      parsed.chips.map((chip) => chip.toJson()).toList(),
    ).whereType<Map>().map((chip) => Map<String, dynamic>.from(chip)).toList(),
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

/// Style This ships its boards under `style_directions`.
List<Map<String, dynamic>> _extractStyleThisDirections(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
    ) {
  return _mapList(
    response['style_directions'] ??
        response['styleDirections'] ??
        data['style_directions'] ??
        data['styleDirections'],
  );
}

/// Top-level anchor garment as a board-item-shaped map (id + image + role).
Map<String, dynamic> _anchorItemMap(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
    ) {
  final anchor =
      response['anchor_item'] ??
          response['anchorItem'] ??
          data['anchor_item'] ??
          data['anchorItem'];
  final m = anchor is Map
      ? Map<String, dynamic>.from(anchor)
      : <String, dynamic>{};
  final anchorMapId =
  (m['item_id'] ?? m['id'] ?? m[r'$id'] ?? '').toString().trim();
  final selectedId =
  (response['selected_item_id'] ??
      response['selectedItemId'] ??
      data['selected_item_id'] ??
      data['selectedItemId'] ??
      '')
      .toString()
      .trim();
  final declaredAnchorId =
  (response['anchor_item_id'] ?? data['anchor_item_id'] ?? '')
      .toString()
      .trim();
  final identityMismatch =
      (selectedId.isNotEmpty &&
          ((anchorMapId.isNotEmpty && selectedId != anchorMapId) ||
              (declaredAnchorId.isNotEmpty && selectedId != declaredAnchorId))) ||
          (declaredAnchorId.isNotEmpty &&
              anchorMapId.isNotEmpty &&
              declaredAnchorId != anchorMapId);
  if (identityMismatch) {
    return const {};
  }
  final id = selectedId.isNotEmpty
      ? selectedId
      : (declaredAnchorId.isNotEmpty ? declaredAnchorId : anchorMapId);
  if (id.isEmpty) return const {};
  final safeImage =
      m['safe_image_url'] ??
          m['safeImageUrl'] ??
          m['board_image_url'] ??
          m['boardImageUrl'] ??
          m['cutout_url'] ??
          m['cutoutUrl'] ??
          m['catalog_image_url'] ??
          m['catalogImageUrl'] ??
          m['normalized_url'] ??
          m['normalizedUrl'] ??
          m['masked_url'] ??
          m['maskedUrl'] ??
          m['resolved_image_url'] ??
          m['image_url'] ??
          m['imageUrl'];
  return {
    ...m,
    'item_id': id,
    if (safeImage != null && safeImage.toString().trim().isNotEmpty)
      'image_url': safeImage,
    'safe_image_url': safeImage,
    if (safeImage != null && safeImage.toString().trim().isNotEmpty)
      'normalized_url': safeImage,
    'role': m['role'] ?? m['category'],
    'owned': true,
  };
}

String _itemId(Map<String, dynamic> it) =>
    (it['item_id'] ?? it['id'] ?? it[r'$id'] ?? '').toString().trim();

const _validSourcePolicies = {'wardrobe', 'style_asset', 'mixed'};

/// Return the value only if it is an allowed board source policy, else null.
String? _validSourcePolicy(dynamic value) {
  final policy = value?.toString().trim().toLowerCase();
  return _validSourcePolicies.contains(policy) ? policy : null;
}

/// Map one backend `style_directions` entry to a canonical visual direction.
///
/// The backend entry is `{title, items, missing_items, styling_note}` — no
/// board_id/revision/positions and its garments live under `items` (not
/// `board_items`). Synthesize the contract fields the modal + board card
/// require: stable board_id, revision=1, style_this scenario/mode, wardrobe
/// source; map items→board_items; guarantee the anchor is present so it can be
/// the locked piece.
Map<String, dynamic> _styleDirectionToCanonical(
    Map<String, dynamic> direction,
    Map<String, dynamic> anchorItem,
    int index,
    String? responsePolicy,
    ) {
  final anchorId = _itemId(anchorItem);
  final items = _mapList(
    direction['items'] ?? direction['board_items'] ?? direction['boardItems'],
  );

  final anchorCatalog =
      anchorItem['normalized_url'] ??
          anchorItem['normalizedUrl'] ??
          anchorItem['resolved_image_url'];

  final anchorIndex = anchorId.isEmpty
      ? -1
      : items.indexWhere((item) => _itemId(item) == anchorId);

  final backendAnchor = anchorIndex >= 0
      ? items[anchorIndex]
      : <String, dynamic>{};

  final supportingItems = <Map<String, dynamic>>[
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++)
      if (itemIndex != anchorIndex && _itemId(items[itemIndex]) != anchorId)
        items[itemIndex],
  ];

  final canonicalAnchor = <String, dynamic>{
    ...anchorItem,
    ...backendAnchor,
    if (anchorId.isNotEmpty) 'item_id': anchorId,
    if (anchorId.isNotEmpty) 'id': anchorId,
    if (anchorCatalog != null && backendAnchor.isEmpty)
      'normalized_url': anchorCatalog,
    'anchor': true,
    'locked': true,
    'source': 'wardrobe',
    'source_policy': 'wardrobe',
    'scenario': 'style_this',
    'interaction_mode': 'style_this',
  };

  // Keep the selected garment first. A downstream visual item cap must never
  // remove the garment that originated the Style This request.
  final boardItems = anchorId.isNotEmpty && anchorItem.isNotEmpty
      ? (anchorIndex >= 0
      ? <Map<String, dynamic>>[canonicalAnchor, ...supportingItems]
      : items)
      : items;

  final existingBoardId = (direction['board_id'] ?? '').toString().trim();
  final boardId =
  (existingBoardId.isNotEmpty &&
      !existingBoardId.toLowerCase().startsWith('outfit_card_'))
      ? existingBoardId
      : (anchorId.isNotEmpty
      ? 'style_this_${anchorId}_$index'
      : 'style_this_$index');
  final revision =
  (direction['revision'] is num && (direction['revision'] as num) >= 1)
      ? direction['revision']
      : 1;

  // Resolution order: direction-level → response-level → wardrobe fallback.
  // Never overwrite an explicit style_asset / mixed policy with wardrobe.
  final sourcePolicy =
      _validSourcePolicy(direction['source_policy']) ??
          responsePolicy ??
          'wardrobe';

  final out = <String, dynamic>{
    ...direction,
    'board_id': boardId,
    'revision': revision,
    'scenario': 'style_this',
    'interaction_mode': 'style_this',
    'source_policy': sourcePolicy,
    'board_items': boardItems,
    'title': direction['title'] ?? direction['direction_name'],
    'why_it_works': direction['why_it_works'] ?? direction['styling_note'],
  };
  if (anchorId.isNotEmpty) {
    out['anchor_item_id'] = anchorId;
    out['selected_item_id'] = anchorId;
    out['originating_item_id'] = direction['originating_item_id'] ?? anchorId;
  }
  return out;
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
    final out = <String, dynamic>{
      ...it,
      'name': it['name'] ?? it['title'] ?? it['label'],
      'role': it['role'] ?? it['slot'] ?? it['category'],
    };

    void canonical(String field, Object? snake, Object? camel) {
      final value = snake ?? camel;
      if (value?.toString().trim().isNotEmpty == true) out[field] = value;
    }

    canonical(
      'asset_cutout_url',
      it['asset_cutout_url'],
      it['assetCutoutUrl'],
    );
    canonical('cutout_url', it['cutout_url'], it['cutoutUrl']);
    canonical(
      'asset_masked_url',
      it['asset_masked_url'],
      it['assetMaskedUrl'],
    );
    canonical('masked_url', it['masked_url'], it['maskedUrl']);
    canonical(
      'transparent_url',
      it['transparent_url'],
      it['transparentUrl'],
    );
    canonical('processed_url', it['processed_url'], it['processedUrl']);
    canonical('normalized_url', it['normalized_url'], it['normalizedUrl']);
    canonical(
      'board_image_url',
      it['board_image_url'],
      it['boardImageUrl'],
    );
    canonical('image_url', it['image_url'], it['imageUrl']);
    canonical('image_url', it['safe_image_url'], it['safeImageUrl']);
    canonical('image_url', it['resolved_image_url'], it['resolvedImageUrl']);
    canonical('image_url', it['catalog_image_url'], it['catalogImageUrl']);
    canonical('image_url', it['display_image_url'], it['displayImageUrl']);
    canonical('image_url', it['product_url'], it['productUrl']);
    canonical('image_url', it['url'], it['link']);
    return out;
  })
      .where(
        (it) => const [
      'asset_cutout_url',
      'cutout_url',
      'asset_masked_url',
      'masked_url',
      'transparent_url',
      'processed_url',
      'normalized_url',
      'board_image_url',
      'image_url',
    ].any((field) => it[field]?.toString().trim().isNotEmpty == true),
  )
      .toList();
  final compositeImage =
      board['board_image_url'] ??
          board['boardImageUrl'] ??
          board['image_url'] ??
          board['imageUrl'];
  if (boardItems.isEmpty &&
      compositeImage?.toString().trim().isNotEmpty == true) {
    boardItems.add({
      'item_id': '${board['board_id'] ?? board['id'] ?? 'rendered'}-composite',
      'name': board['title'] ?? board['name'] ?? 'Rendered outfit',
      'role': 'dress',
      'slot': 'dress',
      'source': 'style_asset',
      'image_url': compositeImage,
      'locked': false,
    });
  }
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
  (response['response_type'] ?? data['response_type'] ?? '')
      .toString()
      .toLowerCase();
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
      module == 'diet' ||
      module == 'fitness' ||
      module == 'medi' ||
      module == 'medicines' ||
      module == 'meals' ||
      module == 'home' ||
      module == 'workout' ||
      module == 'skincare';
}
