import 'package:flutter/material.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';

typedef StyleBoardsBuilder = Widget Function(List<dynamic> boards);
typedef VisualBoardBuilder = Widget Function(AhviVisualBoard board);
typedef ModuleCardBuilder = Widget Function(AhviModuleCard card);
typedef ModuleCardsBuilder = Widget Function(List<Map<String, dynamic>> cards);
typedef WardrobeGapBuilder = Widget Function(Map<String, dynamic> data);
typedef MessageSender = void Function(String message);

class AhviBlockRenderer extends StatelessWidget {
  final AhviResponseBlock block;
  final StyleBoardsBuilder styleBoardsBuilder;
  final VisualBoardBuilder visualBoardBuilder;
  final ModuleCardBuilder moduleCardBuilder;
  final ModuleCardsBuilder moduleCardsBuilder;
  final WardrobeGapBuilder? wardrobeGapBuilder;
  final MessageSender? onSendMessage;

  const AhviBlockRenderer({
    super.key,
    required this.block,
    required this.styleBoardsBuilder,
    required this.visualBoardBuilder,
    required this.moduleCardBuilder,
    required this.moduleCardsBuilder,
    this.wardrobeGapBuilder,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case AhviBlockType.styleAdvice:
        return StyleAdviceCard(data: block.data);
      case AhviBlockType.transitionPlan:
        return TransitionPlanCard(data: block.data);
      case AhviBlockType.stylistReasoning:
        return StylistReasoningCard(data: block.data);
      case AhviBlockType.visualInspiration:
        return VisualInspirationCard(
          data: block.data,
          onSendMessage: onSendMessage,
        );
      case AhviBlockType.missingPiece:
        return MissingPieceIntelligenceCard(
          data: block.data,
          onSendMessage: onSendMessage,
        );
      case AhviBlockType.visualDirections:
        final directions = _mapList(block.data['directions']);
        final cover = block.data['editorial_cover'];
        final coverMap = cover is Map
            ? Map<String, dynamic>.from(cover)
            : const <String, dynamic>{};
        return Transform.translate(
          offset: const Offset(-20, 0),
          child: VisualDirectionCarousel(
            directions: directions,
            editorialCover: coverMap,
            onSendMessage: onSendMessage,
          ),
        );
      case AhviBlockType.styleBoards:
        final boards = block.data['boards'];
        return styleBoardsBuilder(boards is List ? boards : const []);
      case AhviBlockType.visualBoard:
        final board = block.data['board'];
        return board is AhviVisualBoard
            ? visualBoardBuilder(board)
            : const SizedBox.shrink();
      case AhviBlockType.moduleCards:
      case AhviBlockType.checklist:
      case AhviBlockType.plan:
        final moduleCard = block.data['module_card'];
        if (moduleCard is AhviModuleCard) return moduleCardBuilder(moduleCard);
        return moduleCardsBuilder(_mapList(block.data['cards']));
      case AhviBlockType.wardrobeGap:
        return wardrobeGapBuilder?.call(block.data) ??
            _DefaultWardrobeGapCard(data: block.data);
      case AhviBlockType.text:
      case AhviBlockType.image:
      case AhviBlockType.unknown:
        return const SizedBox.shrink();
    }
  }
}

