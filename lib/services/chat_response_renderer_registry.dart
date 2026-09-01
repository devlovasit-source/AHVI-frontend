import 'package:flutter/foundation.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/services/ahvi_response_policy.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';

enum AhviChatRendererKind {
  visualPackingChecklist,
  visualBoard,
  visualDirections,
  styleBoard,
  moduleCard,
  calendarPlan,
  genericModuleCard,
  text,
}

class AhviChatRendererSelection {
  final AhviChatRendererKind kind;
  final String responseType;
  final String visualType;
  final String module;
  final String reason;

  const AhviChatRendererSelection({
    required this.kind,
    required this.responseType,
    required this.visualType,
    required this.module,
    required this.reason,
  });

  String get renderer => kind.name;
}

/// Canonical, payload-only renderer selection. It deliberately has no request
/// or navigation responsibilities; surfaces decide how to invoke their
/// existing callbacks after selection.
class AhviChatResponseRendererRegistry {
  const AhviChatResponseRendererRegistry._();

  static AhviChatRendererSelection select(Map<String, dynamic> response) {
    final data = _map(response['data']);
    final policy = AhviResponsePolicy.fromResponse(response);
    final packing = _packingCard(response, data);
    final responseType = _firstText([
      response['response_type'],
      response['type'],
      data['response_type'],
      data['type'],
    ]);
    final visualType = _firstText([
      response['visual_type'],
      response['visualType'],
      data['visual_type'],
      data['visualType'],
    ]);
    final module = _firstText([
      response['module'],
      response['domain'],
      data['module'],
      data['domain'],
    ]);

    AhviChatRendererKind kind;
    String reason;
    if ((policy.hasCanonicalRoute && !policy.canRenderBoards(response) ||
            policy.isSafetySensitive) &&
        _hasStyleVisualPayload(response, data)) {
      kind = AhviChatRendererKind.text;
      reason = policy.isSafetySensitive
          ? 'safety_text_first'
          : 'canonical_board_policy_suppressed';
    } else if (packing != null) {
      kind = AhviChatRendererKind.visualPackingChecklist;
      reason = 'visual_sections';
    } else if (isAhviPackingEnvelope(response)) {
      kind = AhviChatRendererKind.text;
      reason = 'packing_style_renderer_suppressed';
    } else if (policy.canRenderBoards(response) &&
        (AhviVisualBoard.isVisualBoard(response) ||
            response['visual_board'] is Map ||
            response['visualBoard'] is Map ||
            data['visual_board'] is Map ||
            data['visualBoard'] is Map)) {
      kind = AhviChatRendererKind.visualBoard;
      reason = 'visual_board';
    } else if (policy.canRenderBoards(response) &&
        (_hasList(response['visual_directions']) ||
            _hasList(data['visual_directions']) ||
            _hasList(response['visualDirections']) ||
            _hasList(data['visualDirections']) ||
            _hasList(response['style_directions']) ||
            _hasList(data['style_directions']))) {
      kind = AhviChatRendererKind.visualDirections;
      reason = 'canonical_style_directions';
    } else if (policy.canRenderBoards(response) &&
        policy.boardCollection(response).isValid) {
      kind = AhviChatRendererKind.styleBoard;
      reason = 'canonical_board_alias';
    } else if (AhviModuleCard.isModuleCard(response)) {
      kind = AhviChatRendererKind.moduleCard;
      reason = 'typed_module_card';
    } else if (_isCalendarPlan(response, data)) {
      kind = AhviChatRendererKind.calendarPlan;
      reason = 'calendar_plan_contract';
    } else if (_isModuleResponse(response, data)) {
      kind = AhviChatRendererKind.genericModuleCard;
      reason = 'module_response';
    } else if (_hasCards(response, data)) {
      kind = AhviChatRendererKind.genericModuleCard;
      reason = 'card_payload';
    } else {
      kind = AhviChatRendererKind.text;
      reason = 'no_structured_payload';
    }

    final selection = AhviChatRendererSelection(
      kind: kind,
      responseType: responseType,
      visualType: visualType,
      module: module,
      reason: reason,
    );
    debugPrint(
      'AHVI_CHAT_RENDERER_SELECT response_type=${selection.responseType} '
      'visual_type=${selection.visualType} module=${selection.module} '
      'selected_renderer=${selection.renderer} reason=${selection.reason}',
    );
    if (kind == AhviChatRendererKind.text &&
        (responseType.isNotEmpty ||
            visualType.isNotEmpty ||
            module.isNotEmpty)) {
      debugPrint(
        'AHVI_CHAT_RENDERER_FALLBACK unsupported_type=${responseType.isEmpty ? visualType : responseType} '
        'reason=${selection.reason} generic_text=true',
      );
    }
    return selection;
  }

  static Map<String, dynamic>? packingCard(Map<String, dynamic> response) {
    return _packingCard(response, _map(response['data']));
  }

  static AhviModuleCard? typedModuleCard(Map<String, dynamic> response) =>
      AhviModuleCard.fromResponse(response);

