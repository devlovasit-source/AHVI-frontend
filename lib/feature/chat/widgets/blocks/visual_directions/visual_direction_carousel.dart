import 'package:flutter/material.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/curation_reveal.dart';
import 'package:myapp/theme/theme_tokens.dart';

/// Public so the chat stream (ahvi_stylist_chat / block renderer) can suppress
/// the legacy text-heavy "Visual Inspiration" card when the flat-lay 85 board
/// is the active renderer. Default on — the modern board is canonical.
const bool kVisualBoard85Enabled = bool.fromEnvironment(
  'ENABLE_VISUAL_BOARD_85_LAYOUT',
  defaultValue: true,
);

const bool _enableVisualBoard85Layout = kVisualBoard85Enabled;

/// Signature for sticky-action-bar invocations on a direction card.
typedef DirectionMessageSender = void Function(String message);

class VisualDirectionCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> directions;
  final double? cardWidth;
  final Map<String, dynamic> editorialCover;

  /// Optional sender used by the sticky action bar inside each direction
  /// card. When null the bar still renders but each action becomes a soft
  /// no-op so unmounted callbacks never crash.
  final DirectionMessageSender? onSendMessage;

  /// Toggle for the premium one-shot reveal animation. Defaults to on; the
  /// loader self-disables when there are no directions to gate.
  final bool curationReveal;
  final bool? use85Layout;

  const VisualDirectionCarousel({
    super.key,
    required this.directions,
    this.cardWidth,
    this.editorialCover = const {},
    this.onSendMessage,
    this.curationReveal = true,
    this.use85Layout,
  });

  @override
  Widget build(BuildContext context) {
    final usable = directions.where((item) => item.isNotEmpty).toList();
    if (usable.isEmpty) return const SizedBox.shrink();

    // Wider hero — premium boards command the viewport instead of feeling
    // like nested chat cards. ~360 keeps two boards peeking in on a 6"
    // device while letting the hero collage breathe.
    final width = cardWidth ?? 360.0;
    final useBoard85 = use85Layout ?? _enableVisualBoard85Layout;
    final hasCover =
        !useBoard85 &&
        editorialCover.isNotEmpty &&
        _text(editorialCover['direction_name'], '').isNotEmpty;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          EditorialCoverCard(cover: editorialCover),
          const SizedBox(height: 14),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < usable.length; index++) ...[
                // Single authoritative action surface: ANY direction that
                // carries an underlying outfit payload renders through
                // AhviOutfitBoardCard (flat-lay when the assets are renderable,
                // its own _IncompleteBoardFallback otherwise) so OutfitActionBar's
                // Appwrite-backed Save + native Share are ALWAYS present — even on
                // weak_occasion_match with blank cutout_status/board_status where
                // the transparent renderer rejects every image. No second
                // Save/Share implementation is used.
                Builder(
                  builder: (cardContext) {
                    final direction = usable[index];
                    final underlyingCount =
                        _underlyingOutfitItems(direction).length;
                    if (underlyingCount > 0) {
                      debugPrint(
                        'AHVI_STYLE_CARD_PATH path=outfit_board '
                        'response_type=${_directionResponseType(direction, editorialCover)} '
                        'renderable_asset_count=${_renderableAssetCount(direction)} '
                        'underlying_item_count=$underlyingCount',
                      );
                      return AhviOutfitBoardCard(
                        key: ValueKey('vd-board-$index'),
                        direction: direction,
                        width: width,
                        onSendMessage: onSendMessage,
                        editorialCover: editorialCover,
                        onTapBoard: () => _openBoardDetail(
                          cardContext,
                          direction: direction,
                          editorialCover: editorialCover,
                        ),
                      );
                    }
                    return _BoardDirectionFallbackCard(
                      key: ValueKey('vd-fallback-$index'),
                      direction: direction,
                      width: width,
                    );
                  },
                ),
                if (index != usable.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    );

    if (!curationReveal) return body;
    final occasionLabel = _text(
      editorialCover['occasion_label'],
      '',
    ).toUpperCase();
    final venueLabel = _text(editorialCover['venue'], '');
    return CurationReveal(
      occasionLabel: occasionLabel,
      venueLabel: venueLabel,
      directionCount: usable.length,
      child: body,
    );
  }

  /// Opens the legacy stylist-reasoning content (why_it_works, hero_piece,
  /// palette/adjectives, style_note, wardrobe match, occasion fit, missing
  /// piece, complete-the-look) in a tap-only detail sheet. The flat-lay board
  /// stays visual-first in the chat stream; the reasoning lives here on tap so
  /// it is never duplicated above the board.
  void _openBoardDetail(
    BuildContext context, {
    required Map<String, dynamic> direction,
    required Map<String, dynamic> editorialCover,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AhviOutfitBoardDetailSheet(
        direction: direction,
        editorialCover: editorialCover,
        onSendMessage: (message) {
          Navigator.of(sheetContext).pop();
          onSendMessage?.call(message);
        },
      ),
    );
  }
}