/// Style V2 — open-ended structured advice (body proportion / color / occasion).
class StyleAdviceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const StyleAdviceCard({super.key, required this.data});

  static const _titles = {
    'body_proportion_advice': 'PROPORTION ADVICE',
    'color_advice': 'COLOR ADVICE',
    'occasion_advice': 'OCCASION ADVICE',
  };

  // Per-mode ordered (label, key, glyph, color-ish).
  static const _sections = {
    'body_proportion_advice': [
      ['Principles', 'principles', '•'],
      ['Do', 'do', '✓'],
      ['Avoid', 'avoid', '✕'],
      ['Outfit examples', 'outfit_examples', '◆'],
    ],
    'color_advice': [
      ['Recommended', 'recommended_colors', '✓'],
      ['Avoid', 'avoid_colors', '✕'],
      ['Why', 'why', '•'],
      ['Outfit palettes', 'outfit_palettes', '◆'],
    ],
    'occasion_advice': [
      ['Do', 'do', '✓'],
      ['Avoid', 'avoid', '✕'],
      ['Better alternatives', 'better_alternatives', '→'],
      ['Safe routes', 'styling_routes', '◆'],
    ],
  };

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final mode = _s(data['type']);
    final sections = _sections[mode] ?? const [];
    final summary = _s(data['summary']);
    final hasAny = sections.any((s) => _strList(data[s[1]]).isNotEmpty);
    if (!hasAny && summary.isEmpty) return const SizedBox.shrink();
    debugPrint('AHVI_ADVICE_CARD_RENDERED mode=$mode');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titles[mode] ?? 'STYLE ADVICE',
            style: TextStyle(
              color: t.accent.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...sections.map((s) {
            final items = _strList(data[s[1]]);
            if (items.isEmpty) return const SizedBox.shrink();
            final danger = s[2] == '✕';
            final color = danger ? const Color(0xFFB0534A) : t.accent.primary;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s[0].toUpperCase(),
                    style: TextStyle(
                      color: t.mutedText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 3),
                  ...items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s[2],
                            style: TextStyle(
                              color: color,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              it,
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
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Style V2 — Transition Plan (keep / swap / add / avoid / dinner-ready).
class TransitionPlanCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const TransitionPlanCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final keep = _strList(data['keep']);
    final swap = _strList(data['swap']);
    final add = _strList(data['add']);
    final avoid = _strList(data['avoid']);
    final dinnerReady = _s(data['dinner_ready']);
    if (keep.isEmpty &&
        swap.isEmpty &&
        add.isEmpty &&
        avoid.isEmpty &&
        dinnerReady.isEmpty) {
      return const SizedBox.shrink();
    }
    debugPrint(
      'AHVI_TRANSITION_PLAN_RENDERED keep=${keep.length} swap=${swap.length} add=${add.length}',
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 15, color: t.accent.primary),
              const SizedBox(width: 6),
              Text(
                'TRANSITION STRATEGY',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _planSection('KEEP', keep, '✓', const Color(0xFF3A8A57), t),
          _planSection('SWAP', swap, '→', t.accent.primary, t),
          _planSection('ADD', add, '+', const Color(0xFF3A5C8C), t),
          _planSection('AVOID', avoid, '✕', const Color(0xFFB0534A), t),
          if (dinnerReady.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'DINNER READY',
              style: TextStyle(
                color: t.mutedText,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              dinnerReady,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planSection(
    String label,
    List<String> items,
    String glyph,
    Color color,
    dynamic t,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.mutedText,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    glyph,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      it,
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
      ),
    );
  }
}

/// Style V2 — "Why this fits YOU" stylist reasoning.
class StylistReasoningCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const StylistReasoningCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final archetype = _s(data['archetype']);
    final why = _s(data['why_this_fits_you']);
    final dna = _s(data['dna_alignment']);
    final wardrobe = _s(data['wardrobe_alignment']);
    if (archetype.isEmpty && why.isEmpty) return const SizedBox.shrink();
    debugPrint('AHVI_STYLIST_REASONING_RENDERED archetype=$archetype');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.panel, t.accent.primary.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin_rounded, size: 15, color: t.accent.primary),
              const SizedBox(width: 6),
              Text(
                'WHY THIS FITS YOU',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          if (archetype.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              archetype,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (why.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              why,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (dna.isNotEmpty) _reasonRow('Style DNA', dna, t),
          if (wardrobe.isNotEmpty) _reasonRow('Wardrobe', wardrobe, t),
        ],
      ),
    );
  }

  Widget _reasonRow(String label, String value, dynamic t) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(color: t.mutedText, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _s(dynamic v) => (v ?? '').toString().trim();

/// Complete the Look — local Meghna accessory inspiration assets. Backend
/// image_url wins where present; this is local fallback. Inspiration only,
/// never owned wardrobe.
class CompleteTheLookStrip extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const CompleteTheLookStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final assets = items
        .where((item) => _s(item['image_url'] ?? item['imageUrl']).isNotEmpty)
        .toList(growable: false);
    if (assets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPLETE THE LOOK',
            style: TextStyle(
              color: t.accent.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: assets.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final a = assets[i];
                final imageUrl = _s(a['image_url'] ?? a['imageUrl']);
                final name = _s(a['name'] ?? a['title'] ?? a['label']);
                return SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.mutedText, fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _strList(dynamic v) {
  if (v is! List) return const [];
  return v
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

/// Style V2 — premium Visual Inspiration card (no image yet).
class VisualInspirationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final MessageSender? onSendMessage;

  const VisualInspirationCard({
    super.key,
    required this.data,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final title = _s(data['title']).isEmpty
        ? 'Style Inspiration'
        : _s(data['title']);
    final aesthetic = _s(data['aesthetic']);
    final mood = _s(data['mood']);
    final palette = _strList(data['palette']);
    final hero = _s(data['hero_piece']);
    final silhouette = _s(data['silhouette']);
    final notes = _s(data['styling_notes']);
    final missing = data['missing_piece'] is Map
        ? Map<String, dynamic>.from(data['missing_piece'])
        : const <String, dynamic>{};

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.panel, t.accent.primary.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: t.accent.primary),
              const SizedBox(width: 6),
              Text(
                'VISUAL INSPIRATION',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          if (aesthetic.isNotEmpty || mood.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (aesthetic.isNotEmpty)
                  _Pill(text: aesthetic, color: t.accent.primary, filled: true),
                if (mood.isNotEmpty)
                  _Pill(text: mood, color: t.mutedText, filled: false),
              ],
            ),
          ],
          if (palette.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: palette
                  .map((c) => _PaletteChip(label: c, tokens: t))
                  .toList(growable: false),
            ),
          ],
          if (hero.isNotEmpty)
            _KeyValue(label: 'Hero piece', value: hero, tokens: t),
          if (silhouette.isNotEmpty)
            _KeyValue(label: 'Silhouette', value: silhouette, tokens: t),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notes,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (_s(missing['name']).isNotEmpty) ...[
            const SizedBox(height: 12),
            _MissingPieceCallout(
              missing: missing,
              contextData: data,
              tokens: t,
              onSendMessage: onSendMessage,
            ),
          ],
          CompleteTheLookStrip(
            items: _mapList(
              data['complete_the_look'] ?? data['completeTheLook'],
            ),
          ),
        ],
      ),
    );
  }
}

