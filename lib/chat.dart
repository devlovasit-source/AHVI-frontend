import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/bills_page.dart' as bills_page;
import 'package:myapp/calendar.dart' as calendar_page;
import 'package:myapp/daily_wear.dart' as daily_wear_page;
import 'package:myapp/medi_tracker.dart' as medi_tracker_page;
import 'package:myapp/app_localizations.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/feature/chat/widgets/blocks/ahvi_block_renderer.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/services/ahvi_speech_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/skincare.dart' as skincare_page;
import 'package:myapp/fitness_page.dart' as fitness_page;
import 'package:myapp/diet_page.dart' as diet_page;
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';
import 'package:myapp/widgets/ahvi_visual_board.dart';
import 'package:provider/provider.dart';

class _SavedBoardCategory {
  final String key;
  final String label;
  final IconData icon;

  const _SavedBoardCategory(this.key, this.label, this.icon);
}

const List<_SavedBoardCategory> _savedBoardCategories = [
  _SavedBoardCategory('party_looks', 'Party Looks', Icons.celebration_rounded),
  _SavedBoardCategory('office_fits', 'Office Fits', Icons.work_outline_rounded),
  _SavedBoardCategory('vacation', 'Vacation', Icons.flight_takeoff_rounded),
  _SavedBoardCategory('occasion', 'Occasion', Icons.diamond_outlined),
  _SavedBoardCategory(
    'everything_else',
    'Everything Else',
    Icons.auto_awesome_rounded,
  ),
  _SavedBoardCategory('custom', 'Create Your Own Board', Icons.add_rounded),
];