  /// Normalizes the card aliases without changing the backend payload.
  static List<Map<String, dynamic>> moduleCards(Map<String, dynamic> response) {
    final data = _map(response['data']);
    final out = <Map<String, dynamic>>[];
    void add(dynamic value) {
      if (value is Map) out.add(Map<String, dynamic>.from(value));
    }

    final packing = _packingCard(response, data);
    if (packing != null) return [packing];
    if (isAhviPackingEnvelope(response)) return const [];
    add(response['card']);
    add(response['moduleCard']);
    add(data['card']);
    add(data['moduleCard']);
    for (final value in [
      response['cards'],
      response['module_cards'],
      response['moduleCards'],
      data['cards'],
      data['module_cards'],
      data['moduleCards'],
    ]) {
      if (value is List) {
        out.addAll(
          value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
        );
      }
    }
    if (out.isEmpty && _isModuleResponse(response, data)) {
      out.add(Map<String, dynamic>.from(response));
    }
    return out;
  }

  static Map<String, dynamic>? _packingCard(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) {
    for (final source in [response, data]) {
      final raw = source['visual_sections'] ?? source['visualSections'];
      if (raw is List) {
        return _normalizePackingCard(source, response, raw);
      }
    }
    final nestedCards = [
      response['card'],
      response['moduleCard'],
      data['card'],
      data['moduleCard'],
      ..._listValues(response, const ['cards', 'module_cards', 'moduleCards']),
      ..._listValues(data, const ['cards', 'module_cards', 'moduleCards']),
    ];
    for (final value in nestedCards) {
      if (value is Map) {
        final card = Map<String, dynamic>.from(value);
        final raw = card['visual_sections'] ?? card['visualSections'];
        final type = (card['type'] ?? card['visual_type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (raw is List &&
            (type == 'visual_packing_checklist' ||
                card['visual_sections'] is List ||
                card['visualSections'] is List)) {
          return _normalizePackingCard(card, response, raw, fallback: data);
        }
      }
    }
    return null;
  }

  static Map<String, dynamic> _normalizePackingCard(
    Map<String, dynamic> source,
    Map<String, dynamic> response,
    List<dynamic> sections, {
    Map<String, dynamic>? fallback,
  }) {
    final actions =
        source['actions'] ??
        source['quick_actions'] ??
        source['quickActions'] ??
        fallback?['actions'] ??
        fallback?['quick_actions'] ??
        fallback?['quickActions'] ??
        fallback?['chips'] ??
        response['actions'] ??
        response['quick_actions'] ??
        response['quickActions'] ??
        response['chips'];
    return {
      ...source,
      'type': 'visual_packing_checklist',
      'title':
          source['title'] ??
          fallback?['title'] ??
          response['title'] ??
          'Carry-on Packing Checklist',
      'subtitle':
          source['subtitle'] ??
          fallback?['subtitle'] ??
          response['subtitle'] ??
          '',
      'visual_sections': sections,
      if (actions is List) 'actions': actions,
    };
  }

  static List<dynamic> _listValues(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    final values = <dynamic>[];
    for (final key in keys) {
      final raw = source[key];
      if (raw is List) values.addAll(raw);
    }
    return values;
  }

  static bool _hasStyleBoards(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) => [
    response['style_boards'],
    response['rendered_boards'],
    response['outfits'],
    data['style_boards'],
    data['rendered_boards'],
    data['outfits'],
  ].any(_hasList);

  static bool _hasStyleVisualPayload(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) {
    return _hasStyleBoards(response, data) ||
        _hasList(response['visual_directions']) ||
        _hasList(data['visual_directions']) ||
        _hasList(response['visualDirections']) ||
        _hasList(data['visualDirections']) ||
        AhviVisualBoard.isVisualBoard(response) ||
        response['visual_board'] is Map ||
        response['visualBoard'] is Map ||
        data['visual_board'] is Map ||
        data['visualBoard'] is Map;
  }

  static bool _isCalendarPlan(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) {
    final values = [
      response['visual_type'],
      response['type'],
      response['intent'],
      data['visual_type'],
      data['type'],
      data['intent'],
    ].map((value) => value.toString().toLowerCase());
    return values.any(
      (value) =>
          value == 'calendar_plan' ||
          value == 'tomorrow_prep' ||
          value == 'plan_pack',
    );
  }

  static bool _hasCards(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) => [
    response['card'],
    response['moduleCard'],
    response['cards'],
    response['module_cards'],
    data['card'],
    data['cards'],
    data['module_cards'],
  ].any((value) => value is Map || _hasList(value));

  static bool _isModuleResponse(
    Map<String, dynamic> response,
    Map<String, dynamic> data,
  ) {
    final type = _firstText([response['type'], data['type']]).toLowerCase();
    final module = _firstText([
      response['module'],
      response['domain'],
      data['module'],
      data['domain'],
    ]).toLowerCase();
    return type == 'module_response' ||
        type == 'module_card' ||
        const {
          'calendar',
          'planner',
          'diet',
          'fitness',
          'skincare',
          'medi',
          'bills',
          'medicine',
        }.contains(module);
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static bool _hasList(dynamic value) => value is List && value.isNotEmpty;
}