/// Style V2 — Missing Piece Intelligence card.
class MissingPieceIntelligenceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final MessageSender? onSendMessage;

  const MissingPieceIntelligenceCard({
    super.key,
    required this.data,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final owned = data['owned_percentage'];
    final items = _mapList(data['missing_items']);
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owned is num && owned > 0)
            Text(
              'You own ${owned.round()}% of this look',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Complete it with',
            style: TextStyle(color: t.mutedText, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (m) => _MissingPieceCallout(
              missing: m,
              contextData: data,
              tokens: t,
              onSendMessage: onSendMessage,
            ),
          ),
          _wardrobeReality(t),
          CompleteTheLookStrip(
            items: _mapList(
              data['complete_the_look'] ?? data['completeTheLook'],
            ),
          ),
        ],
      ),
    );
  }

  // Phase 5: "you own X / adding Y unlocks archetypes Z".
  Widget _wardrobeReality(dynamic t) {
    final owned = _strList(data['owned_items']);
    final adding = _strList(data['adding_items']);
    final unlocks = _strList(data['unlocks_archetypes']);
    if (owned.isEmpty && unlocks.isEmpty) return const SizedBox.shrink();
    Widget list(String label, List<String> xs, String glyph) {
      if (xs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.mutedText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            ...xs.map(
              (x) => Text(
                '$glyph $x',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list('YOU ALREADY OWN', owned, '✓'),
          list('ADDING', adding, '✓'),
          list('WOULD UNLOCK', unlocks, '◆'),
        ],
      ),
    );
  }
}