_SavedBoardCategory _suggestSavedBoardCategory(Map<String, dynamic> board) {
  final text = [
    board['occasion'],
    board['title'],
    board['style_direction'],
    board['vibe'],
    board['prompt'],
    board['prompt_interpretation'],
  ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
  if (RegExp(
    r'\b(party|date|cocktail|rave|club|rooftop|bar)\b',
  ).hasMatch(text)) {
    return _savedBoardCategories[0];
  }
  if (RegExp(r'\b(office|work|meeting|client|interview)\b').hasMatch(text)) {
    return _savedBoardCategories[1];
  }
  if (RegExp(r'\b(travel|airport|vacation|holiday|trip)\b').hasMatch(text)) {
    return _savedBoardCategories[2];
  }
  if (RegExp(
    r'\b(wedding|event|festival|ceremony|occasion)\b',
  ).hasMatch(text)) {
    return _savedBoardCategories[3];
  }
  return _savedBoardCategories[4];
}

String _savedCategoryOccasion(_SavedBoardCategory category) {
  switch (category.key) {
    case 'party_looks':
      return 'Party';
    case 'office_fits':
      return 'Office';
    case 'vacation':
      return 'Vacation';
    case 'occasion':
      return 'Occasion';
    case 'everything_else':
      return 'Everything Else';
    default:
      return category.label;
  }
}

Future<_SavedBoardCategory?> _showSaveBoardPicker(
  BuildContext context,
  _SavedBoardCategory suggested,
) {
  final t = context.themeTokens;
  return showModalBottomSheet<_SavedBoardCategory>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save to board',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Suggested: ${suggested.label}',
              style: TextStyle(color: t.mutedText, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final category in _savedBoardCategories)
              ListTile(
                dense: true,
                leading: Icon(category.icon, color: t.accent.primary),
                title: Text(
                  category.label,
                  style: TextStyle(color: t.textPrimary),
                ),
                trailing: category.key == suggested.key
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: t.accent.secondary,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(category),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _showCustomBoardNameDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Create board'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Board name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

String _generatedSavedBoardTitle(
  Map<String, dynamic> board,
  Map<String, Map<String, dynamic>> slotted,
  _SavedBoardCategory category,
) {
  final explicit = (board['title'] ?? board['name'] ?? '').toString().trim();
  final lowerExplicit = explicit.toLowerCase();
  if (explicit.isNotEmpty &&
      lowerExplicit != 'hero look' &&
      lowerExplicit != 'saved look') {
    return explicit;
  }
  final palette = (board['palette'] is Iterable)
      ? (board['palette'] as Iterable)
            .map((e) => e.toString())
            .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '')
      : (board['color'] ?? board['color_story'] ?? '').toString();
  final top = slotted.values
      .map((it) => (it['name'] ?? it['label'] ?? '').toString())
      .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
  final mood = (board['style_direction'] ?? board['vibe'] ?? '').toString();
  final seed = [
    palette,
    mood,
    top,
  ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');
  final words = seed
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .take(2)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  final suffix = category.key == 'vacation'
      ? 'Easy Layers'
      : category.key == 'office_fits'
      ? 'Office Look'
      : category.key == 'party_looks'
      ? 'Edit'
      : 'Look';
  return [if (words.isNotEmpty) words, suffix].join(' ');
}

String _uniqueSavedBoardTitle(String base, Set<String> existing) {
  final clean = base.trim().isEmpty ? 'Saved Look' : base.trim();
  final lowerExisting = existing.map((e) => e.toLowerCase()).toSet();
  if (!lowerExisting.contains(clean.toLowerCase())) return clean;
  var i = 2;
  while (lowerExisting.contains('$clean $i'.toLowerCase())) {
    i++;
  }
  return '$clean $i';
}

Map<String, List<String>> _getChipsByModule(BuildContext context) => {
  'style': [
    AppLocalizations.t(context, 'intent_style_s1'),
    AppLocalizations.t(context, 'intent_style_s2'),
    AppLocalizations.t(context, 'intent_style_s3'),
  ],
  'organize': [
    AppLocalizations.t(context, 'intent_organize_s1'),
    AppLocalizations.t(context, 'intent_organize_s2'),
    AppLocalizations.t(context, 'intent_organize_s3'),
    AppLocalizations.t(context, 'intent_organize_s4'),
    AppLocalizations.t(context, 'intent_organize_s5'),
    AppLocalizations.t(context, 'intent_organize_s6'),
    AppLocalizations.t(context, 'intent_organize_s7'),
    AppLocalizations.t(context, 'intent_organize_s8'),
  ],
  'plan': [
    AppLocalizations.t(context, 'intent_prepare_s1'),
    AppLocalizations.t(context, 'intent_prepare_s2'),
    AppLocalizations.t(context, 'intent_prepare_s3'),
  ],
};

class _ChatMessage {
  final String text;
  final bool isMe;
  final bool isGreeting;
  final List<dynamic> chips;
  final List<AhviResponseBlock> blocks;
  final String? boardId;
  final String? packId;
  final _LocalResponse? local;
  // Visual outfit board cards from backend.
  // Each card: { id, title, items: [{ name, image_url, masked_url, color, ... }], ... }
  final List<dynamic> cards;
  final AhviVisualBoard? visualBoard;
  final AhviModuleCard? moduleCard;
  final List<Map<String, dynamic>> moduleCards;
  _ChatMessage({
    required this.text,
    required this.isMe,
    this.isGreeting = false,
    this.chips = const [],
    this.blocks = const [],
    this.boardId,
    this.packId,
    this.local,
    this.cards = const [],
    this.visualBoard,
    this.moduleCard,
    this.moduleCards = const [],
  });

  // ── Persistence (for chat history) ────────────────────────────────────
  // `local` (_LocalResponse) is a hardcoded static template keyed by chip
  // text in the `_local` map — we don't serialize the object itself, we
  // just remember its lookup key and re-resolve it from `_local` on load.
  String? get _localLookupKey {
    if (local == null) return null;
    for (final entry in _local.entries) {
      if (identical(entry.value, local)) return entry.key;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'isMe': isMe,
    'chips': chips,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'boardId': boardId,
    'packId': packId,
    'cards': cards,
    'visualBoard': visualBoard?.toJson(),
    'moduleCard': moduleCard?.toJson(),
    'moduleCards': moduleCards,
    'localKey': _localLookupKey,
  };

  factory _ChatMessage.fromJson(Map<String, dynamic> j) {
    final localKey = j['localKey'] as String?;
    return _ChatMessage(
      text: (j['text'] ?? '').toString(),
      isMe: j['isMe'] == true,
      chips: (j['chips'] as List?) ?? const [],
      blocks:
          (j['blocks'] as List?)
              ?.map(
                (b) => AhviResponseBlock.fromJson(
                  Map<String, dynamic>.from(b as Map),
                ),
              )
              .toList() ??
          const [],
      boardId: j['boardId'] as String?,
      packId: j['packId'] as String?,
      cards: (j['cards'] as List?) ?? const [],
      visualBoard: j['visualBoard'] != null
          ? AhviVisualBoard.fromJson(
              Map<String, dynamic>.from(j['visualBoard'] as Map),
            )
          : null,
      moduleCard: j['moduleCard'] != null
          ? AhviModuleCard.fromJson(
              Map<String, dynamic>.from(j['moduleCard'] as Map),
            )
          : null,
      moduleCards:
          (j['moduleCards'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      local: localKey != null ? _local[localKey] : null,
    );
  }
}

bool _isStyleMoreChip(String value) {
  final text = value.toLowerCase().trim();
  return text == 'more looks' ||
      text == 'more options' ||
      text == 'next best options' ||
      text == 'next best' ||
      text == 'try different shoes' ||
      text.contains('more look') ||
      text.contains('more option') ||
      text.contains('next option') ||
      text.contains('different shoe') ||
      text.contains('different footwear');
}

bool _isShowClosestChip(String value) {
  final text = value.toLowerCase().trim();
  return text == 'show closest option' ||
      text == 'show_closest_option' ||
      text == 'show closest' ||
      text == 'closest option';
}

bool _isStyleActionChip(String value) {
  final text = value.toLowerCase().trim();
  return text == 'use my wardrobe' ||
      text == 'use wardrobe' ||
      text == 'use_wardrobe' ||
      text == 'from my wardrobe' ||
      text == 'show visual inspiration' ||
      text == 'visual inspiration' ||
      text == 'show_visual_inspiration' ||
      text == 'find missing pieces' ||
      text == 'missing pieces' ||
      text == 'find_missing_pieces' ||
      text == 'find this';
}

String _stripStyleActionPrefix(String value) {
  var text = value.trim();
  final lower = text.toLowerCase();
  for (final prefix in [
    'use my wardrobe for ',
    'use wardrobe for ',
    'from my wardrobe for ',
    'show visual inspiration for ',
    'visual inspiration for ',
    'find missing pieces for ',
    'missing pieces for ',
    'find this for ',
  ]) {
    if (lower.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
      break;
    }
  }
  return text;
}

bool _isPlanPackRequest(String value) {
  final text = value.toLowerCase().trim();
  final asksForPacking =
      text.contains('pack') ||
      text.contains('packing') ||
      text.contains('carry-on') ||
      text.contains('carry on');
  final tripContext =
      text.contains('trip') ||
      text.contains('travel') ||
      text.contains('beach') ||
      text.contains('vacation') ||
      text.contains('destination') ||
      text.contains('goa');
  final prepContext =
      text.contains('prep') ||
      text.contains('prepare') ||
      text.contains('checklist') ||
      text.contains('plan');
  final eventPlan =
      text.contains('camping') ||
      text.contains('goa trip') ||
      text.contains('birthday party') ||
      text.contains('plan a birthday');
  return (asksForPacking && (tripContext || prepContext)) ||
      eventPlan ||
      (prepContext &&
          (text.contains('camping') ||
              text.contains('trip') ||
              text.contains('travel') ||
              text.contains('party')));
}

String _styleChipQuery(String value) {
  switch (value.toLowerCase().trim()) {
    case 'office':
      return 'office outfit';
    case 'casual':
      return 'casual outfit';
    case 'date':
      return 'date night outfit';
    case 'party':
      return 'party outfit';
    case 'travel':
      return 'airport travel outfit';
    case 'workout':
      return 'workout outfit';
  }
  return value;
}

String _chipLabel(dynamic chip) => AhviChip.fromDynamic(chip).label;

String _chipValue(dynamic chip) => AhviChip.fromDynamic(chip).value;

bool _looksLikeStyleClarification(String value) {
  final t = value.toLowerCase();
  return t.contains('what are we dressing') ||
      t.contains('what are you dressing for') ||
      t.contains('pick an occasion');
}

bool _isBoardActionPhrase(String value) {
  final t = value.toLowerCase().trim();
  return t.contains('another look') ||
      t.contains('more looks') ||
      t.contains('show me another') ||
      t.contains('different look') ||
      t.startsWith('shuffle');
}

List<dynamic> _extractStyleBoardsFromResponse(Map<String, dynamic> response) {
  if ((response['type'] ?? '').toString().toLowerCase() == 'module_response') {
    return const [];
  }
  final data = response['data'] is Map
      ? Map<String, dynamic>.from(response['data'] as Map)
      : <String, dynamic>{};

  for (final value in [
    response['style_boards'],
    data['outfits'],
    data['rendered_boards'],
  ]) {
    final boards = _mapDynamicBoards(value);
    if (boards.isNotEmpty) return boards;
  }
  return const [];
}

List<dynamic> _mapDynamicBoards(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _blockText(dynamic value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? fallback : text;
}

String? _blockNullableText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? null : text;
}

List<String> _blockStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty && item != 'null')
      .toList(growable: false);
}

List<Map<String, dynamic>> _moduleCardsFromResponse(
  Map<String, dynamic> response,
) {
  final out = <Map<String, dynamic>>[];
  final card = response['card'];
  if (card is Map) out.add(Map<String, dynamic>.from(card));
  final cards = response['cards'];
  if (cards is List) {
    out.addAll(
      cards.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
    );
  }
  if (out.isEmpty && _looksLikeModuleCards(response)) {
    out.add(response);
  }
  return out;
}

bool _looksLikeModuleCards(Map<String, dynamic> response) {
  if ((response['response_type'] ?? '').toString() == 'module_card') {
    return true;
  }
  final type = (response['type'] ?? '').toString().toLowerCase();
  final intent = (response['intent'] ?? '').toString().toLowerCase();
  final module = (response['module'] ?? response['domain'] ?? '')
      .toString()
      .toLowerCase();
  if (type.contains('checklist') ||
      type == 'module_response' ||
      type == 'module_card' ||
      intent == 'plan_pack' ||
      module == 'planner' ||
      module == 'calendar' ||
      module == 'bills' ||
      module == 'medicines' ||
      module == 'meals' ||
      module == 'workout' ||
      module == 'skincare') {
    return true;
  }
  return false;
}

List<dynamic> _mergeStyleBoards(
  List<dynamic> current,
  List<dynamic> incoming, {
  int maxBoards = 6,
}) {
  final merged = <Map<String, dynamic>>[];
  final seen = <String>{};

  void add(dynamic value) {
    if (merged.length >= maxBoards || value is! Map) return;
    final board = Map<String, dynamic>.from(value);
    final signature = _styleBoardSignature(board);
    if (signature.isEmpty || !seen.add(signature)) return;
    merged.add(board);
  }

  for (final board in current) {
    add(board);
  }
  for (final board in incoming) {
    add(board);
  }
  return merged;
}

List<AhviResponseBlock> _replaceStyleBoardBlock(
  List<AhviResponseBlock> blocks,
  List<dynamic> boards,
) {
  if (blocks.isEmpty) return blocks;
  var replaced = false;
  final next = blocks
      .map((block) {
        if (block.type != AhviBlockType.styleBoards) return block;
        replaced = true;
        return AhviResponseBlock(
          type: AhviBlockType.styleBoards,
          data: {'boards': boards},
        );
      })
      .toList(growable: true);
  if (!replaced && boards.isNotEmpty) {
    next.add(
      AhviResponseBlock(
        type: AhviBlockType.styleBoards,
        data: {'boards': boards},
      ),
    );
  }
  return next;
}

List<String> _styleBoardSignatures(List<dynamic> boards) {
  return boards
      .whereType<Map>()
      .map((board) => _styleBoardSignature(Map<String, dynamic>.from(board)))
      .where((signature) => signature.isNotEmpty)
      .toList();
}

String _styleBoardSignature(Map<String, dynamic> board) {
  final names =
      _styleBoardItems(board)
          .map(
            (item) =>
                (item['id'] ??
                        item[r'$id'] ??
                        item['item_id'] ??
                        item['image_id'] ??
                        item['name'] ??
                        item['label'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase(),
          )
          .where((value) => value.isNotEmpty)
          .toList()
        ..sort();

  if (names.isNotEmpty) return names.join('|');
  return (board['id'] ?? board['title'] ?? board['name'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
}

List<Map<String, dynamic>> _styleBoardItems(Map<String, dynamic> board) {
  final out = <Map<String, dynamic>>[];
  void addList(dynamic value) {
    if (value is! List) return;
    out.addAll(
      value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
    );
  }

  addList(board['items']);
  addList(board['accessories']);
  for (final key in [
    'top',
    'bottom',
    'dress',
    'shoes',
    'footwear',
    'outerwear',
  ]) {
    final value = board[key];
    if (value is Map) out.add(Map<String, dynamic>.from(value));
  }
  return out;
}

enum _RespType { outfits, plan, card, checklist }

class _LocalResponse {
  final _RespType type;
  final String intro;
  final List<_Outfit> outfits;
  final List<_Plan> plans;
  final _CardData? card;
  const _LocalResponse({
    required this.type,
    required this.intro,
    this.outfits = const [],
    this.plans = const [],
    this.card,
  });
}

class _Outfit {
  final String name;
  final List<String> tags;
  final String image;
  final String description;
  bool saved;
  _Outfit(
    this.name,
    this.tags,
    this.image, {
    this.description = '',
    this.saved = false,
  });
}

class _Plan {
  final String title;
  final List<String> items;
  const _Plan(this.title, this.items);
}

class _CardData {
  final String title;
  final IconData icon;
  final List<_CardRow> rows;
  final String footer;
  final String pageKey;
  const _CardData(this.title, this.icon, this.rows, this.footer, this.pageKey);
}

class _CardRow {
  final bool done;
  final String main;
  final String sub;
  final String tag;
  const _CardRow(this.done, this.main, this.sub, this.tag);
}

IconData _moduleIconFor(String key) {
  switch (key) {
    case 'medication':
      return Icons.medication_rounded;
    case 'restaurant':
      return Icons.restaurant_menu_rounded;
    case 'receipt':
      return Icons.receipt_long_rounded;
    case 'fitness':
      return Icons.fitness_center_rounded;
    case 'event':
      return Icons.event_note_rounded;
    case 'spa':
      return Icons.spa_rounded;
    default:
      return Icons.dashboard_rounded;
  }
}

/// Parse a backend `module_card` envelope into a card the chat already
/// knows how to render (via _localView). Returns null for other responses.
_LocalResponse? _moduleCardFromResponse(Map<String, dynamic> response) {
  if ((response['response_type'] ?? '').toString() != 'module_card')
    return null;
  final card = response['card'];
  if (card is! Map) return null;
  final rows = <_CardRow>[];
  final rawRows = card['rows'];
  if (rawRows is List) {
    for (final r in rawRows) {
      if (r is! Map) continue;
      rows.add(
        _CardRow(
          r['done'] == true,
          (r['main'] ?? '').toString(),
          (r['sub'] ?? '').toString(),
          (r['tag'] ?? '').toString(),
        ),
      );
    }
  }
  final title = (card['title'] ?? 'Summary').toString();
  return _LocalResponse(
    type: _RespType.card,
    intro: (response['message_text'] ?? response['message'] ?? '').toString(),
    card: _CardData(
      title,
      _moduleIconFor((card['icon'] ?? '').toString()),
      rows,
      'Open $title',
      (card['open_key'] ?? '').toString(),
    ),
  );
}

final _local = <String, _LocalResponse>{
  'What should I wear today?': _LocalResponse(
    type: _RespType.outfits,
    intro:
        "Based on today's 14°C partly cloudy weather, here are 3 looks curated for you:",
    outfits: [
      _Outfit(
        'Layered Minimal',
        ['Casual', 'Today'],
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'A light knit layered over a crisp tee with slim trousers. Comfortable yet polished for a cool day.',
      ),
      _Outfit(
        'Smart Casual',
        ['Office', 'Versatile'],
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'Tailored chinos paired with a structured shirt. Effortless transition from desk to dinner.',
      ),
      _Outfit(
        'Street Edit',
        ['Urban', 'Fresh'],
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'Wide-leg joggers with an oversized graphic tee and clean sneakers. Relaxed city energy.',
      ),
    ],
  ),
  'Build a rooftop party outfit': _LocalResponse(
    type: _RespType.outfits,
    intro:
        "Rooftop energy calls for elevated looks. Here's what works perfectly:",
    outfits: [
      _Outfit(
        'Evening Glow',
        ['Party', 'Night'],
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'A sleek satin slip dress with strappy heels. Warm-toned accessories complete the golden-hour vibe.',
      ),
      _Outfit(
        'Rooftop Chic',
        ['Elevated', 'Cool'],
        'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'Tailored wide-leg trousers with a cropped blazer. Sharp, confident and built for the skyline.',
      ),
      _Outfit(
        'Bold Statement',
        ['Trendy', 'Standout'],
        'https://images.unsplash.com/photo-1469334031218-e382a71b716b?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'A vibrant co-ord set that commands attention. Minimal jewellery lets the colour do the talking.',
      ),
    ],
  ),
  'Show trending casual looks': _LocalResponse(
    type: _RespType.outfits,
    intro:
        'Quiet luxury and clean lines are having a moment. Top trending now:',
    outfits: [
      _Outfit(
        'Quiet Luxury',
        ['Trending', 'Minimal'],
        'https://images.unsplash.com/photo-1538805060514-97d9cc17730c?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'Cream wide-leg trousers with a fine-knit cardigan. Understated elegance that speaks volumes.',
      ),
      _Outfit(
        'Soft Tones',
        ['Casual', 'Neutral'],
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'Dusty beige linen set with white sneakers. Easy, breathable and endlessly wearable.',
      ),
      _Outfit(
        'Classic Ease',
        ['Everyday', 'Fresh'],
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=220&h=260&fit=crop&crop=top&auto=format',
        description:
            'A white oversized button-down tucked into straight jeans. The perfect no-fuss uniform.',
      ),
    ],
  ),
  'Plan a 3-day Goa trip': _LocalResponse(
    type: _RespType.checklist,
    intro: "Here's your expert-curated 3-day Goa itinerary:",
    plans: [
      _Plan('Day 1 — Arrival & North Goa', [
        '☀️ Arrive & check in',
        '🏖️ Baga Beach',
        '🍽️ Dinner at Thalassa',
      ]),
      _Plan('Day 2 — Culture & South Goa', [
        '🏛️ Old Goa churches',
        '🚗 Drive to Palolem',
        '🌅 Sunset at Cabo de Rama',
      ]),
      _Plan('Day 3 — Relax & Depart', [
        '🧘 Morning yoga',
        '🛍️ Anjuna flea market',
        '✈️ Airport by 4pm',
      ]),
    ],
  ),
  'Pack for business travel': _LocalResponse(
    type: _RespType.checklist,
    intro: 'Smart packing list — nothing missing, nothing extra:',
    plans: [
      _Plan('👔 Clothing', ['2× formal shirts', '1× blazer', '2× trousers']),
      _Plan('💼 Work Essentials', [
        'Laptop + charger',
        'Notebook + pens',
        'Portable battery',
      ]),
      _Plan('🧴 Toiletries', [
        'Moisturiser, deodorant',
        'Toothbrush + paste',
        'Face wash + razor',
      ]),
    ],
  ),
  'Create a wedding checklist': _LocalResponse(
    type: _RespType.checklist,
    intro: 'Complete wedding checklist — 24 items across 4 categories:',
    plans: [
      _Plan('📆 6–12 Months Before', [
        'Set budget & guest list',
        'Book venue & caterer',
        'Book photographer',
      ]),
      _Plan('🎨 3–6 Months Before', [
        'Send invitations',
        'Finalise menu',
        'Book hair & makeup',
      ]),
      _Plan('✅ Week Of', [
        'Final dress fitting',
        'Prepare wedding day kit',
        'Rest & enjoy 🎉',
      ]),
    ],
  ),
  // The Today's meals / Pending bills / Today's workout / Upcoming events /
  // Today's events / Morning skincare chips are no longer demo cards — they
  // all route to the backend's module_card endpoint and render the user's
  // real Appwrite data via _moduleCardFromResponse, alongside My medicines.
};

// ── Persistent chat session model ──────────────────────────────────────────

class _ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  final List<Map<String, String>>
  history; // [{role, content}] — sent to backend as context
  final List<_ChatMessage>
  messages; // rich UI messages (boards, cards, chips, images)

  _ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.history,
    List<_ChatMessage>? messages,
  }) : messages = messages ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'history': history,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory _ChatSession.fromJson(Map<String, dynamic> j) => _ChatSession(
    id: j['id'] as String,
    title: j['title'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    history: (j['history'] as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList(),
    // Older saved sessions won't have `messages` — fall back to an empty
    // list, which _loadSession() rebuilds from `history` as plain text.
    messages:
        (j['messages'] as List?)
            ?.map(
              (e) => _ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        const [],
  );
}

const _kSessionsKey = 'ahvi_chat_sessions';

class ChatScreen extends StatefulWidget {
  final String moduleContext;
  final String? initialPrompt;
  final bool showBackButton;
  const ChatScreen({
    super.key,
    this.moduleContext = 'style',
    this.initialPrompt,
    this.showBackButton = true,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<_ChatMessage> _messages = [];
  final List<Map<String, String>> _chatHistory = [];
  String _runningMemory = '';
  // Persisted style-pairing session — kept across follow-ups so anchor/route/
  // persona survive "use my wardrobe" / "show visual inspiration" / etc.
  Map<String, dynamic>? _lastStyleContext;
  // A rendered board/cards response resolves any pending occasion
  // clarification; later board actions must not be sent as clarification answers.
  bool _clarificationResolvedByCards = false;
  bool _isTyping = false;
  bool _lastRequestWasWardrobe = false;
  String _userName = 'User';
  final Map<String, List<List<bool>>> _checklistChecksByTitle = {};
  final Map<String, List<List<String>>> _checklistItemsByTitle = {};
  final Map<String, List<TextEditingController>> _checklistAddCtrlsByTitle = {};
  final Map<String, bool> _checklistSavedByTitle = {};
  Map<String, dynamic> _lastPlanPackContext = const {};

  // ── Voice ──────────────────────────────────────────────────────────────────
  bool _isListening = false;

  // ── History ────────────────────────────────────────────────────────────────
  List<_ChatSession> _sessions = [];
  late String _currentSessionId;
  bool _greetingAdded = false;
  String get _module => widget.moduleContext.toLowerCase().trim() == 'prepare'
      ? 'plan'
      : widget.moduleContext.toLowerCase().trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    // If we're opening fresh (no initialPrompt forcing a new topic), resume
    // the most recent conversation automatically instead of starting empty.
    _loadSessions(autoResume: widget.initialPrompt == null);

    // Keyboard వచ్చినప్పుడు scroll to bottom
    _chatFocusNode.addListener(() {
      if (_chatFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_greetingAdded) {
      _greetingAdded = true;
      _fetchUser();
      _messages.add(_ChatMessage(text: '', isMe: false, isGreeting: true));
      final pendingPrompt = widget.initialPrompt?.trim();
      if (pendingPrompt != null && pendingPrompt.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sendMessage(pendingPrompt);
        });
      }
    }
  }

  Future<void> _fetchUser() async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final user = await appwrite.getCurrentUser();
    if (user != null && mounted) {
      setState(
        () => _userName = user.name.isNotEmpty
            ? user.name.split(' ').first
            : 'Stylist',
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await AhviSpeechService.instance.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (mounted) setState(() => _isListening = true);

    await AhviSpeechService.instance.start(
      onText: (text) {
        if (!mounted) return;

        setState(() {
          _chatController.text = text;
          _chatController.selection = TextSelection.fromPosition(
            TextPosition(offset: _chatController.text.length),
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (mounted && !AhviSpeechService.instance.isListening) {
      setState(() => _isListening = false);
    }
  }

  // ── Session persistence ────────────────────────────────────────────────────

  Future<void> _loadSessions({bool autoResume = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSessionsKey);
    if (raw == null) return;
    try {
      final List decoded = jsonDecode(raw) as List;
      final loaded =
          decoded
              .map((e) => _ChatSession.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _sessions = loaded;
        if (autoResume && loaded.isNotEmpty && !_greetingAdded) {
          final last = loaded.first;
          _currentSessionId = last.id;
          _chatHistory
            ..clear()
            ..addAll(last.history);
          _messages
            ..clear()
            ..add(_ChatMessage(text: '', isMe: false, isGreeting: true));
          if (last.messages.isNotEmpty) {
            _messages.addAll(last.messages);
          } else {
            for (final h in last.history) {
              _messages.add(
                _ChatMessage(
                  text: h['content'] ?? '',
                  isMe: h['role'] == 'user',
                ),
              );
            }
          }
          _greetingAdded = true; // stop didChangeDependencies re-adding it
          _fetchUser();
        }
      });
    } catch (_) {}
  }

  Future<void> _saveCurrentSession() async {
    if (_chatHistory.isEmpty) return; // nothing to persist yet
    final prefs = await SharedPreferences.getInstance();

    // Build a readable title from the first user message
    final firstUser = _chatHistory.firstWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': 'Chat'},
    );
    final title = (firstUser['content'] ?? 'Chat').length > 40
        ? '${firstUser['content']!.substring(0, 40)}…'
        : firstUser['content']!;

    // Greeting bubble is re-added on load, so skip persisting it here.
    final richMessages = _messages.where((m) => !m.isGreeting).toList();

    final existing = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (existing >= 0) {
      _sessions[existing].history
        ..clear()
        ..addAll(_chatHistory);
      _sessions[existing].messages
        ..clear()
        ..addAll(richMessages);
      _sessions[existing].title = title;
    } else {
      _sessions.insert(
        0,
        _ChatSession(
          id: _currentSessionId,
          title: title,
          createdAt: DateTime.now(),
          history: List.from(_chatHistory),
          messages: List.from(richMessages),
        ),
      );
    }

    await prefs.setString(
      _kSessionsKey,
      jsonEncode(_sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _deleteSession(String id) async {
    setState(() => _sessions.removeWhere((s) => s.id == id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSessionsKey,
      jsonEncode(_sessions.map((s) => s.toJson()).toList()),
    );
  }

  void _startNewChat() {
    _scaffoldKey.currentState
        ?.closeDrawer(); // close drawer only, not the screen
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages
        ..clear()
        ..add(_ChatMessage(text: '', isMe: false, isGreeting: true));
      _chatHistory.clear();
      _runningMemory = '';
      _lastStyleContext = null;
    });
    _scrollToBottom();
  }

  void _loadSession(_ChatSession session) {
    _scaffoldKey.currentState
        ?.closeDrawer(); // close drawer only, not the screen
    setState(() {
      _currentSessionId = session.id;
      _chatHistory
        ..clear()
        ..addAll(session.history);
      _messages
        ..clear()
        ..add(_ChatMessage(text: '', isMe: false, isGreeting: true));
      if (session.messages.isNotEmpty) {
        // Full-fidelity restore: boards, cards, chips, images all come back.
        _messages.addAll(session.messages);
      } else {
        // Backward compatibility for sessions saved before rich-message
        // persistence existed — falls back to plain text bubbles.
        for (final h in session.history) {
          _messages.add(
            _ChatMessage(text: h['content'] ?? '', isMe: h['role'] == 'user'),
          );
        }
      }
      _runningMemory = '';
      _lastStyleContext = null;
    });
    _scrollToBottom();
  }

  Map<String, dynamic>? _extractLastStyleContext(
    Map<String, dynamic> response,
  ) {
    final direct = response['last_style_context'];
    if (direct is Map && direct.isNotEmpty) {
      return Map<String, dynamic>.from(direct);
    }
    final data = response['data'];
    if (data is Map) {
      final fromData = data['last_style_context'];
      if (fromData is Map && fromData.isNotEmpty) {
        return Map<String, dynamic>.from(fromData);
      }
    }
    return null;
  }

  void _handleChipTap(String chip) {
    const styleModules = {'style', 'wardrobe', 'daily_wear'};
    if (styleModules.contains(_module) && _isStyleMoreChip(chip)) {
      _requestMoreStyleBoards(chip);
      return;
    }
    final resolvedChip = styleModules.contains(_module)
        ? _resolveStyleActionChipQuery(chip)
        : chip;
    final local = _local[chip];
    if (local == null) return _sendMessage(resolvedChip, chip);
    setState(() {
      _messages.add(_ChatMessage(text: chip, isMe: true));
      _messages.add(_ChatMessage(text: local.intro, isMe: false, local: local));
    });
    _scrollToBottom();
  }

  String _resolveStyleActionChipQuery(String value) {
    if (!_isStyleActionChip(value)) return value;
    final baseIntent = _lastStyleActionBaseIntent();
    if (baseIntent.isEmpty) return value;
    final text = value.toLowerCase().trim();
    if (text == 'use my wardrobe' ||
        text == 'use wardrobe' ||
        text == 'use_wardrobe' ||
        text == 'from my wardrobe') {
      return 'Use my wardrobe for $baseIntent';
    }
    if (text == 'find missing pieces' ||
        text == 'missing pieces' ||
        text == 'find_missing_pieces' ||
        text == 'find this') {
      return 'Find missing pieces for $baseIntent';
    }
    if (text == 'show visual inspiration' ||
        text == 'visual inspiration' ||
        text == 'show_visual_inspiration') {
      return 'Show visual inspiration for $baseIntent';
    }
    return value;
  }

  String _lastStyleActionBaseIntent() {
    for (var i = _chatHistory.length - 1; i >= 0; i--) {
      final row = _chatHistory[i];
      if (row['role'] != 'user') continue;
      final text = (row['content'] ?? '').trim();
      if (text.isEmpty || _isShowClosestChip(text) || _isStyleMoreChip(text)) {
        continue;
      }
      if (_isStyleActionChip(text)) continue;
      final stripped = _stripStyleActionPrefix(text);
      if (stripped.isNotEmpty && !_isStyleActionChip(stripped)) {
        return stripped;
      }
    }
    return '';
  }

  Future<void> _requestMoreStyleBoards(String chip) async {
    final sourceIndex = _lastAssistantWithBoardsIndex();
    final sourceCards = sourceIndex == null
        ? const <dynamic>[]
        : _messages[sourceIndex].cards;
    final exclude = _styleBoardSignatures(sourceCards);

    setState(() {
      _messages.add(_ChatMessage(text: chip, isMe: true));
      _chatHistory.add({'role': 'user', 'content': chip});
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final backend = Provider.of<BackendService>(context, listen: false);
      final resolvedPrompt = _lastResolvedStylePrompt();
      final requestPrompt = resolvedPrompt.isNotEmpty ? resolvedPrompt : chip;
      final response = await backend.sendChatQuery(
        requestPrompt,
        'user_$_userName',
        List<Map<String, String>>.from(_chatHistory),
        _runningMemory,
        moduleContext: _module,
        styleAction: chip.toLowerCase().contains('shoe')
            ? 'try_different_shoes'
            : 'more_options',
        action: chip.toLowerCase().contains('shoe')
            ? 'try_different_shoes'
            : 'more_options',
        previousPrompt: resolvedPrompt.isNotEmpty ? resolvedPrompt : null,
        resolvedPrompt: resolvedPrompt.isNotEmpty ? resolvedPrompt : null,
        lastStyleContext: _lastStyleContext,
        excludeStyleSignatures: exclude,
        requestedBoardCount: 3,
      );
      if (!mounted) return;

      final newBoards = _extractStyleBoardsFromResponse(response);
      final parsed = AhviResponse.fromMap(response);
      final mergedBoards = _mergeStyleBoards(
        sourceCards,
        newBoards,
        maxBoards: 6,
      );
      final added = mergedBoards.length > sourceCards.length;
      final rawMessage = response['message'];
      final aiText =
          (response['message_text'] ??
                  (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
                  '')
              .toString()
              .trim();

      setState(() {
        if (sourceIndex != null && added) {
          final old = _messages[sourceIndex];
          _messages[sourceIndex] = _ChatMessage(
            text: old.text,
            isMe: old.isMe,
            isGreeting: old.isGreeting,
            chips: old.chips,
            blocks: _replaceStyleBoardBlock(old.blocks, mergedBoards),
            boardId: old.boardId,
            packId: old.packId,
            local: old.local,
            cards: mergedBoards,
            visualBoard: old.visualBoard,
            moduleCard: old.moduleCard,
            moduleCards: old.moduleCards,
          );
          _messages.add(
            _ChatMessage(
              text: aiText.isNotEmpty ? aiText : 'I added fresh style options.',
              isMe: false,
              chips: parsed.chips.map((chip) => chip.toJson()).toList(),
            ),
          );
        } else {
          _messages.add(
            _ChatMessage(
              text: "I've shown the strongest options from this wardrobe.",
              isMe: false,
              chips: parsed.chips.map((chip) => chip.toJson()).toList(),
            ),
          );
        }
        _chatHistory.add({
          'role': 'assistant',
          'content': added
              ? (aiText.isNotEmpty ? aiText : 'I added fresh style options.')
              : "I've shown the strongest options from this wardrobe.",
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _ChatMessage(
            text: '${AppLocalizations.t(context, 'chat_error_prefix')}: $e',
            isMe: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTyping = false);
      // Save regardless of success/failure so the user message (and any
      // error bubble) is never silently lost from history.
      _saveCurrentSession();
      _scrollToBottom();
    }
  }

  int? _lastAssistantWithBoardsIndex() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (!message.isMe && message.cards.isNotEmpty) return i;
    }
    return null;
  }

  void _sendMessage([String? chipText, String? displayText]) async {
    final queryText = chipText ?? _chatController.text.trim();
    final visibleText = displayText ?? queryText;
    if (queryText.isEmpty || visibleText.isEmpty) return;
    _chatController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: visibleText, isMe: true));
      _chatHistory.add({'role': 'user', 'content': visibleText});
      _isTyping = true;
    });
    _scrollToBottom();
    try {
      final backend = Provider.of<BackendService>(context, listen: false);
      const styleModules = {'style', 'wardrobe', 'daily_wear'};
      final isStyleModule = styleModules.contains(_module);
      final backendQueryText = isStyleModule
          ? _styleChipQuery(queryText)
          : queryText;
      final isPlanPackRequest = !isStyleModule && _isPlanPackRequest(queryText);
      final planActionLabels = {
        'open checklist',
        'packing checklist',
        'weather prep',
        'save trip plan',
        'plan outfits',
      };
      final isPlanPackAction = planActionLabels.contains(
        queryText.toLowerCase().trim(),
      );
      final isClosestAction = isStyleModule && _isShowClosestChip(queryText);
      final isBoardActionPhrase = _isBoardActionPhrase(queryText);
      final pendingClarificationPrompt =
          isStyleModule && !isClosestAction && !isBoardActionPhrase
          ? _pendingStyleClarificationPrompt()
          : '';
      final isClarificationAnswer =
          pendingClarificationPrompt.isNotEmpty &&
          visibleText.trim().isNotEmpty;
      final clarificationResolvedPrompt = isClarificationAnswer
          ? '$pendingClarificationPrompt · $visibleText'
          : '';
      final resolvedStylePrompt = isClosestAction
          ? _lastResolvedStylePrompt()
          : '';
      final originalStylePrompt = resolvedStylePrompt.contains('·')
          ? resolvedStylePrompt.split('·').first.trim()
          : resolvedStylePrompt;
      final interpretedOccasion =
          resolvedStylePrompt.toLowerCase().contains('beach') ? 'beach' : null;
      // Only style / wardrobe / daily_wear flows go through /api/text which
      // builds boards. Every other module (home, utilities, fitness, diet,
      // skincare, medi, bills, calendar) goes through the shared module chat
      // which runs a module-aware LLM prompt. Same routing as the AHVI
      // stylist sheet, brought to the ChatScreen so Home/Utilities chats
      // actually return text instead of an empty style response.
      // Style/wardrobe board requests route through /api/module-chat (the
      // validated board path). The homepage is now the summary surface and
      // /api/text only returns style_advice TEXT (no board), so a typed style
      // prompt produced nothing. Closest-option / clarification follow-ups
      // still use /api/text because they depend on its rich style params.
      final bool styleViaText =
          isStyleModule && (isClosestAction || isClarificationAnswer);
      final Map<String, dynamic> response;
      if (styleViaText) {
        response = await backend.sendChatQuery(
          backendQueryText,
          'user_$_userName',
          List<Map<String, String>>.from(_chatHistory),
          _runningMemory,
          moduleContext: _module == 'daily_wear' ? 'style' : _module,
          styleAction: isClosestAction ? 'show_closest_option' : null,
          action: isClosestAction
              ? 'show_closest_option'
              : (isClarificationAnswer ? 'clarification_selected' : null),
          clarification: isClarificationAnswer ? visibleText : null,
          previousPrompt: isClarificationAnswer
              ? pendingClarificationPrompt
              : isClosestAction && originalStylePrompt.isNotEmpty
              ? originalStylePrompt
              : null,
          resolvedPrompt: isClarificationAnswer
              ? clarificationResolvedPrompt
              : isClosestAction && resolvedStylePrompt.isNotEmpty
              ? resolvedStylePrompt
              : null,
          styleContext: isClarificationAnswer
              ? {
                  'original_prompt': pendingClarificationPrompt,
                  'clarification': visibleText,
                  'resolved_prompt': clarificationResolvedPrompt,
                }
              : isClosestAction && resolvedStylePrompt.isNotEmpty
              ? {
                  'original_prompt': originalStylePrompt,
                  'resolved_prompt': resolvedStylePrompt,
                  if (interpretedOccasion != null)
                    'interpreted_occasion': interpretedOccasion,
                }
              : null,
          lastStyleContext: _lastStyleContext,
          showClosestOption: isClosestAction,
          allowClosestOption: isClosestAction,
          closest: isClosestAction,
        );
      } else if (isStyleModule) {
        response = await backend.sendModuleChat(
          domain: _module == 'daily_wear' ? 'style' : _module,
          message: backendQueryText,
          chatHistory: List<Map<String, String>>.from(_chatHistory),
        );
      } else {
        response = await backend.sendModuleChat(
          domain: isPlanPackRequest ? 'planner' : _module,
          message: queryText,
          context: isPlanPackAction ? _lastPlanPackContext : const {},
          chatHistory: List<Map<String, String>>.from(_chatHistory),
        );
      }
      if (!mounted) return;
      if (response['updated_memory'] != null) {
        _runningMemory = response['updated_memory'];
      }
      // Persist style-pairing session context (anchor/route/persona) so the
      // next follow-up keeps it. A new pairing response replaces the old one.
      final lsc = _extractLastStyleContext(response);
      if (lsc != null) _lastStyleContext = lsc;
      final parsedResponse = parseAhviResponse(response);
      final visualBoard = AhviVisualBoard.isVisualBoard(response)
          ? AhviVisualBoard.fromJson(response)
          : null;
      final sharedModuleCard = AhviModuleCard.fromResponse(response);
      final moduleCard = sharedModuleCard == null
          ? _moduleCardFromResponse(response)
          : null;
      final isModuleResponse = _looksLikeModuleCards(response);
      final responseBoards = isModuleResponse
          ? const <dynamic>[]
          : _extractStyleBoardsFromResponse(response);
      // Clarification lifecycle: rendered boards resolve a pending
      // clarification; a fresh clarification response re-arms it.
      final clarificationMsg =
          (response['message_text'] ?? response['message'] ?? '').toString();
      if (responseBoards.isNotEmpty) {
        _clarificationResolvedByCards = true;
      } else if ((response['type'] ?? '').toString().toLowerCase() ==
              'clarification' ||
          _looksLikeStyleClarification(clarificationMsg)) {
        _clarificationResolvedByCards = false;
      }
      final moduleCards = isModuleResponse && sharedModuleCard == null
          ? _moduleCardsFromResponse(response)
          : const <Map<String, dynamic>>[];
      final responseData = response['data'];
      if (responseData is Map &&
          (response['intent'] == 'plan_pack' ||
              response['intent'] == 'open_checklist' ||
              response['intent'] == 'weather_prep' ||
              response['intent'] == 'save_plan')) {
        _lastPlanPackContext = {
          ...Map<String, dynamic>.from(responseData),
          'last_plan_prompt':
              responseData['source_text'] ??
              _lastPlanPackContext['last_plan_prompt'] ??
              queryText,
          'active_plan_prompt':
              responseData['source_text'] ??
              _lastPlanPackContext['active_plan_prompt'] ??
              queryText,
        };
      }
      var aiText = parsedResponse.text.trim().isNotEmpty
          ? parsedResponse.text
          : AppLocalizations.t(context, 'chat_connection_error');
      var customChips = parsedResponse.chips;

      // PATCH 5: STYLE THIS CHIP SAFETY - Replace hard failure message and add actions
      if (aiText.contains("couldn't build a complete style board") ||
          aiText.contains("couldn't build a reliable style board") ||
          aiText.contains("I couldn't build a reliable style board")) {
        aiText =
            "I can match this look with your wardrobe where possible and suggest the missing pieces.";
        customChips = [
          {
            'label': 'Show inspiration anyway',
            'value': 'Show visual inspiration',
          },
          {'label': 'Find missing pieces', 'value': 'Find missing pieces'},
          {'label': 'Add wardrobe item', 'value': 'Add wardrobe item'},
        ];
      }

      final closestEmptyFallback = isClosestAction && responseBoards.isEmpty
          ? "I couldn't build even a closest option from the available wardrobe slots."
          : aiText;
      final duplicateWeakMatch =
          (response['type'] ?? '').toString() == 'weak_match' &&
          _messages.isNotEmpty &&
          !_messages.last.isMe &&
          _messages.last.text.trim() == aiText.trim();
      _chatHistory.add({'role': 'assistant', 'content': closestEmptyFallback});
      setState(() {
        if (duplicateWeakMatch && !isClosestAction) return;
        _messages.add(
          _ChatMessage(
            text: closestEmptyFallback,
            isMe: false,
            chips: customChips,
            blocks: parsedResponse.blocks,
            boardId: parsedResponse.boardId,
            packId: parsedResponse.packId,
            cards: responseBoards,
            visualBoard: visualBoard,
            moduleCard: sharedModuleCard,
            moduleCards: moduleCards,
            local: moduleCard,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          _ChatMessage(
            text: '${AppLocalizations.t(context, 'chat_error_prefix')}: $e',
            isMe: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTyping = false);
      // Save regardless of success/failure so the user message (and any
      // error bubble) is never silently lost from history.
      _saveCurrentSession();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 180,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  });

  void _openOrganizePage(String pageKey) {
    Widget? page;
    final key = pageKey.toLowerCase().trim();
    switch (key) {
      case 'meal':
      case 'meals':
      case 'diet':
      case 'meal_planner':
        page = diet_page.MainScreen(); // Meal Planner
        break;
      case 'medi':
      case 'med':
      case 'meds':
      case 'medicine':
      case 'medicines':
        page = medi_tracker_page.MediTrackScreen(); // Medicine Tracker
        break;
      case 'bill':
      case 'bills':
        page = const bills_page.BillsScreen(); // Bills Page
        break;
      case 'workout':
      case 'fitness':
        page = fitness_page.WorkoutStudioScreen(); // Fitness / Workout
        break;
      case 'calendar':
      case 'events':
      case 'event':
      case 'planner':
      case 'plan_pack':
      case 'prepare':
      case 'prep':
        page = const calendar_page.CalendarShell(); // Calendar Screen
        break;
      case 'skincare':
        page = const skincare_page.SkincareScreen(); // Skincare Screen
        break;
      case 'style':
      case 'daily_wear':
        page = const daily_wear_page.DailyWearScreen();
        break;
      case 'wardrobe':
        Navigator.of(context).maybePop();
        return;
    }
    if (page == null) return;
    // Close any active modal / bottom-sheet before navigating to a
    // full-screen route so no stale scrim leaks onto the destination
    // (see Daily Wear "permanent faded overlay" regression).
    final nav = Navigator.of(context);
    while (nav.canPop()) {
      final route = ModalRoute.of(context);
      if (route is PopupRoute || route is RawDialogRoute) {
        nav.pop();
      } else {
        break;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    nav.push(MaterialPageRoute(builder: (_) => page!));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Fire-and-forget: catches the case where the user backs out of the
    // screen quickly, before the async write from a prior send completes.
    _saveCurrentSession();
    if (_isListening) {
      AhviSpeechService.instance.cancel();
    }
    _chatController.dispose();
    _chatFocusNode.dispose();
    _scrollController.dispose();
    for (final ctrls in _checklistAddCtrlsByTitle.values) {
      for (final c in ctrls) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // setState() లేదు — keyboard వచ్చినప్పుడు full rebuild అవ్వదు.
    // Prompt bar & message list వున్న Builder widgets MediaQuery ని
    // directly read చేస్తాయి కాబట్టి Flutter automatically re-layouts చేస్తుంది.
    // setState() వేస్తే logo కూడా rebuild అయి jump అవుతుంది.
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.backgroundPrimary,
      drawer: _historyDrawer(t),
      // resizeToAvoidBottomInset: true — keyboard వచ్చినప్పుడు Scaffold body
      // automatically shrink అవుతుంది. Logo header Column లో first child కాబట్టి
      // keyboard తో పైకి వెళ్ళదు — SafeArea లో ఉంది, Scaffold body shrink
      // అయినా SafeArea top padding change కాదు.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Logo header — AhviHeader (StatelessWidget, never rebuilds) ──
            AhviHeader(
              showBack: widget.showBackButton,
              showBorder: false,
              frosted: true,
              right: IconButton(
                icon: Icon(
                  Icons.history_rounded,
                  color: context.themeTokens.textPrimary,
                ),
                tooltip: AppLocalizations.t(context, 'chat_history_btn'),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ),

            // ── Message list + typing indicator ──
            Expanded(
              child: Builder(
                builder: (context) {
                  final double kbH = MediaQuery.of(context).viewInsets.bottom;
                  final double navBarH = MediaQuery.viewPaddingOf(
                    context,
                  ).bottom;
                  const double promptBarH = 96.0;
                  const double floatingContentClearance = 92.0;
                  final double listBottomPad = kbH > 0
                      ? promptBarH
                      : navBarH +
                            promptBarH +
                            floatingContentClearance +
                            (widget.showBackButton ? 0 : 80);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            20,
                            16,
                            20,
                            listBottomPad,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _msg(_messages[i], t),
                        ),
                      ),
                      if (_isTyping)
                        const Padding(
                          padding: EdgeInsets.only(left: 20, bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _TypingBubble(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // ── Prompt bar — keyboard వచ్చినప్పుడు Scaffold shrink వల్ల
            // automatically keyboard పైకి వస్తుంది. Extra padding వద్దు. ──
            Builder(
              builder: (context) {
                final double navBarH = MediaQuery.viewPaddingOf(context).bottom;
                final double kbH = MediaQuery.of(context).viewInsets.bottom;
                // Keyboard open అయినప్పుడు Scaffold already shrunk — navBar pad వద్దు
                final double bottomPad = kbH > 0
                    ? 0
                    : navBarH + (widget.showBackButton ? 0 : 80);
                return Padding(
                  padding: EdgeInsets.only(bottom: bottomPad),
                  child: _input(t),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyDrawer(AppThemeTokens t) {
    return Drawer(
      backgroundColor: t.backgroundSecondary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.t(context, 'chat_history_title'),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _startNewChat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [t.accent.primary, t.accent.secondary],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.t(context, 'chat_new'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: t.cardBorder, height: 1),
            // Session list
            Expanded(
              child: _sessions.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.t(context, 'chat_no_history'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.mutedText, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _sessions.length,
                      itemBuilder: (ctx, i) {
                        final s = _sessions[i];
                        final isActive = s.id == _currentSessionId;
                        final date = _formatDate(s.createdAt);
                        return Dismissible(
                          key: ValueKey(s.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red.withValues(alpha: 0.15),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                          onDismissed: (_) => _deleteSession(s.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor: t.accent.primary.withValues(
                              alpha: 0.1,
                            ),
                            onTap: () => _loadSession(s),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? t.accent.primary.withValues(alpha: 0.2)
                                    : t.panel,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: t.cardBorder),
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                                color: isActive
                                    ? t.accent.primary
                                    : t.mutedText,
                              ),
                            ),
                            title: Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              date,
                              style: TextStyle(
                                color: t.mutedText,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return AppLocalizations.t(context, 'chat_today');
    if (diff.inDays == 1) return AppLocalizations.t(context, 'chat_yesterday');
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _msg(_ChatMessage m, AppThemeTokens t) => Column(
    crossAxisAlignment: m.isMe
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Align(
        alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: m.isMe ? t.accent.primary : t.panel,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(m.isMe ? 18 : 4),
              bottomRight: Radius.circular(m.isMe ? 4 : 18),
            ),
            border: m.isMe ? null : Border.all(color: t.cardBorder),
          ),
          child: m.isMe
              ? Text(
                  m.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 8),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: t.accent.primary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        m.isGreeting
                            ? AppLocalizations.t(context, 'chat_greeting')
                            : m.text,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      // Style board cards take priority over text blocks. The module-chat
      // style response carries both a text block ("I pulled together…") AND the
      // board cards; rendering blocks first meant the board was skipped and the
      // text/items showed as a checklist. When cards (or a visual board) exist,
      // render the board and suppress the redundant blocks.
      if (!m.isMe && m.cards.isNotEmpty)
        _outfitBoardView(m.cards, t)
      else if (!m.isMe && m.visualBoard != null)
        _visualBoardView(m.visualBoard!, t)
      else ...[
        if (m.blocks.isNotEmpty)
          ...m.blocks.map((block) => _renderBlock(block, t)),
        if (m.blocks.isEmpty && m.moduleCard != null)
          _moduleCardView(m.moduleCard!, t),
        if (m.blocks.isEmpty && m.moduleCards.isNotEmpty)
          _genericModuleCardsView(m.moduleCards, t),
      ],
      if (!m.isMe && m.local != null) _localView(m.local!, t),
      if (!m.isMe && m.chips.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: m.chips.map((c) {
              final label = _chipLabel(c);
              final value = _chipValue(c);
              return GestureDetector(
                onTap: () {
                  const styleModules = {'style', 'wardrobe', 'daily_wear'};
                  final query = styleModules.contains(_module)
                      ? _resolveStyleActionChipQuery(value)
                      : value;
                  _sendMessage(query, label);
                },
                child: _chip(label, t),
              );
            }).toList(),
          ),
        ),
    ],
  );

  Widget _renderBlock(AhviResponseBlock block, AppThemeTokens t) {
    return AhviBlockRenderer(
      block: block,
      styleBoardsBuilder: (boards) => _outfitBoardView(boards, t),
      visualBoardBuilder: (board) => _visualBoardView(board, t),
      moduleCardBuilder: (card) => _moduleCardView(card, t),
      moduleCardsBuilder: (cards) => _genericModuleCardsView(cards, t),
      onSendMessage: (msg) => _sendMessage(msg),
    );
  }

  Widget _moduleCardView(AhviModuleCard card, AppThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AhviModuleCardView(
        card: card,
        onOpen: () => _openOrganizePage(card.openKey),
        surfaceColor: t.panel,
        textColor: t.textPrimary,
        mutedColor: t.mutedText,
        accentColor: t.accent.primary,
        borderColor: t.cardBorder,
      ),
    );
  }

  Widget _visualBoardView(AhviVisualBoard board, AppThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AhviVisualBoardView(
        board: board,
        textColor: t.textPrimary,
        accentColor: t.accent.primary,
      ),
    );
  }

  Widget _visualDirectionCardsView(List<dynamic> directions, AppThemeTokens t) {
    final usable = directions
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 310,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: usable.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final direction = usable[index];
          final title = _blockText(direction['title'], 'Style Direction');
          final description = _blockText(direction['description'], '');
          final styleNote = _blockText(
            direction['style_note'] ?? direction['styleNote'],
            '',
          );
          final imageUrl = _blockNullableText(
            direction['image_url'] ?? direction['imageUrl'],
          );
          final palette = _blockStringList(direction['palette']).take(5);
          final pieces = _blockStringList(direction['pieces']).take(5);

          return Container(
            width: 300,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      imageUrl,
                      height: 82,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: t.accent.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.32,
                    ),
                  ),
                ],
                if (palette.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: palette
                        .map(
                          (color) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: t.accent.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: t.accent.secondary.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            child: Text(
                              color,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (pieces.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    pieces.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.mutedText,
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                if (styleNote.isNotEmpty)
                  Text(
                    styleNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 11.4,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Magazine flat-lay composition: dynamic boards in a horizontal swipe
  // (PageView). Each board is a single white canvas with one item per
  // role (top / bottom / shoes / bag / watch / jewelry / headwear).
  // A "Save to boards" pill sits below — writes to saved_boards.
  Widget _outfitBoardView(List<dynamic> cards, AppThemeTokens t) {
    final boards = cards
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    if (boards.isEmpty) return const SizedBox.shrink();

    // Unified renderer: route to the responsive VisualDirectionCarousel
    // (AhviOutfitBoardCard + EditorialBoardCanvas) — the same card every
    // surface uses. Replaces the fixed _OutfitBoardSwiper (empty/blob canvas).
    // curationReveal off so the board doesn't re-animate on every rebuild.
    return Transform.translate(
      offset: const Offset(-20, 0),
      child: VisualDirectionCarousel(
        directions: boards,
        onSendMessage: (message) => _sendMessage(message),
        curationReveal: false,
      ),
    );
  }

  String? _editorialBoardImageUrl(Map<String, dynamic> board) {
    for (final key in ['image_url', 'imageUrl', 'board_image_url']) {
      final v = (board[key] ?? '').toString().trim();
      if (v.isNotEmpty && v != 'null' && v.startsWith('http')) return v;
    }
    return null;
  }

  Future<void> _saveBoardToPlanner(
    Map<String, dynamic> board,
    Map<String, Map<String, dynamic>> slotted,
  ) async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);

    var selectedCategory = await _showSaveBoardPicker(
      context,
      _suggestSavedBoardCategory(board),
    );
    if (selectedCategory == null) return;
    if (selectedCategory.key == 'custom') {
      final customLabel = await _showCustomBoardNameDialog(context);
      if (customLabel == null || customLabel.trim().isEmpty) return;
      selectedCategory = _SavedBoardCategory(
        'custom',
        customLabel.trim(),
        Icons.dashboard_customize_rounded,
      );
    }
    final desc = slotted.values
        .map((it) => (it['name'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .join(' + ');
    final firstWithImage = slotted.values.firstWhere(
      (it) => _flatLayImageUrlKv(it).isNotEmpty,
      orElse: () => const <String, dynamic>{},
    );
    final imageUrl = _flatLayImageUrlKv(firstWithImage);
    final outfitItems = _savedBoardOutfitItems(slotted);
    final existingTitles =
        (await appwrite.getSavedBoardsByOccasion(
              _savedCategoryOccasion(selectedCategory),
            ))
            .map(
              (doc) =>
                  (doc.data['title'] ?? doc.data['occasion'] ?? '').toString(),
            )
            .toSet();
    final title = _uniqueSavedBoardTitle(
      _generatedSavedBoardTitle(board, slotted, selectedCategory),
      existingTitles,
    );

    final result = await appwrite.saveBoardToCollection(
      occasion: _savedCategoryOccasion(selectedCategory),
      outfitDescription: desc.isEmpty ? 'AHVI styled look' : desc,
      imageUrl: imageUrl,
      boardCategory: selectedCategory.key,
      boardCategoryLabel: selectedCategory.label,
      title: title,
      prompt: _lastUserPrompt(),
      extra: {
        'itemIds': slotted.values
            .map(
              (it) =>
                  it[r'$id'] ??
                  it['id'] ??
                  it['item_id'] ??
                  it['itemId'] ??
                  it['image_id'] ??
                  it['imageId'],
            )
            .where((id) => id != null && id.toString().trim().isNotEmpty)
            .map((id) => id.toString())
            .toList(),
        'outfitItems': outfitItems,
        'items': outfitItems,
        'board_payload': {
          'title': title,
          'occasion': _savedCategoryOccasion(selectedCategory),
          'items': outfitItems,
        },
        'boardPayload': {
          'title': title,
          'occasion': _savedCategoryOccasion(selectedCategory),
          'items': outfitItems,
        },
      },
      emoji: '✨',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? 'Could not save — check Appwrite permissions'
              : 'Saved to ${selectedCategory.label}',
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _savedBoardOutfitItems(
    Map<String, Map<String, dynamic>> slotted,
  ) {
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final entry in _flatLaySortedEntriesKv(slotted)) {
      final item = entry.value;
      final imageUrl = _flatLayImageUrlKv(item);
      if (imageUrl.isEmpty || seen.contains(imageUrl)) continue;
      seen.add(imageUrl);

      final rawId =
          item[r'$id'] ??
          item['id'] ??
          item['item_id'] ??
          item['itemId'] ??
          item['image_id'] ??
          item['imageId'];
      final id = rawId?.toString().trim() ?? '';
      final name = (item['name'] ?? item['label'] ?? item['title'] ?? entry.key)
          .toString()
          .trim();
      final category =
          (item['category'] ??
                  item['sub_category'] ??
                  item['subcategory'] ??
                  item['type'] ??
                  entry.key)
              .toString()
              .trim();
      final maskedUrl = (item['masked_url'] ?? item['maskedUrl'] ?? imageUrl)
          .toString();

      items.add({
        if (id.isNotEmpty) 'id': id,
        if (id.isNotEmpty) 'item_id': id,
        'role': entry.key,
        'name': name.isEmpty ? entry.key : name,
        'category': category.isEmpty ? entry.key : category,
        'imageUrl': imageUrl,
        'image_url': imageUrl,
        'maskedUrl': maskedUrl,
        'masked_url': maskedUrl,
        'url': imageUrl,
        'thumbnailUrl': imageUrl,
      });
    }
    return items;
  }

  String _lastUserPrompt() {
    for (final row in _chatHistory.reversed) {
      if (row['role'] == 'user') return (row['content'] ?? '').trim();
    }
    return '';
  }

  String _lastResolvedStylePrompt() {
    for (final row in _chatHistory.reversed) {
      if (row['role'] != 'user') continue;
      final text = (row['content'] ?? '').trim();
      if (text.isEmpty || _isShowClosestChip(text) || _isStyleMoreChip(text)) {
        continue;
      }
      if (text.contains('·')) return text;
    }
    for (final row in _chatHistory.reversed) {
      if (row['role'] != 'user') continue;
      final text = (row['content'] ?? '').trim();
      if (text.isNotEmpty && !_isShowClosestChip(text)) return text;
    }
    return '';
  }

  String _pendingStyleClarificationPrompt() {
    if (_clarificationResolvedByCards) return '';
    for (var i = _chatHistory.length - 1; i >= 0; i--) {
      final row = _chatHistory[i];
      if (row['role'] != 'assistant') continue;
      final text = (row['content'] ?? '').toLowerCase();
      final isClarification =
          text.contains('what are we dressing') ||
          text.contains('pick an occasion') ||
          text.contains('what are you dressing for');
      if (!isClarification) continue;
      for (var j = i - 1; j >= 0; j--) {
        final previous = _chatHistory[j];
        if (previous['role'] != 'user') continue;
        final prompt = (previous['content'] ?? '').trim();
        if (prompt.isNotEmpty &&
            !_isShowClosestChip(prompt) &&
            !_isStyleMoreChip(prompt)) {
          return prompt;
        }
      }
    }
    return '';
  }

  // (Slot helpers moved to file-level; see _flatLaySlotsKv etc. at the bottom.)

  Widget _localView(_LocalResponse r, AppThemeTokens t) {
    if (r.type == _RespType.outfits) {
      final screenW = MediaQuery.of(context).size.width;
      final screenH = MediaQuery.of(context).size.height;
      final outfitCardW = (screenW * 0.30).clamp(100.0, 140.0);
      final outfitStripH = (screenH * 0.22).clamp(155.0, 195.0);
      final outfitImgH = outfitStripH * 0.62;
      return SizedBox(
        height: outfitStripH,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: r.outfits.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final o = r.outfits[i];
            final heroTag = 'outfit_hero_${o.name}_$i';
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    barrierColor: Colors.transparent,
                    transitionDuration: const Duration(milliseconds: 420),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 320,
                    ),
                    pageBuilder: (ctx, animation, _) => FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                      ),
                      child: _OutfitDetailPage(
                        outfit: o,
                        heroTag: heroTag,
                        t: t,
                        onSaveChanged: (saved) =>
                            setState(() => o.saved = saved),
                      ),
                    ),
                  ),
                );
              },
              child: Hero(
                tag: heroTag,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: outfitCardW,
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: t.backgroundPrimary.withValues(alpha: 0.20),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                o.image,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                cacheWidth: 280,
                                errorBuilder: (_, __, ___) => Container(
                                  color: t.accent.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: t.mutedText,
                                    size: 28,
                                  ),
                                ),
                              ),
                              // Saved badge
                              if (o.saved)
                                Positioned(
                                  top: 7,
                                  right: 7,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: t.accent.primary.withValues(
                                        alpha: 0.88,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              // Bottom gradient
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        t.backgroundPrimary.withValues(
                                          alpha: 0.40,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Label
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.name,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: o.tags
                                    .take(2)
                                    .map(
                                      (tag) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: t.accent.primary.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            color: t.mutedText,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    if (r.type == _RespType.plan) {
      final colors = [t.accent.primary, t.accent.secondary, t.accent.tertiary];
      return Column(
        children: r.plans
            .asMap()
            .entries
            .map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors[e.key % 3], width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.value.title,
                      style: TextStyle(
                        color: colors[e.key % 3],
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...e.value.items.map(
                      (it) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          it,
                          style: TextStyle(
                            color: t.mutedText,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }
    if (r.type == _RespType.checklist) {
      return _buildChecklistCard(r, t);
    }
    final d = r.card!;
    final accent = t.accent.primary;
    final done = d.rows.where((x) => x.done).length;
    return Container(
      margin: EdgeInsets.only(
        left: 4,
        right: (MediaQuery.of(context).size.width * 0.07).clamp(16.0, 28.0),
        bottom: 16,
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Icon(d.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                ),
                child: Text(
                  '$done/${d.rows.length}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...d.rows.map(
            (x) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: t.panel.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.cardBorder.withValues(alpha: 0.9)),
              ),
              child: Row(
                children: [
                  Icon(
                    x.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: x.done ? accent : t.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x.main,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          x.sub,
                          style: TextStyle(color: t.mutedText, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.20)),
                    ),
                    child: Text(
                      x.tag,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openOrganizePage(d.pageKey),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.cardBorder)),
              ),
              child: Text(
                d.footer,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genericModuleCardsView(
    List<Map<String, dynamic>> cards,
    AppThemeTokens t,
  ) {
    final usable = cards.where((card) => card.isNotEmpty).toList();
    if (usable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: usable
            .map((card) => _genericModuleCard(card, t))
            .toList(growable: false),
      ),
    );
  }

  Widget _genericModuleCard(Map<String, dynamic> card, AppThemeTokens t) {
    if ((card['type'] ?? '').toString() == 'visual_packing_checklist' ||
        card['visual_sections'] is List) {
      return _visualPackingChecklistCard(card, t);
    }
    final title =
        (card['title'] ??
                card['name'] ??
                card['label'] ??
                card['intent'] ??
                card['module'] ??
                'Plan')
            .toString()
            .replaceAll('_', ' ')
            .trim();
    final subtitle =
        (card['subtitle'] ??
                card['summary'] ??
                card['description'] ??
                card['message_text'] ??
                card['response'] ??
                card['message'] ??
                '')
            .toString()
            .trim();
    final itemMaps = _genericCardItemMaps(card);
    final items = itemMaps.isEmpty ? _genericCardItems(card) : const <String>[];
    final action = (card['action'] is Map
        ? Map<String, dynamic>.from(card['action'] as Map)
        : card['cta'] is Map
        ? Map<String, dynamic>.from(card['cta'] as Map)
        : <String, dynamic>{});
    final actionModule =
        (action['module'] ??
                action['route'] ??
                card['open_module'] ??
                card['open_key'] ??
                card['module'] ??
                '')
            .toString();
    final actionTitle = (action['title'] ?? action['label'] ?? 'Open')
        .toString()
        .trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 4, right: 20, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: t.accent.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.checklist_rounded,
                  size: 16,
                  color: t.accent.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Plan' : title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: t.mutedText,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (itemMaps.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...itemMaps.take(8).map((item) => _visualChecklistRow(item, t)),
          ] else if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...items
                .take(8)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: t.accent.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (actionModule.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                final intent = (action['intent'] ?? '').toString();
                if (actionModule == 'plan_pack' ||
                    intent == 'open_checklist' ||
                    intent == 'view_plan' ||
                    intent == 'weather_prep') {
                  _sendMessage(actionTitle);
                  return;
                }
                _openOrganizePage(actionModule);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: t.accent.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: t.accent.primary.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  actionTitle == 'Open'
                      ? 'Open ${actionModule.replaceAll('_', ' ')}'
                      : actionTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.accent.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _visualPackingChecklistCard(
    Map<String, dynamic> card,
    AppThemeTokens t,
  ) {
    final sections = _packingVisualSections(card);
    if (sections.isEmpty) return const SizedBox.shrink();
    final title = (card['title'] ?? 'Carry-on Packing Checklist')
        .toString()
        .trim();
    final subtitle = (card['subtitle'] ?? 'Short trip').toString().trim();
    final rawActions = card['actions'] is List
        ? card['actions'] as List
        : const [];
    final actions = rawActions.isNotEmpty
        ? rawActions
        : const [
            {'label': 'Open checklist'},
            {'label': 'Plan outfits'},
            {'label': 'Weather prep'},
          ];

    // Card-level StatefulBuilder so toggling an item live-updates the
    // progress bar and every section tile in one rebuild.
    return StatefulBuilder(
      builder: (context, setBoard) {
        final progress = _packingProgress(sections);
        final packed = progress.$1;
        final total = progress.$2;
        final ratio = total == 0 ? 0.0 : packed / total;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 4, right: 20, bottom: 96),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Editorial header: title + subtitle + progress on the left,
              // travel hero visual on the right.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? 'Carry-on Packing Checklist' : title,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 20,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: t.accent.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          '$packed of $total packed',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _packingProgressBar(ratio, t),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _packingHeroVisual(t),
                ],
              ),
              const SizedBox(height: 18),
              // Image-first 2-column section grid.
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth < 320 ? 1 : 2;
                  const gap = 10.0;
                  final cardW = ((c.maxWidth - gap * (cols - 1)) / cols) - 0.5;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < sections.length; i++)
                        SizedBox(
                          width: cardW,
                          child: _packingGridCard(
                            sections[i],
                            i + 1,
                            t,
                            () => setBoard(() {}),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _packingActionRow(actions, t),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _packingVisualSections(Map<String, dynamic> card) {
    final raw = card['visual_sections'] ?? card['visualSections'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['items'] is List))
        .toList(growable: false);
  }

  (int, int) _packingProgress(List<Map<String, dynamic>> sections) {
    var packed = 0;
    var total = 0;
    for (final section in sections) {
      for (final item in _packingSectionItems(section)) {
        total++;
        if (_packingItemDone(item)) packed++;
      }
    }
    return (packed, total);
  }

  bool _packingItemDone(Map<String, dynamic> item) {
    final label =
        (item['display_label'] ?? item['label'] ?? item['name'] ?? 'Item')
            .toString()
            .trim();
    final stateKey = (item['id'] ?? label).toString();
    final saved = _checklistChecksByTitle[stateKey];
    if (saved != null && saved.isNotEmpty && saved.first.isNotEmpty) {
      return saved.first.first;
    }
    return item['packed'] == true;
  }

  void _togglePackingItem(Map<String, dynamic> item) {
    final label =
        (item['display_label'] ?? item['label'] ?? item['name'] ?? 'Item')
            .toString()
            .trim();
    final stateKey = (item['id'] ?? label).toString();
    _checklistChecksByTitle[stateKey] = [
      [!_packingItemDone(item)],
    ];
  }

  Widget _packingProgressBar(double ratio, AppThemeTokens t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 6,
        color: t.accent.primary.withValues(alpha: 0.14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: ratio.clamp(0.0, 1.0),
            child: Container(color: t.accent.primary),
          ),
        ),
      ),
    );
  }

  // Travel hero built purely from icons + shapes in the AHVI palette.
  // No external or copyrighted imagery.
  Widget _packingHeroVisual(AppThemeTokens t) {
    return SizedBox(
      width: 96,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 4,
            top: 16,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.secondary.withValues(alpha: 0.16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 22,
            child: Icon(
              Icons.cloud_rounded,
              size: 16,
              color: t.accent.secondary.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            right: 14,
            top: 6,
            child: Row(
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accent.primary.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Icon(
              Icons.flight_rounded,
              size: 18,
              color: t.accent.primary.withValues(alpha: 0.85),
            ),
          ),
          // Suitcase handle
          Positioned(
            right: 30,
            bottom: 54,
            child: Container(
              width: 22,
              height: 12,
              decoration: BoxDecoration(
                border: Border.all(
                  color: t.accent.primary.withValues(alpha: 0.5),
                  width: 2,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
            ),
          ),
          // Suitcase body
          Positioned(
            right: 18,
            bottom: 4,
            child: Container(
              width: 46,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.secondary.withValues(alpha: 0.55),
                    t.accent.primary.withValues(alpha: 0.45),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: t.accent.primary.withValues(alpha: 0.45),
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: t.panel.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          // Passport badge
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 22,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent.primary,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: t.panel, width: 1.6),
              ),
              child: Icon(Icons.menu_book_rounded, size: 12, color: t.panel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _packingGridCard(
    Map<String, dynamic> section,
    int number,
    AppThemeTokens t,
    VoidCallback onChanged,
  ) {
    final title = (section['title'] ?? section['label'] ?? 'Section')
        .toString()
        .trim();
    final id = (section['id'] ?? title).toString().toLowerCase();
    final items = _packingSectionItems(section);
    // Count = number of display tiles (groups), not the quantity sum.
    final count = items.length;
    final shown = items.take(4).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 12),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _packingSectionIcon(id),
                  size: 15,
                  color: t.accent.primary,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$number. ${title.isEmpty ? 'Section' : title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count items',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (shown.isNotEmpty)
            LayoutBuilder(
              builder: (ctx, c) {
                final n = shown.length;
                const gap = 6.0;
                final raw = (c.maxWidth - gap * (n - 1)) / n;
                // Cap tile width so a single item never stretches full-width.
                final tileW = raw.clamp(0.0, 110.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: tileW,
                        child: _packingGridItem(shown[i], t, onChanged),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _packingGridItem(
    Map<String, dynamic> item,
    AppThemeTokens t,
    VoidCallback onChanged,
  ) {
    final label =
        (item['display_label'] ?? item['label'] ?? item['name'] ?? 'Item')
            .toString()
            .trim();
    final done = _packingItemDone(item);
    return Column(
      children: [
        AspectRatio(aspectRatio: 1, child: _packingThumb(item, t, fill: true)),
        const SizedBox(height: 5),
        SizedBox(
          height: 26,
          child: Text(
            label.isEmpty ? 'Item' : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 9.8,
              height: 1.12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            _togglePackingItem(item);
            onChanged();
          },
          child: Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: done
                ? t.accent.primary
                : t.mutedText.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _packingSectionItems(
    Map<String, dynamic> section,
  ) {
    final raw = section['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Widget _packingActionRow(List actions, AppThemeTokens t) {
    final pills = <Widget>[];
    for (final raw in actions.take(3)) {
      final action = raw is Map
          ? Map<String, dynamic>.from(raw)
          : {'label': raw.toString()};
      final label = (action['label'] ?? action['title'] ?? '')
          .toString()
          .trim();
      if (label.isEmpty) continue;
      pills.add(
        GestureDetector(
          onTap: () => _sendMessage(label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.accent.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.accent.primary.withValues(alpha: 0.18),
              ),
            ),
            // Intrinsic width + Wrap below => full label, no ellipsis.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _packingActionIcon(label),
                  size: 14,
                  color: t.accent.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  softWrap: false,
                  style: TextStyle(
                    color: t.accent.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  IconData _packingActionIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('outfit') || l.contains('plan')) {
      return Icons.checkroom_rounded;
    }
    if (l.contains('weather')) return Icons.cloud_outlined;
    return Icons.assignment_turned_in_outlined;
  }

  Widget _packingThumb(
    Map<String, dynamic> item,
    AppThemeTokens t, {
    double size = 40,
    bool round = false,
    bool fill = false,
  }) {
    final imageUrls = item['image_urls'] ?? item['imageUrls'];
    final imageUrl = imageUrls is List && imageUrls.isNotEmpty
        ? imageUrls.first.toString().trim()
        : (item['image_url'] ?? item['imageUrl'] ?? '').toString().trim();
    final label = (item['label'] ?? item['display_label'] ?? '').toString();
    final iconKey = (item['iconKey'] ?? item['icon_key'] ?? '')
        .toString()
        .trim();
    final assetKey = (item['asset_key'] ?? item['assetIcon'] ?? '')
        .toString()
        .trim();
    final icon =
        _packingIconForKey(iconKey) ??
        _packingSectionIcon(
          (item['section'] ?? item['category'] ?? label)
              .toString()
              .toLowerCase(),
        );
    final iconSize = fill ? 22.0 : size * 0.46;
    Widget child;
    if (imageUrl.isNotEmpty) {
      child = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(icon, size: iconSize, color: t.accent.primary),
      );
    } else if (assetKey.startsWith('assets/')) {
      child = Image.asset(
        assetKey,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(icon, size: iconSize, color: t.accent.primary),
      );
    } else {
      child = Icon(icon, size: iconSize, color: t.accent.primary);
    }
    return Container(
      width: fill ? double.infinity : size,
      height: fill ? double.infinity : size,
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(round ? 999 : 12),
        border: round ? null : Border.all(color: t.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(padding: const EdgeInsets.all(5), child: child),
    );
  }

  IconData _packingSectionIcon(String key) {
    final text = key.toLowerCase();
    final icon = _packingIconForKey(text);
    if (icon != null) return icon;
    if (text.contains('cloth') ||
        text.contains('top') ||
        text.contains('wear')) {
      return Icons.checkroom_rounded;
    }
    if (text.contains('tech') ||
        text.contains('charger') ||
        text.contains('phone')) {
      return Icons.power_rounded;
    }
    if (text.contains('document') ||
        text.contains('passport') ||
        text.contains('ticket')) {
      return Icons.description_rounded;
    }
    if (text.contains('weather') ||
        text.contains('rain') ||
        text.contains('sun')) {
      return Icons.wb_sunny_outlined;
    }
    if (text.contains('essential') ||
        text.contains('toiletr') ||
        text.contains('medicine')) {
      return Icons.spa_rounded;
    }
    return Icons.inventory_2_rounded;
  }

  IconData? _packingIconForKey(String key) {
    switch (key.toLowerCase()) {
      case 'sunscreen':
        return Icons.wb_sunny_outlined;
      case 'sunglasses':
        return Icons.remove_red_eye_outlined;
      case 'charger':
      case 'tech':
        return Icons.power_outlined;
      case 'power_bank':
        return Icons.battery_charging_full_outlined;
      case 'toiletries':
      case 'essentials':
        return Icons.inventory_2_outlined;
      case 'water_bottle':
        return Icons.local_drink_outlined;
      case 'shoes':
      case 'clothes':
      case 'jacket':
        return Icons.checkroom_outlined;
      case 'towel':
        return Icons.dry_cleaning_outlined;
      case 'medicine':
        return Icons.medical_services_outlined;
      case 'first_aid':
        return Icons.health_and_safety_outlined;
      case 'documents':
      case 'document':
        return Icons.description_outlined;
      case 'passport':
        return Icons.badge_outlined;
      case 'tickets':
        return Icons.confirmation_number_outlined;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'earphones':
        return Icons.headphones_outlined;
      case 'lip_balm':
        return Icons.face_outlined;
      case 'wet_wipes':
        return Icons.cleaning_services_outlined;
      case 'moisturizer':
        return Icons.spa_outlined;
      case 'sanitizer':
        return Icons.sanitizer_outlined;
      case 'face_mask':
        return Icons.masks_outlined;
      case 'umbrella':
        return Icons.umbrella_outlined;
      case 'travel_pillow':
        return Icons.airline_seat_recline_normal_outlined;
      case 'health':
        return Icons.health_and_safety_outlined;
      case 'camera':
        return Icons.camera_alt_outlined;
      case 'weather':
        return Icons.cloud_outlined;
      case 'bag':
        return Icons.shopping_bag_outlined;
    }
    return null;
  }

  List<String> _genericCardItems(Map<String, dynamic> card) {
    final raw = card['items'] ?? card['steps'] ?? card['checklist'];
    if (raw is List) {
      return raw
          .map((item) {
            if (item is Map) {
              return (item['title'] ??
                      item['label'] ??
                      item['name'] ??
                      item['text'] ??
                      '')
                  .toString()
                  .trim();
            }
            return item.toString().trim();
          })
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final sections = card['sections'];
    if (sections is List) {
      return sections
          .whereType<Map>()
          .expand((section) {
            final heading = (section['title'] ?? section['label'] ?? '')
                .toString()
                .trim();
            final sectionItems = section['items'];
            if (sectionItems is! List) {
              return heading.isEmpty ? const <String>[] : <String>[heading];
            }
            return sectionItems.map((item) {
              final label = item is Map
                  ? (item['title'] ??
                            item['label'] ??
                            item['name'] ??
                            item['text'] ??
                            '')
                        .toString()
                        .trim()
                  : item.toString().trim();
              if (heading.isEmpty || label.isEmpty) return label;
              return '$heading: $label';
            });
          })
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  List<Map<String, dynamic>> _genericCardItemMaps(Map<String, dynamic> card) {
    final raw = card['items'] ?? card['steps'] ?? card['checklist'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final label =
                (item['label'] ??
                        item['title'] ??
                        item['name'] ??
                        item['text'] ??
                        '')
                    .toString()
                    .trim();
            return label.isNotEmpty;
          })
          .toList(growable: false);
    }
    return const [];
  }

  IconData _fallbackIconFor(String label) {
    final text = label.toLowerCase();
    final icon = _packingIconForKey(text);
    if (icon != null) return icon;
    if (text.contains('sunscreen') || text.contains('moistur')) {
      return Icons.spa_rounded;
    }
    if (text.contains('sunglass')) return Icons.wb_sunny_outlined;
    if (text.contains('charger') || text.contains('power bank')) {
      return Icons.battery_charging_full_rounded;
    }
    if (text.contains('water') || text.contains('hydration')) {
      return Icons.local_drink_rounded;
    }
    if (text.contains('shoe') || text.contains('footwear')) {
      return Icons.directions_walk_rounded;
    }
    if (text.contains('jacket') || text.contains('layer')) {
      return Icons.checkroom_rounded;
    }
    if (text.contains('medicine') || text.contains('first')) {
      return Icons.medical_services_outlined;
    }
    return Icons.checklist_rounded;
  }

  Widget _visualChecklistRow(Map<String, dynamic> item, AppThemeTokens t) {
    final label =
        (item['label'] ?? item['title'] ?? item['name'] ?? item['text'] ?? '')
            .toString()
            .trim();
    final category = (item['category'] ?? '').toString().trim();
    final imageUrl = (item['imageUrl'] ?? item['image_url'] ?? '')
        .toString()
        .trim();
    final iconKey = (item['iconKey'] ?? item['icon_key'] ?? '')
        .toString()
        .trim();
    final source = (item['source'] ?? '').toString().trim();
    final stateKey = '${item['wardrobeItemId'] ?? item['iconKey'] ?? label}';

    return StatefulBuilder(
      builder: (context, setRowState) {
        final saved = _checklistChecksByTitle[stateKey];
        final done = saved != null && saved.isNotEmpty && saved.first.isNotEmpty
            ? saved.first.first
            : item['checked'] == true;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setRowState(() {
              _checklistChecksByTitle[stateKey] = [
                [!done],
              ];
            });
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.accent.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.cardBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            _fallbackIconFor(
                              iconKey.isNotEmpty ? iconKey : label,
                            ),
                            size: 18,
                            color: t.accent.primary,
                          ),
                        )
                      : Icon(
                          _fallbackIconFor(
                            iconKey.isNotEmpty ? iconKey : label,
                          ),
                          size: 18,
                          color: t.accent.primary,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 12.8,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (category.isNotEmpty || source.isNotEmpty)
                        Text(
                          [
                            category,
                            source == 'wardrobe' ? 'wardrobe' : '',
                          ].where((v) => v.isNotEmpty).join(' · '),
                          style: TextStyle(
                            color: t.mutedText,
                            fontSize: 10.8,
                            height: 1.2,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? t.accent.primary : t.mutedText,
                  size: 19,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChecklistCard(_LocalResponse r, AppThemeTokens t) {
    final title = r.intro.isNotEmpty ? r.intro : 'Checklist';
    const sections = [
      (
        name: 'Documents',
        emoji: '📄',
        color: Color(0xFF04D7C8), // teal - keep as semantic category color
        items: [
          'Passport / ID',
          'Boarding pass',
          'Travel insurance',
          'Hotel confirmation',
          'Visa (if required)',
        ],
      ),
      (
        name: 'Tech & Power',
        emoji: '🔌',
        color: Color(0xFF8D7DFF),
        items: [
          'Phone + charger',
          'Power bank',
          'Headphones',
          'Laptop or tablet',
          'Universal adapter',
        ],
      ),
      (
        name: 'Comfort',
        emoji: '😴',
        color: Color(0xFF6B91FF),
        items: [
          'Neck pillow',
          'Eye mask',
          'Earplugs',
          'Light jacket',
          'Compression socks',
        ],
      ),
    ];
    const sectionImages = [
      [
        'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1522199755839-a2bacb67c546?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1517336714739-489689fd1ca8?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1525547719571-a2d4ac8945e2?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1583394838336-acd977736f90?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1593344484962-796055d4a3a4?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1520006403909-838d6b92c22e?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1506485338023-6ce5f36692df?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=400&h=260&fit=crop&auto=format',
      ],
    ];

    final itemsState = _checklistItemsByTitle.putIfAbsent(
      title,
      () => sections.map((s) => List<String>.from(s.items)).toList(),
    );
    final addCtrls = _checklistAddCtrlsByTitle.putIfAbsent(
      title,
      () => List.generate(sections.length, (_) => TextEditingController()),
    );
    final checksState = _checklistChecksByTitle.putIfAbsent(
      title,
      () => itemsState
          .map(
            (items) => List<bool>.filled(items.length, false, growable: true),
          )
          .toList(),
    );
    final isSaved = _checklistSavedByTitle[title] ?? false;

    for (var i = 0; i < itemsState.length; i++) {
      final targetLen = itemsState[i].length;
      if (checksState[i].length < targetLen) {
        checksState[i].addAll(
          List<bool>.filled(
            targetLen - checksState[i].length,
            false,
            growable: true,
          ),
        );
      } else if (checksState[i].length > targetLen) {
        checksState[i] = checksState[i].sublist(0, targetLen);
      }
    }

    return StatefulBuilder(
      builder: (context, checklistSetState) {
        final totalItems = itemsState.fold<int>(
          0,
          (sum, items) => sum + items.length,
        );
        final totalChecked = checksState.fold<int>(
          0,
          (sum, items) => sum + items.where((v) => v).length,
        );
        final progress = totalItems == 0 ? 0.0 : totalChecked / totalItems;

        return Container(
          margin: EdgeInsets.only(
            left: 4,
            right: (MediaQuery.of(context).size.width * 0.07).clamp(16.0, 28.0),
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: t.backgroundSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.cardBorder),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: t.phoneShell,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.intro,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$totalChecked of $totalItems items',
                      style: TextStyle(
                        color: t.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 7,
                      decoration: BoxDecoration(
                        color: t.cardBorder.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 300),
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(color: t.accent.tertiary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...List.generate(sections.length, (sIdx) {
                final s = sections[sIdx];
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border(
                      top: BorderSide(
                        color: t.cardBorder.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(s.emoji),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 64,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: sectionImages[sIdx].length,
                          itemExtent: 88,
                          itemBuilder: (_, imgIdx) {
                            final img = sectionImages[sIdx][imgIdx];
                            return Padding(
                              padding: EdgeInsets.only(
                                right: imgIdx == sectionImages[sIdx].length - 1
                                    ? 0
                                    : 8,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: t.cardBorder.withValues(alpha: 0.85),
                                  ),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: Image.network(
                                  img,
                                  fit: BoxFit.cover,
                                  cacheWidth: 264,
                                  cacheHeight: 192,
                                  errorBuilder: (_, _, _) => Container(
                                    color: t.panel.withValues(alpha: 0.75),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: 16,
                                      color: t.mutedText,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(itemsState[sIdx].length, (i) {
                        final done = checksState[sIdx][i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: t.panel.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: t.cardBorder.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => checklistSetState(
                                  () => checksState[sIdx][i] = !done,
                                ),
                                child: Icon(
                                  done
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18,
                                  color: done ? s.color : t.mutedText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  itemsState[sIdx][i],
                                  style: TextStyle(
                                    color: done ? t.mutedText : t.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  checklistSetState(() {
                                    itemsState[sIdx].removeAt(i);
                                    checksState[sIdx].removeAt(i);
                                  });
                                },
                                child: Text(
                                  '×',
                                  style: TextStyle(
                                    color: t.mutedText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: t.phoneShellInner.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: addCtrls[sIdx],
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 12,
                                ),
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.t(
                                    context,
                                    'chat_add_item',
                                  ),
                                  hintStyle: TextStyle(
                                    color: t.mutedText,
                                    fontSize: 12,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) {
                                  final v = addCtrls[sIdx].text.trim();
                                  if (v.isEmpty) return;
                                  checklistSetState(() {
                                    itemsState[sIdx].add(v);
                                    checksState[sIdx].add(false);
                                    addCtrls[sIdx].clear();
                                  });
                                },
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                final v = addCtrls[sIdx].text.trim();
                                if (v.isEmpty) return;
                                checklistSetState(() {
                                  itemsState[sIdx].add(v);
                                  checksState[sIdx].add(false);
                                  addCtrls[sIdx].clear();
                                });
                              },
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: s.color,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  '+',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: GestureDetector(
                  onTap: isSaved
                      ? null
                      : () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: t.backgroundSecondary,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (_) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 12),
                                  Text(
                                    AppLocalizations.t(
                                      context,
                                      'save_to_board_title',
                                    ),
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...[
                                    'Party Looks',
                                    'Occasion',
                                    'Office Fit',
                                    'Vacation',
                                  ].map(
                                    (b) => ListTile(
                                      title: Text(
                                        b,
                                        style: TextStyle(color: t.textPrimary),
                                      ),
                                      trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: t.mutedText,
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        checklistSetState(
                                          () => _checklistSavedByTitle[title] =
                                              true,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          );
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isSaved
                          ? LinearGradient(
                              colors: [t.accent.tertiary, t.accent.tertiary],
                            )
                          : LinearGradient(
                              colors: [t.accent.tertiary, t.accent.primary],
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isSaved
                          ? AppLocalizations.t(context, 'list_saved')
                          : AppLocalizations.t(context, 'save_to_board'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chips(AppThemeTokens t) {
    // Assistant responses render backend quick_actions directly below the
    // bubble/card. Avoid mirroring the same row again above the input bar.
    if (_latestAssistantChips().isNotEmpty) {
      return const SizedBox.shrink();
    }
    final chips = _getChipsByModule(context)[_module] ?? const <String>[];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 7),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => _handleChipTap(chips[i]),
          child: _chip(chips[i], t),
        ),
      ),
    );
  }

  List<String> _latestAssistantChips() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.isMe || message.chips.isEmpty) continue;
      return message.chips
          .map(_chipLabel)
          .where((label) => label.trim().isNotEmpty)
          .toSet()
          .take(4)
          .toList(growable: false);
    }
    return const [];
  }

  Widget _chip(String label, AppThemeTokens t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: t.panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: t.cardBorder, width: 1.2),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: t.mutedText,
      ),
    ),
  );

  Widget _input(AppThemeTokens t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chips(t),
        AhviChatPromptBar(
          controller: _chatController,
          focusNode: _chatFocusNode,
          hintText: AppLocalizations.t(context, 'chat_hint'),
          hasTextListenable: _chatController,
          surface: t.phoneShellInner,
          border: t.cardBorder,
          accent: t.accent.primary,
          accentSecondary: t.accent.secondary,
          textHeading: t.textPrimary,
          textMuted: t.mutedText,
          shadowMedium: t.backgroundPrimary.withValues(alpha: 0.20),
          onAccent: Colors.white,
          themeTokens: t,
          onVoiceTap: _toggleListening,
          isListening: _isListening,
          onSendMessage: (v) => _sendMessage(v),
          // ── Lens sheet actions ──────────────────────────────────────
          onVisualSearch: null,
          onFindSimilar: null,
          onAddToWardrobe:
              null, // uses showAddToWardrobeModal default in lens sheet
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Outfit Detail Page (Hero expand destination) ───────────────────────────

class _OutfitDetailPage extends StatefulWidget {
  final _Outfit outfit;
  final String heroTag;
  final AppThemeTokens t;
  final ValueChanged<bool> onSaveChanged;

  const _OutfitDetailPage({
    required this.outfit,
    required this.heroTag,
    required this.t,
    required this.onSaveChanged,
  });

  @override
  State<_OutfitDetailPage> createState() => _OutfitDetailPageState();
}

class _OutfitDetailPageState extends State<_OutfitDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _contentCtrl;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _saved = widget.outfit.saved;
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _contentFade = CurvedAnimation(
      parent: _contentCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _contentCtrl,
            curve: const Interval(0.2, 1.0, curve: Cubic(0.16, 1.0, 0.3, 1.0)),
          ),
        );
    Future.delayed(const Duration(milliseconds: 170), () {
      if (mounted) _contentCtrl.forward();
    });
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final accent = t.accent.primary;
    final accentTertiary = t.accent.tertiary;
    final bg = t.backgroundPrimary;
    final surface = t.phoneShellInner;
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: bg.withValues(alpha: 0.82),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // prevent tap-through
              child: Hero(
                tag: widget.heroTag,
                flightShuttleBuilder: (_, animation, __, ___, toCtx) =>
                    AnimatedBuilder(
                      animation: animation,
                      builder: (_, __) => toCtx.widget,
                    ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: screenW * 0.88,
                    constraints: BoxConstraints(maxHeight: screenH * 0.82),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.22),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: bg.withValues(alpha: 0.50),
                          blurRadius: 60,
                          offset: const Offset(0, 20),
                        ),
                        BoxShadow(
                          color: accent.withValues(alpha: 0.10),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Large image ───────────────────────────────────
                        SizedBox(
                          height: screenH * 0.42,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                widget.outfit.image,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                errorBuilder: (_, __, ___) => Container(
                                  color: accent.withValues(alpha: 0.10),
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: t.mutedText,
                                    size: 48,
                                  ),
                                ),
                              ),
                              // Bottom fade
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 80,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, surface],
                                    ),
                                  ),
                                ),
                              ),
                              // Top shimmer line
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        accent.withValues(alpha: 0.55),
                                        accentTertiary.withValues(alpha: 0.45),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.35, 0.65, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                              // Close button
                              Positioned(
                                top: 14,
                                right: 14,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: bg.withValues(alpha: 0.55),
                                      border: Border.all(
                                        color: t.cardBorder,
                                        width: 1,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: t.textPrimary,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Content ───────────────────────────────────────
                        FadeTransition(
                          opacity: _contentFade,
                          child: SlideTransition(
                            position: _contentSlide,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(22, 6, 22, 26),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Tags
                                  Wrap(
                                    spacing: 6,
                                    children: widget.outfit.tags
                                        .map(
                                          (tag) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accent.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(100),
                                              border: Border.all(
                                                color: accent.withValues(
                                                  alpha: 0.20,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                color: accent,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 10),

                                  // Name
                                  Text(
                                    widget.outfit.name,
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // 2-line description
                                  Text(
                                    widget.outfit.description.isNotEmpty
                                        ? widget.outfit.description
                                        : 'A curated look styled just for you.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.mutedText,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                      height: 1.55,
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Save button
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _saved = !_saved);
                                      widget.onSaveChanged(_saved);
                                      if (_saved) HapticFeedback.lightImpact();
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: _saved
                                            ? null
                                            : LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  accent,
                                                  accentTertiary,
                                                ],
                                              ),
                                        color: _saved ? t.panel : null,
                                        borderRadius: BorderRadius.circular(16),
                                        border: _saved
                                            ? Border.all(
                                                color: accent.withValues(
                                                  alpha: 0.30,
                                                ),
                                                width: 1,
                                              )
                                            : null,
                                        boxShadow: _saved
                                            ? []
                                            : [
                                                BoxShadow(
                                                  color: accent.withValues(
                                                    alpha: 0.30,
                                                  ),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _saved
                                                ? Icons.bookmark_rounded
                                                : Icons.bookmark_border_rounded,
                                            color: _saved ? accent : onAccent,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _saved
                                                ? 'Saved to Wardrobe'
                                                : 'Save Outfit',
                                            style: TextStyle(
                                              color: _saved ? accent : onAccent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Animated typing bubble (3 bouncing dots) ────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );
    _anims = _ctrls
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: -6,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.backgroundSecondary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) => Transform.translate(
              offset: Offset(0, _anims[i].value),
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: t.mutedText.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pulsing mic animation when listening ────────────────────────────────────
class _PulsingMicIcon extends StatefulWidget {
  const _PulsingMicIcon();

  @override
  State<_PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<_PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return ScaleTransition(
      scale: _scale,
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
    );
  }
}

// _ChatLogoHeader removed — replaced by AhviHeader (see build method above)

// ─── Magazine flat-lay style board ────────────────────────────────────────────
// File-level helpers shared by the State class above and the swiper widget below.

// ================= AHVI BOARD V8 EDITORIAL INTELLIGENCE BEGIN =================

const Map<String, Rect> _flatLaySlotsKv = {
  // V8 editorial composition:
  // - top + bottom become the central hero outfit
  // - footwear is close to the outfit, not floating at the bottom
  // - accessories are a controlled right-side cluster
  // Coordinates are normalized inside the board canvas.
  'outerwear': Rect.fromLTWH(0.055, 0.035, 0.475, 0.345),
  'jacket': Rect.fromLTWH(0.055, 0.035, 0.475, 0.345),
  'blazer': Rect.fromLTWH(0.055, 0.035, 0.475, 0.345),

  'top': Rect.fromLTWH(0.075, 0.055, 0.430, 0.295),
  'tops': Rect.fromLTWH(0.075, 0.055, 0.430, 0.295),
  'shirt': Rect.fromLTWH(0.075, 0.055, 0.430, 0.295),
  'tshirt': Rect.fromLTWH(0.075, 0.055, 0.430, 0.295),
  'tee': Rect.fromLTWH(0.075, 0.055, 0.430, 0.295),

  'bottom': Rect.fromLTWH(0.055, 0.315, 0.480, 0.500),
  'bottoms': Rect.fromLTWH(0.055, 0.315, 0.480, 0.500),
  'pants': Rect.fromLTWH(0.055, 0.315, 0.480, 0.500),
  'trousers': Rect.fromLTWH(0.055, 0.315, 0.480, 0.500),
  'jeans': Rect.fromLTWH(0.055, 0.315, 0.480, 0.500),
  'shorts': Rect.fromLTWH(0.075, 0.395, 0.430, 0.380),

  'dress': Rect.fromLTWH(0.070, 0.055, 0.500, 0.760),
  'dresses': Rect.fromLTWH(0.070, 0.055, 0.500, 0.760),
  'onepiece': Rect.fromLTWH(0.070, 0.055, 0.500, 0.760),
  'saree': Rect.fromLTWH(0.055, 0.045, 0.535, 0.790),
  'indianwear': Rect.fromLTWH(0.055, 0.045, 0.535, 0.790),

  'footwear': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'shoes': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'shoe': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'sneakers': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'boots': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'loafers': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'heels': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'sandals': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),
  'sliders': Rect.fromLTWH(0.565, 0.610, 0.350, 0.250),

  'accessory': Rect.fromLTWH(0.615, 0.095, 0.270, 0.380),
  'accessories': Rect.fromLTWH(0.615, 0.095, 0.270, 0.380),
  'watch': Rect.fromLTWH(0.625, 0.115, 0.175, 0.155),
  'belt': Rect.fromLTWH(0.610, 0.305, 0.270, 0.110),
  'cap': Rect.fromLTWH(0.690, 0.445, 0.180, 0.130),
  'hat': Rect.fromLTWH(0.690, 0.445, 0.180, 0.130),
  'bag': Rect.fromLTWH(0.610, 0.380, 0.270, 0.230),
  'jewelry': Rect.fromLTWH(0.650, 0.155, 0.200, 0.220),
};

// ================= AHVI BOARD V8 EDITORIAL INTELLIGENCE END =================

double _flatLayRoleScaleKv(String role) {
  final r = role.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  // V8: hero garments should dominate the canvas.
  if (r.contains('dress') || r.contains('saree') || r.contains('onepiece')) {
    return 1.34;
  }

  if (r.contains('outer') || r.contains('jacket') || r.contains('blazer')) {
    return 1.24;
  }

  if (r == 'top' ||
      r.contains('shirt') ||
      r.contains('tshirt') ||
      r.contains('tee') ||
      r.contains('polo') ||
      r.contains('kurta')) {
    return 1.33;
  }

  if (r == 'bottom' ||
      r.contains('pant') ||
      r.contains('trouser') ||
      r.contains('jean') ||
      r.contains('short')) {
    return 1.42;
  }

  if (r.contains('foot') ||
      r.contains('shoe') ||
      r.contains('sneaker') ||
      r.contains('boot') ||
      r.contains('loafer') ||
      r.contains('heel') ||
      r.contains('sandal') ||
      r.contains('slider')) {
    return 1.28;
  }

  if (r.contains('watch')) return 0.88;
  if (r.contains('belt')) return 0.92;
  if (r.contains('cap') || r.contains('hat')) return 0.82;
  if (r.contains('bag')) return 1.02;
  if (r.contains('jewel') || r.contains('ring') || r.contains('necklace')) {
    return 0.78;
  }

  if (r.contains('access')) return 0.86;

  return 1.0;
}

String _ahviBoardV8Norm(Object? value) {
  return (value ?? '').toString().trim();
}

bool _ahviBoardV8WeakWhy(Object? value) {
  final v = _ahviBoardV8Norm(value).toLowerCase();
  if (v.isEmpty) return true;
  if (v == 'today') return true;
  if (v == 'date night') return true;
  if (v == 'office') return true;
  if (v == 'work') return true;
  if (v == 'casual') return true;
  if (v == 'party') return true;
  if (v.length < 18) return true;
  return false;
}

String _ahviBoardV8Occasion(Object? raw) {
  final q = _ahviBoardV8Norm(raw).toLowerCase();

  if (q.contains('date')) return 'date night';
  if (q.contains('office') || q.contains('meeting') || q.contains('work')) {
    return 'office';
  }
  if (q.contains('party') || q.contains('club')) return 'party';
  if (q.contains('wedding') ||
      q.contains('traditional') ||
      q.contains('ethnic')) {
    return 'traditional';
  }
  if (q.contains('travel') || q.contains('airport')) return 'travel';
  if (q.contains('rain')) return 'rainy day';
  return 'today';
}

String _ahviBoardV8LookName({
  Object? rawTitle,
  Object? occasion,
  int index = 0,
}) {
  final title = _ahviBoardV8Norm(rawTitle);
  final lower = title.toLowerCase();

  if (title.isNotEmpty &&
      !lower.contains('ahvi styled look') &&
      !lower.contains('look ${index + 1}') &&
      lower.length > 8) {
    return title;
  }

  switch (_ahviBoardV8Occasion(occasion)) {
    case 'date night':
      return 'Look ${index + 1} · Evening Smart Casual';
    case 'office':
      return 'Look ${index + 1} · Polished Work Fit';
    case 'party':
      return 'Look ${index + 1} · After-Hours Statement';
    case 'traditional':
      return 'Look ${index + 1} · Occasion Ready';
    case 'travel':
      return 'Look ${index + 1} · Travel Smart';
    case 'rainy day':
      return 'Look ${index + 1} · Weather Ready';
    default:
      return 'Look ${index + 1} · Clean Daily Look';
  }
}

String _ahviBoardV8Why({
  Object? rawWhy,
  Object? occasion,
  Object? top,
  Object? bottom,
  Object? footwear,
  Object? accessory,
}) {
  final existing = _ahviBoardV8Norm(rawWhy);
  if (!_ahviBoardV8WeakWhy(existing)) return existing;

  final occ = _ahviBoardV8Occasion(occasion);
  final topName = _ahviBoardV8Norm(top);
  final bottomName = _ahviBoardV8Norm(bottom);
  final footwearName = _ahviBoardV8Norm(footwear);
  final accessoryName = _ahviBoardV8Norm(accessory);

  String pieces() {
    final parts = <String>[];
    if (topName.isNotEmpty) parts.add(topName);
    if (bottomName.isNotEmpty) parts.add(bottomName);
    if (footwearName.isNotEmpty) parts.add(footwearName);
    return parts.take(3).join(', ');
  }

  final usedPieces = pieces();

  if (occ == 'date night') {
    return usedPieces.isNotEmpty
        ? 'This works for date night because $usedPieces creates a clean smart-casual base. The look feels intentional without being overdone, and the accessory choice keeps it polished.'
        : 'This works for date night because it balances polish and ease: a clean hero piece, a grounded base, and minimal accessories so the look feels intentional.';
  }

  if (occ == 'office') {
    return usedPieces.isNotEmpty
        ? 'This works for office because $usedPieces keeps the outfit structured, neat, and easy to wear through the day. The styling stays professional without looking stiff.'
        : 'This works for office because it keeps the outfit structured and clean while staying comfortable enough for a full day.';
  }

  if (occ == 'party') {
    return usedPieces.isNotEmpty
        ? 'This works for a party because $usedPieces gives the outfit a stronger visual point of view while keeping the base balanced and wearable.'
        : 'This works for a party because it adds visual interest without making the outfit feel messy or over-accessorized.';
  }

  if (occ == 'travel') {
    return usedPieces.isNotEmpty
        ? 'This works for travel because $usedPieces keeps the outfit comfortable, practical, and still put-together.'
        : 'This works for travel because it prioritizes comfort, easy movement, and a clean put-together finish.';
  }

  if (accessoryName.isNotEmpty) {
    return 'This works because the outfit has a clean base and $accessoryName adds a controlled finishing detail without cluttering the look.';
  }

  return usedPieces.isNotEmpty
      ? 'This works because $usedPieces creates a balanced everyday outfit: clean, easy to wear, and visually connected.'
      : 'This works because it keeps the outfit balanced, wearable, and visually clean for the occasion.';
}

EdgeInsets _flatLayRolePaddingKv(String role) {
  switch (role) {
    case 'top':
    case 'bottom':
    case 'dress':
      return const EdgeInsets.all(0);
    case 'footwear':
      return const EdgeInsets.all(2);
    case 'bag':
      return const EdgeInsets.all(4);
    default:
      return const EdgeInsets.all(6);
  }
}

int _flatLayRoleZKv(String role) {
  switch (role) {
    case 'bottom':
      return 1;
    case 'top':
    case 'dress':
      return 2;
    case 'footwear':
      return 3;
    case 'bag':
      return 4;
    default:
      return 5;
  }
}

List<MapEntry<String, Map<String, dynamic>>> _flatLaySortedEntriesKv(
  Map<String, Map<String, dynamic>> byRole,
) {
  final entries = byRole.entries.toList();
  entries.sort(
    (a, b) => _flatLayRoleZKv(a.key).compareTo(_flatLayRoleZKv(b.key)),
  );
  return entries;
}

String _flatLayImageUrlKv(Map<String, dynamic> item) {
  // AHVI style boards must prefer clean/processed item assets.
  // Some older documents store the raw photo in image_url, so image_url
  // should not win over normalized/masked/processed URLs.
  final candidates = <Object?>[
    item['normalized_url'],
    item['normalizedUrl'],
    item['transparent_url'],
    item['transparentUrl'],
    item['processed_url'],
    item['processedUrl'],
    item['masked_url'],
    item['maskedUrl'],
    item['png_url'],
    item['pngUrl'],
    item['cutout_url'],
    item['cutoutUrl'],
    item['image_url'],
    item['imageUrl'],
    item['public_url'],
    item['publicUrl'],
    item['url'],
    item['image'],
    item['raw_url'],
    item['rawUrl'],
  ];

  for (final value in candidates) {
    final url = value?.toString().trim() ?? '';
    if (url.isEmpty || url.toLowerCase() == 'null') continue;
    return url;
  }

  return '';
}

// Premium board shell colors / spacing
const double _kvBoardRadius = 24.0;
const double _kvSectionRadius = 18.0;

String _roleForItem(Map<String, dynamic> item) {
  final blob = [
    item['layout_role'],
    item['role'],
    item['slot'],
    item['type'],
    item['category'],
    item['cat'],
    item['category_group'],
    item['sub_category'],
    item['subcategory'],
    item['subCategory'],
    item['name'],
    item['label'],
    item['description'],
  ].where((v) => v != null).join(' ').toLowerCase();

  bool has(String pattern) => RegExp(pattern).hasMatch(blob);

  if (has(
    r'\b(footwear|shoe|shoes|heel|heels|sandal|sandals|flat|flats|pump|pumps|loafer|loafers|sneaker|sneakers|boot|boots)\b',
  )) {
    return 'footwear';
  }

  // One-piece before top
  if (has(r'\b(dress|dresses|saree|sari|lehenga|gown|jumpsuit|kurta set)\b')) {
    return 'dress';
  }

  // Fine accessory roles
  if (has(r'\b(earring|earrings)\b')) return 'earrings';
  if (has(r'\b(necklace|pendant|choker)\b')) return 'necklace';
  if (has(r'\b(ring|rings)\b')) return 'ring';
  if (has(r'\b(bracelet|bracelets|bangle|bangles)\b')) return 'bracelet';
  if (has(r'\b(watch|watches)\b')) return 'watch';
  if (has(r'\b(sunglass|sunglasses|eyewear|glasses|shade|shades)\b'))
    return 'eyewear';
  if (has(r'\b(belt|belts)\b')) return 'belt';
  if (has(
    r'\b(bag|bags|purse|clutch|tote|handbag|hobo|crossbody|shoulder bag|backpack)\b',
  ))
    return 'bag';
  if (has(r'\b(cap|caps|hat|hats|beanie|headwear)\b')) return 'headwear';
  if (has(r'\b(accessory|accessories|scarf|scarves|brooch)\b'))
    return 'accessory';

  if (has(
    r'\b(top|tops|shirt|shirts|blouse|tee|tshirt|tshirts|tank|cami|camisole|sweater|cardigan|jacket|blazer|kurti|tunic|crop top|polo|hoodie)\b',
  )) {
    return 'top';
  }

  if (has(
    r'\b(bottom|bottoms|jean|jeans|pant|pants|trouser|trousers|wide leg|wide-leg|shorts|skirt|skirts|palazzo|chino|chinos|cargo|jogger|joggers)\b',
  )) {
    return 'bottom';
  }

  return 'unknown';
}

Map<String, Map<String, dynamic>> _slotItemsForFlatLayKv(
  List<Map<String, dynamic>> items,
) {
  final byRole = <String, Map<String, dynamic>>{};
  final seenRole = <String>{};
  final seenId = <String>{};
  var accessoryOverflow = 0;

  bool hasImage(Map<String, dynamic> item) {
    return _flatLayImageUrlKv(item).isNotEmpty;
  }

  String itemId(Map<String, dynamic> item) {
    return (item[r'$id'] ??
            item['id'] ??
            item['item_id'] ??
            item['image_id'] ??
            item['name'] ??
            item['label'] ??
            item.hashCode)
        .toString()
        .toLowerCase();
  }

  bool isAccessoryRole(String role) {
    return {
      'earrings',
      'necklace',
      'ring',
      'bracelet',
      'watch',
      'eyewear',
      'belt',
      'bag',
      'headwear',
    }.contains(role);
  }

  void putAccessoryOverflow(Map<String, dynamic> item) {
    if (accessoryOverflow >= 2) return;
    final key = accessoryOverflow == 0 ? 'accessory1' : 'accessory2';
    accessoryOverflow += 1;
    byRole.putIfAbsent(key, () => item);
  }

  void putRole(String role, Map<String, dynamic> item) {
    if (!hasImage(item)) return;

    final id = itemId(item);
    if (seenId.contains(id)) return;
    seenId.add(id);

    if (role == 'accessory') {
      putAccessoryOverflow(item);
      return;
    }

    if (byRole.containsKey(role) || seenRole.contains(role)) {
      if (isAccessoryRole(role)) {
        putAccessoryOverflow(item);
      }
      return;
    }

    byRole[role] = item;
    seenRole.add(role);
  }

  for (final item in items) {
    final role = _roleForItem(item);
    if (role == 'unknown') continue;

    if (_flatLaySlotsKv.containsKey(role) || role == 'accessory') {
      putRole(role, item);
    }
  }

  if (byRole.containsKey('dress')) {
    byRole.remove('top');
    byRole.remove('bottom');
  }

  return byRole;
}

Widget _flatLayPieceKv(
  Map<String, dynamic> item,
  String role,
  Rect slot,
  Size boardSize,
) {
  final imageUrl = _flatLayImageUrlKv(item);

  if (imageUrl.isEmpty) {
    return const SizedBox.shrink();
  }

  final left = slot.left * boardSize.width;
  final top = slot.top * boardSize.height;
  final width = slot.width * boardSize.width;
  final height = slot.height * boardSize.height;

  final scale = _flatLayRoleScaleKv(role);
  final scaledWidth = width * scale;
  final scaledHeight = height * scale;

  final isHero = role == 'top' || role == 'bottom' || role == 'dress';

  return Positioned(
    left: left + ((width - scaledWidth) / 2),
    top: top + ((height - scaledHeight) / 2),
    width: scaledWidth,
    height: scaledHeight,
    child: Padding(
      padding: _flatLayRolePaddingKv(role),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isHero ? 24 : 18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isHero ? 0.07 : 0.045),
              blurRadius: isHero ? 22 : 12,
              spreadRadius: isHero ? -8 : -6,
              offset: Offset(0, isHero ? 14 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isHero ? 24 : 18),
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

typedef _OutfitBoardSaveCallback =
    Future<void> Function(
      Map<String, dynamic> board,
      Map<String, Map<String, dynamic>> slotted,
    );

class _OutfitBoardSwiper extends StatefulWidget {
  final List<Map<String, dynamic>> boards;
  final AppThemeTokens t;
  final _OutfitBoardSaveCallback onSave;

  const _OutfitBoardSwiper({
    required this.boards,
    required this.t,
    required this.onSave,
  });

  @override
  State<_OutfitBoardSwiper> createState() => _OutfitBoardSwiperState();
}

class _OutfitBoardSwiperState extends State<_OutfitBoardSwiper> {
  final _controller = PageController();
  int _index = 0;
  final Set<int> _saving = {};
  final Set<int> _saved = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final n = widget.boards.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              n > 1
                  ? 'AHVI styled looks · swipe'
                  : _ahviBoardV8LookName(index: 0, occasion: 'today'),
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          AspectRatio(
            aspectRatio: 0.78,
            child: PageView.builder(
              controller: _controller,
              itemCount: n,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) =>
                  _editorialBoardCanvas(widget.boards[i], t, i),
            ),
          ),
          if (n > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(n, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: active
                          ? t.textPrimary.withValues(alpha: 0.85)
                          : t.textPrimary.withValues(alpha: 0.25),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveBoardAt(int index) async {
    if (index < 0 || index >= widget.boards.length) return;
    if (_saving.contains(index) || _saved.contains(index)) return;

    setState(() => _saving.add(index));
    final board = widget.boards[index];
    // Prefer board_items (role-tagged, image-bearing) over the legacy `items`.
    // Visual-inspiration cards put the rendered pieces under board_items; their
    // `items` are text pieces with no images, so the flat-lay collage rendered
    // empty. board_items carries image_url, so the collage now paints.
    final rawItems =
        (board['board_items'] as List?) ??
        (board['items'] as List?) ??
        const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final slotted = _slotItemsForFlatLayKv(items);

    await widget.onSave(board, slotted);
    if (!mounted) return;
    setState(() {
      _saving.remove(index);
      _saved.add(index);
    });
  }

  Widget _editorialBoardCanvas(
    Map<String, dynamic> board,
    AppThemeTokens t,
    int index,
  ) {
    // Prefer board_items (role-tagged, image-bearing) over the legacy `items`.
    // Visual-inspiration cards put the rendered pieces under board_items; their
    // `items` are text pieces with no images, so the flat-lay collage rendered
    // empty. board_items carries image_url, so the collage now paints.
    final rawItems =
        (board['board_items'] as List?) ??
        (board['items'] as List?) ??
        const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final slotted = _slotItemsForFlatLayKv(items);

    final top = _editorialFindItem(slotted, items, const [
      'top',
      'shirt',
      't-shirt',
      'tee',
      'polo',
      'kurta',
      'hoodie',
      'jacket',
      'blazer',
      'overshirt',
    ]);

    final bottom = _editorialFindItem(slotted, items, const [
      'bottom',
      'bottoms',
      'bottomwear',
      'pant',
      'pants',
      'trouser',
      'trousers',
      'jean',
      'jeans',
      'chino',
      'chinos',
      'short',
      'shorts',
      'skirt',
      'skirts',
      'joggers',
      'churidar',
      'pajama',
      'pyjama',
      'dhoti',
    ]);

    final dress = _editorialFindItem(slotted, items, const [
      'dress',
      'saree',
      'gown',
      'lehenga',
    ]);

    final footwear = _editorialFindItem(slotted, items, const [
      'footwear',
      'shoe',
      'shoes',
      'sneaker',
      'sneakers',
      'loafer',
      'loafers',
      'slider',
      'sliders',
      'slipper',
      'slippers',
      'boot',
      'boots',
      'sandals',
    ]);

    final accessories = _editorialAccessories(
      items,
      top,
      bottom,
      dress,
      footwear,
    );

    final lookName = _editorialLookName(board, top ?? dress, bottom);
    final occasion = _editorialOccasion(board);
    final why = _editorialWhy(board, top ?? dress, bottom, footwear);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.cardBorder.withValues(alpha: 0.75)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _editorialHeader(t, index, lookName, occasion),
              const SizedBox(height: 8),
              _editorialWhyBox(t, why),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;

                    Widget positionedItem({
                      required Map<String, dynamic>? item,
                      required double left,
                      required double topPx,
                      required double width,
                      required double height,
                      required AppThemeTokens t,
                      Alignment alignment = Alignment.center,
                      double scale = 1.0,
                    }) {
                      if (item == null) return const SizedBox.shrink();
                      return Positioned(
                        left: left,
                        top: topPx,
                        width: width,
                        height: height,
                        child: Transform.scale(
                          scale: scale,
                          alignment: alignment,
                          child: Align(
                            alignment: alignment,
                            child: _editorialImageOrPlaceholder(item, t),
                          ),
                        ),
                      );
                    }

                    final visibleAccessories = accessories
                        .take(4)
                        .toList(growable: false);
                    final accessoryCount = visibleAccessories.length;
                    final railLeft = w * 0.710;
                    final railTop = h * 0.045;
                    final railGap = h * 0.022;
                    final railItemH = accessoryCount <= 2
                        ? h * 0.180
                        : h * 0.142;
                    final railItemW = w * 0.250;
                    final bottomText =
                        '${bottom?['name'] ?? ''} ${bottom?['category'] ?? ''} ${bottom?['subcategory'] ?? ''}'
                            .toLowerCase();
                    final bottomIsShorts =
                        bottomText.contains('short') ||
                        bottomText.contains('skirt');

                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned(
                            right: -w * 0.13,
                            top: -h * 0.10,
                            width: w * 0.60,
                            height: w * 0.60,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(
                                  0xFFF1E7EA,
                                ).withValues(alpha: 0.86),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -w * 0.18,
                            bottom: -h * 0.08,
                            width: w * 0.52,
                            height: w * 0.52,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(
                                  0xFFF5F1E7,
                                ).withValues(alpha: 0.70),
                              ),
                            ),
                          ),

                          // Bottoms need their own visible lane; do not hide
                          // shorts/trousers entirely behind the shirt hero.
                          if (dress == null)
                            positionedItem(
                              item: bottom,
                              left: bottomIsShorts ? w * 0.455 : w * 0.405,
                              topPx: bottomIsShorts ? h * 0.300 : h * 0.115,
                              width: bottomIsShorts ? w * 0.345 : w * 0.390,
                              height: bottomIsShorts ? h * 0.455 : h * 0.760,
                              t: t,
                              // Tamed scale: boxes already size the contain
                              // image; >1.0 only pushed garments past the
                              // Clip.antiAlias edge and clipped them.
                              scale: bottomIsShorts ? 1.02 : 1.06,
                            ),

                          // Dress path uses the main canvas area.
                          if (dress != null)
                            positionedItem(
                              item: dress,
                              left: w * 0.020,
                              topPx: h * 0.015,
                              width: w * 0.620,
                              height: h * 0.850,
                              t: t,
                              scale: 1.06,
                            ),

                          // Foreground layer: top/shirt.
                          if (dress == null)
                            positionedItem(
                              item: top,
                              left: -w * 0.005,
                              topPx: h * 0.045,
                              width: w * 0.585,
                              height: h * 0.700,
                              t: t,
                              scale: 1.08,
                            ),

                          // Footwear: bottom-left anchor. No upscaling — it sat
                          // at the canvas edge and was the worst-clipped item.
                          positionedItem(
                            item: footwear,
                            left: -w * 0.025,
                            topPx: h * 0.650,
                            width: w * 0.455,
                            height: h * 0.300,
                            t: t,
                            alignment: Alignment.bottomLeft,
                            scale: 1.0,
                          ),

                          // Controlled right accessory rail.
                          for (var i = 0; i < visibleAccessories.length; i++)
                            Positioned(
                              left: railLeft,
                              top: railTop + (railItemH + railGap) * i,
                              width: railItemW,
                              height: i == 2 && accessoryCount >= 3
                                  ? railItemH * 1.20
                                  : railItemH,
                              child: Transform.scale(
                                scale: 1.0,
                                child: _editorialImageOrPlaceholder(
                                  visibleAccessories[i],
                                  t,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 1,
                width: double.infinity,
                color: t.cardBorder.withValues(alpha: 0.72),
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _saving.contains(index) || _saved.contains(index)
                            ? null
                            : () => _saveBoardAt(index),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _saved.contains(index)
                                    ? Icons.check_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: t.mutedText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _saving.contains(index)
                                    ? 'Saving…'
                                    : (_saved.contains(index)
                                          ? 'Saved'
                                          : 'Save Look'),
                                style: TextStyle(
                                  color: t.mutedText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 22,
                      color: t.cardBorder.withValues(alpha: 0.72),
                    ),
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.ios_share_rounded,
                              size: 18,
                              color: t.mutedText,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Share',
                              style: TextStyle(
                                color: t.mutedText,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorialHeader(
    AppThemeTokens t,
    int index,
    String lookName,
    String occasion,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LOOK ${(index + 1).toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: t.accent.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                lookName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: t.accent.secondary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: t.accent.secondary.withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            occasion.toUpperCase(),
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ],
    );
  }

  Widget _editorialWhyBox(AppThemeTokens t, String why) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder.withValues(alpha: 0.55)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Why it works: ',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(text: why),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.mutedText,
          fontSize: 10.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _editorialSectionLabel(AppThemeTokens t, String label) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.textPrimary.withValues(alpha: 0.75),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: t.cardBorder.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  Widget _editorialImageOrPlaceholder(
    Map<String, dynamic> item,
    AppThemeTokens t,
  ) {
    final imageUrl = _flatLayImageUrlKv(item);
    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _editorialPlaceholder(item, t),
      );
    }
    return _editorialPlaceholder(item, t);
  }

  Widget _editorialPlaceholder(Map<String, dynamic> item, AppThemeTokens t) {
    final name =
        (item['name'] ??
                item['label'] ??
                item['title'] ??
                item['category'] ??
                'Item')
            .toString();

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.accent.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.cardBorder.withValues(alpha: 0.45)),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _editorialEmpty(AppThemeTokens t, String text) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.cardBorder.withValues(alpha: 0.40)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: t.mutedText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Map<String, dynamic>? _editorialFindItem(
    Map<String, Map<String, dynamic>> slotted,
    List<Map<String, dynamic>> items,
    List<String> tokens,
  ) {
    for (final entry in slotted.entries) {
      final key = entry.key.toLowerCase();
      if (tokens.any((token) => key.contains(token))) {
        return entry.value;
      }
    }

    for (final item in items) {
      final text = _editorialItemText(item);
      if (tokens.any((token) => text.contains(token))) {
        return item;
      }
    }

    return null;
  }

  String _editorialItemText(Map<String, dynamic> item) {
    return [
      item['name'],
      item['label'],
      item['title'],
      item['category'],
      item['sub_category'],
      item['subcategory'],
      item['type'],
      item['color'],
    ].where((v) => v != null).join(' ').toLowerCase();
  }

  List<Map<String, dynamic>> _editorialAccessories(
    List<Map<String, dynamic>> items,
    Map<String, dynamic>? top,
    Map<String, dynamic>? bottom,
    Map<String, dynamic>? dress,
    Map<String, dynamic>? footwear,
  ) {
    final blocked = <Map<String, dynamic>>[
      if (top != null) top,
      if (bottom != null) bottom,
      if (dress != null) dress,
      if (footwear != null) footwear,
    ];

    final seen = <String>{};
    final output = <Map<String, dynamic>>[];

    for (final item in items) {
      if (blocked.any((b) => identical(b, item))) continue;

      final text = _editorialItemText(item);
      final isAccessory =
          text.contains('watch') ||
          text.contains('bracelet') ||
          text.contains('belt') ||
          text.contains('cap') ||
          text.contains('bag') ||
          text.contains('sunglass') ||
          text.contains('eyewear') ||
          text.contains('jewel') ||
          text.contains('chain') ||
          text.contains('ring');

      if (!isAccessory) continue;

      final key =
          (item['category'] ??
                  item['sub_category'] ??
                  item['name'] ??
                  item['label'] ??
                  text)
              .toString()
              .toLowerCase()
              .trim();

      if (key.isEmpty || seen.add(key)) {
        output.add(item);
      }
    }

    return output;
  }

  String _editorialLookName(
    Map<String, dynamic> board,
    Map<String, dynamic>? top,
    Map<String, dynamic>? bottom,
  ) {
    final existing =
        (board['look_name'] ??
                board['lookName'] ??
                board['title'] ??
                board['name'] ??
                board['label'] ??
                '')
            .toString()
            .trim();

    final occasion = _editorialOccasion(board).toLowerCase();
    final lower = existing.toLowerCase();
    final genericTitle =
        existing.isEmpty ||
        lower == 'styled look' ||
        lower == 'ahvi style board' ||
        lower == 'hero look' ||
        lower == "today's edit" ||
        lower == 'easy win' ||
        lower == 'signature combo' ||
        lower == 'polished daily';

    if (occasion.contains('date') && genericTitle) return 'Date Night Edit';
    if (occasion.contains('office') && genericTitle) return 'Boardroom Casual';
    if (occasion.contains('work') && genericTitle) return 'Sharp Daily';
    if (occasion.contains('party') && genericTitle) return 'After-Hours Edit';
    if (genericTitle) return 'Polished Neutral';
    return existing;
  }

  String _editorialOccasion(Map<String, dynamic> board) {
    final text = [
      board['occasion'],
      board['intent'],
      board['title'],
      board['vibe'],
      board['aesthetic'],
      board['reason'],
    ].where((v) => v != null).join(' ').toLowerCase();

    if (text.contains('date')) return 'Date Night';
    if (text.contains('office') || text.contains('business'))
      return 'Office Casual';
    if (text.contains('evening') || text.contains('dinner'))
      return 'Evening Casual';
    if (text.contains('brunch')) return 'Brunch';
    if (text.contains('street')) return 'Streetwear';

    return 'Smart Casual';
  }

  String _editorialWhy(
    Map<String, dynamic> board,
    Map<String, dynamic>? top,
    Map<String, dynamic>? bottom,
    Map<String, dynamic>? footwear,
  ) {
    final existing =
        (board['why_it_works'] ??
                board['whyItWorks'] ??
                board['explanation'] ??
                board['reason'] ??
                board['vibe'] ??
                '')
            .toString()
            .trim();

    if (existing.isNotEmpty && existing.toLowerCase() != 'wardrobe ready') {
      return existing;
    }

    final topName = (top?['name'] ?? top?['label'] ?? top?['category'] ?? 'top')
        .toString();
    final bottomName =
        (bottom?['name'] ?? bottom?['label'] ?? bottom?['category'] ?? 'bottom')
            .toString();
    final footwearName =
        (footwear?['name'] ??
                footwear?['label'] ??
                footwear?['category'] ??
                'footwear')
            .toString();

    return 'The $topName creates the focal point, the $bottomName balances the silhouette, and the $footwearName finishes the look cleanly.';
  }

  Widget _saveButton(AppThemeTokens t) {
    final saving = _saving.contains(_index);
    final saved = _saved.contains(_index);
    return GestureDetector(
      onTap: saving || saved
          ? null
          : () async {
              setState(() => _saving.add(_index));
              final board = widget.boards[_index];
              // Prefer board_items (role-tagged, image-bearing) over the legacy `items`.
              // Visual-inspiration cards put the rendered pieces under board_items; their
              // `items` are text pieces with no images, so the flat-lay collage rendered
              // empty. board_items carries image_url, so the collage now paints.
              final rawItems =
                  (board['board_items'] as List?) ??
                  (board['items'] as List?) ??
                  const [];
              final items = rawItems
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              final slotted = _slotItemsForFlatLayKv(items);
              await widget.onSave(board, slotted);
              if (!mounted) return;
              setState(() {
                _saving.remove(_index);
                _saved.add(_index);
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: saved
              ? t.accent.primary.withValues(alpha: 0.15)
              : t.accent.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: t.accent.primary.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              saved ? Icons.check_rounded : Icons.favorite_border_rounded,
              size: 16,
              color: t.accent.primary,
            ),
            const SizedBox(width: 6),
            Text(
              saving ? 'Saving…' : (saved ? 'Saved' : 'Save Look'),
              style: TextStyle(
                color: t.accent.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= AHVI V6 PREMIUM BOARD UI HELPERS BEGIN =================

TextStyle _kvBoardTitleStyle(BuildContext context) {
  return Theme.of(context).textTheme.titleLarge!.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.1,
  );
}

TextStyle _kvBoardSubtitleStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    color: const Color(0xFF6B7280),
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
}

TextStyle _kvSectionTitleStyle(BuildContext context) {
  return Theme.of(context).textTheme.titleMedium!.copyWith(
    fontWeight: FontWeight.w700,
    color: const Color(0xFF2F2560),
    letterSpacing: -0.2,
  );
}

// ================= AHVI V6 PREMIUM BOARD UI HELPERS END =================

// ================= AHVI V4.5 SINGLE CANVAS MORE LOOKS MERGE =================