/// Tap-detail sheet for a flat-lay board. TEXT-ONLY reasoning — the board
/// itself is the visual, so the sheet carries no image, no badges, no wardrobe
/// score and no action bar. Only the direction name, mood tags and "Why AHVI
/// selected this".
class AhviOutfitBoardDetailSheet extends StatelessWidget {
  final Map<String, dynamic> direction;
  final Map<String, dynamic> editorialCover;
  final DirectionMessageSender? onSendMessage;

  const AhviOutfitBoardDetailSheet({
    super.key,
    required this.direction,
    this.editorialCover = const {},
    this.onSendMessage,
  });

  String get _title => _text(
    direction['direction_name'] ??
        direction['directionName'] ??
        direction['archetype'] ??
        direction['style_direction'] ??
        direction['styleDirection'] ??
        direction['title'],
    'Style Direction',
  );

  List<String> get _moodTags => _stringList(
    direction['mood_words'] ?? direction['moodWords'] ?? direction['adjectives'],
  ).take(4).toList(growable: false);

  List<String> get _reasons {
    final seen = <String>{};
    final out = <String>[];
    for (final value in [
      direction['rationale'],
      direction['reason'],
      direction['why'],
      direction['short_note'] ?? direction['shortNote'],
      direction['why_it_works'] ??
          direction['whyThisWorks'] ??
          direction['why_this_works'],
      direction['styling_tip'] ??
          direction['style_note'] ??
          direction['styleNote'],
    ]) {
      final text = _text(value, '');
      if (text.isEmpty) continue;
      final key = text.toLowerCase();
      if (seen.add(key)) out.add(text);
      if (out.length >= 3) break;
    }
    return out;
  }