class _MissingPieceCallout extends StatelessWidget {
  final Map<String, dynamic> missing;
  final Map<String, dynamic> contextData;
  final dynamic tokens;
  final MessageSender? onSendMessage;

  const _MissingPieceCallout({
    required this.missing,
    this.contextData = const <String, dynamic>{},
    required this.tokens,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final name = _s(missing['name']);
    final category = _s(missing['category']);
    final reason = _s(missing['reason']);
    final imageUrl = _s(missing['image_url'] ?? missing['imageUrl']);
    final unlocks = _strList(missing['unlocks']);
    if (name.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accent.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                height: 116,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Missing: $name',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (category.isNotEmpty)
                _Pill(text: category, color: t.mutedText, filled: false),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (unlocks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unlocks
                  .map(
                    (u) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: t.panel,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.cardBorder),
                      ),
                      child: Text(
                        u,
                        style: TextStyle(color: t.mutedText, fontSize: 10.5),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () =>
                onSendMessage?.call(_findThisMessage(missing, contextData)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: t.accent.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, size: 13, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Find this',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _findThisMessage(
  Map<String, dynamic> missing,
  Map<String, dynamic> contextData,
) {
  final name = _s(missing['name'] ?? missing['item_name'] ?? missing['label']);
  final parts = <String>[];
  void add(String key, dynamic value) {
    final text = _s(value);
    if (text.isEmpty) return;
    parts.add('$key=$text');
  }

  add('category', missing['category']);
  add('subcategory', missing['subcategory'] ?? missing['sub_category']);
  add('color', missing['color']);
  add(
    'occasion',
    missing['occasion'] ??
        contextData['occasion'] ??
        contextData['title'] ??
        contextData['mood'],
  );
  add(
    'archetype',
    missing['archetype'] ??
        missing['style_archetype'] ??
        contextData['archetype'],
  );

  final suffix = parts.isEmpty ? '' : ' | ${parts.join(' | ')}';
  return 'Find this: $name$suffix';
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const _Pill({required this.text, required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  final String label;
  final dynamic tokens;
  const _PaletteChip({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _colorFromName(label) ?? t.mutedText,
              shape: BoxShape.circle,
              border: Border.all(color: t.cardBorder),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: t.textPrimary, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  final dynamic tokens;
  const _KeyValue({
    required this.label,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(color: t.mutedText, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color? _colorFromName(String name) {
  const map = <String, Color>{
    'black': Color(0xFF1A1A1A),
    'white': Color(0xFFF5F5F0),
    'cream': Color(0xFFF3EAD7),
    'stone': Color(0xFFCFC6B8),
    'navy': Color(0xFF24324A),
    'brown': Color(0xFF6B4A2F),
    'tan': Color(0xFFBfa37a),
    'olive': Color(0xFF6B6B3A),
    'grey': Color(0xFF9A9A9A),
    'gray': Color(0xFF9A9A9A),
    'charcoal': Color(0xFF36383B),
    'beige': Color(0xFFE3D8C3),
    'khaki': Color(0xFFB3A06B),
    'blue': Color(0xFF3A5C8C),
    'teal': Color(0xFF2E6F73),
    'burgundy': Color(0xFF6B2A35),
    'camel': Color(0xFFC19A6B),
    'ivory': Color(0xFFF7F2E7),
    'rust': Color(0xFFA8552E),
  };
  return map[name.toLowerCase().trim()];
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

class _DefaultWardrobeGapCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DefaultWardrobeGapCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final message = (data['message'] ?? data['response'] ?? '')
        .toString()
        .trim();
    final missing = _mapList(data['missing_items']);
    if (message.isEmpty && missing.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16, right: 20, left: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.isEmpty
                ? "I need a little more wardrobe coverage for this."
                : message,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: missing
                  .map(
                    (item) => Chip(
                      label: Text(
                        (item['label'] ?? item['name'] ?? item['category'])
                            .toString(),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}