  // Pieces text must describe what is ACTUALLY on the board. Derive names from
  // the rendered board_items (the matched assets), not direction.items/pieces
  // (the LLM's ideal piece names) — otherwise the sheet says "Tailored Khaki
  // Trouser / White Sneakers" while the card shows cream shorts + formal shoes.
  List<String> get _pieces {
    final boardItems = _mapList(direction['board_items'] ?? direction['boardItems']);
    if (boardItems.isNotEmpty) {
      final names = <String>[];
      final seen = <String>{};
      for (final it in boardItems) {
        final name = _text(it['name'] ?? it['title'] ?? it['label'], '');
        if (name.isEmpty) continue;
        if (seen.add(name.toLowerCase())) names.add(name);
      }
      if (names.isNotEmpty) return names.take(6).toList(growable: false);
    }
    return _stringList(direction['items'] ?? direction['pieces'])
        .take(6)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final reasons = _reasons;
    final pieces = _pieces;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.32,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.mutedText.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
              if (_moodTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _moodTags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: t.accent.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'WHY AHVI SELECTED THIS',
                  style: TextStyle(
                    color: t.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 10),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: t.accent.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            reason,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 18),
                Text(
                  'A curated direction picked to fit the occasion and your style.',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
              if (pieces.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'PIECES',
                  style: TextStyle(
                    color: t.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pieces.join('  •  '),
                  style: TextStyle(
                    color: t.mutedText,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Magazine-style cover header that frames the curated looks below.
/// Renders the occasion label, lead direction name, wardrobe-match badge
/// and the curated-for benefit triad.
class EditorialCoverCard extends StatelessWidget {
  final Map<String, dynamic> cover;
  const EditorialCoverCard({super.key, required this.cover});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final occasion = _text(cover['occasion_label'], 'CURATED LOOK');
    final direction = _text(cover['direction_name'], 'Curated Direction');
    final pct = cover['wardrobe_match_pct'];
    final curatedFor = _stringList(cover['curated_for']).take(3).toList();
    final badge = cover['badge'];
    final occasionFit = badge is Map ? _text((badge)['occasion_fit'], '') : '';

    // Drop the visible border so the cover reads as part of the page,
    // not a nested chip. AHVI house weights only — w700 max.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            occasion,
            style: TextStyle(
              color: t.mutedText,
              fontSize: 11.5,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            direction,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.08,
            ),
          ),
          if (pct is int) ...[
            const SizedBox(height: 18),
            Text(
              'WARDROBE MATCH',
              style: TextStyle(
                color: t.mutedText,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                if (occasionFit.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    '$occasionFit Fit',
                    style: TextStyle(
                      color: t.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 12),
          ],
          if (curatedFor.isNotEmpty) ...[
            Text(
              'CURATED FOR',
              style: TextStyle(
                color: t.mutedText,
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: curatedFor
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: t.accent.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
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

/// Compact, honest fallback shown when the 85 board is the active layout but a
/// direction lacks the pieces to render a real board. Deliberately minimal —
/// no hero image, no wardrobe-match, no Recommended badge, no ownership block,
/// no action bar — so the old premium card never leaks back into the stream.
class _BoardDirectionFallbackCard extends StatelessWidget {
  final Map<String, dynamic> direction;
  final double width;

  const _BoardDirectionFallbackCard({
    super.key,
    required this.direction,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final title = _text(
      direction['direction_name'] ??
          direction['directionName'] ??
          direction['archetype'] ??
          direction['title'],
      'Style Direction',
    );
    final note = _text(
      direction['short_note'] ??
          direction['shortNote'] ??
          direction['why_it_works'] ??
          direction['why_this_works'],
      '',
    );

    final hasRoles = outfitBoardHasRoles(direction, editorialCover: const {});
    final String fallbackMessage = hasRoles
        ? 'Found outfit pieces, but board images are not ready yet.'
        : 'Board view needs complete pieces — a top, bottom, and footwear image. '
            'Showing this as a direction for now.';
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 14,
                color: t.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fallbackMessage,
                  style: TextStyle(
                    color: t.mutedText,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _underlyingOutfitItems(
  Map<String, dynamic> direction,
) {
  for (final key in const ['board_items', 'boardItems', 'items', 'pieces']) {
    final value = direction[key];
    if (value is List) {
      final items = value
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      if (items.isNotEmpty) return items;
    }
  }
  return const <Map<String, dynamic>>[];
}

int _renderableAssetCount(Map<String, dynamic> direction) {
  var count = 0;
  for (final item in _underlyingOutfitItems(direction)) {
    final url =
        (item['board_image_url'] ??
                item['transparent_image_url'] ??
                item['cutout_url'] ??
                '')
            .toString()
            .trim();
    if (url.isNotEmpty) count++;
  }
  return count;
}

String _directionResponseType(
  Map<String, dynamic> direction,
  Map<String, dynamic> cover,
) => (direction['response_type'] ??
        direction['type'] ??
        cover['response_type'] ??
        cover['type'] ??
        '')
    .toString();

String _text(dynamic value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? fallback : text;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty && item != 'null')
      .toList(growable: false);
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
