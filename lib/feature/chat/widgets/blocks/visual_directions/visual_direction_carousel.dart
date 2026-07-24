import 'package:flutter/material.dart';
import 'package:myapp/feature/chat/services/fashion_item_filter.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/board_render_completeness.dart';
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
    final nonEmpty = directions.where((item) => item.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();

    // Final rendered-role completeness guard. The backend may claim a complete
    // outfit, but after normalization/dedup/image-resolution a board can end up
    // as e.g. bottom+footwear+accessory. Skip those; if every board is invalid,
    // show one honest fallback instead of an accessory-only visual.
    final usable = <Map<String, dynamic>>[];
    for (final d in nonEmpty) {
      final result = boardCompletenessForDirection(d, editorialCover: editorialCover);
      if (result.complete) {
        usable.add(d);
      } else {
        debugPrint(
          'AHVI_BOARD_RENDER_COMPLETENESS_REJECT reason=${result.reason} '
          'roles=${result.roles.join(",")} '
          'title=${_text(d['title'] ?? d['direction_name'], '')}',
        );
      }
    }
    if (usable.isEmpty) {
      debugPrint('AHVI_BOARD_RENDER_ALL_REJECTED count=${nonEmpty.length}');
      return const _AllBoardsIncompleteFallback();
    }

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
                // Board layout is the default surface. Render the flat-lay 85
                // board only when it is viable (real outfit pieces). When it is
                // not, show a compact honest fallback — NEVER the old massive
                // VisualDirectionCard, which is now reserved for the tap-detail
                // sheet only.
                if (useBoard85 &&
                    _isBoardViable(
                      usable[index],
                      editorialCover,
                    ))
                  AhviOutfitBoardCard(
                    key: ValueKey('vd-board85-$index'),
                    direction: usable[index],
                    width: width,
                    onSendMessage: onSendMessage,
                    editorialCover: editorialCover,
                    onTapBoard: () => _openBoardDetail(
                      context,
                      direction: usable[index],
                      editorialCover: editorialCover,
                    ),
                  )
                else if (useBoard85)
                  _BoardDirectionFallbackCard(
                    key: ValueKey('vd-fallback-$index'),
                    direction: usable[index],
                    width: width,
                  )
                else
                  _VisualDirectionCard(
                    key: ValueKey('vd-legacy-$index'),
                    direction: usable[index],
                    width: width,
                    onSendMessage: onSendMessage,
                    editorialCover: editorialCover,
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

class _VisualDirectionCard extends StatelessWidget {
  final Map<String, dynamic> direction;
  final double width;
  final DirectionMessageSender? onSendMessage;
  final Map<String, dynamic> editorialCover;

  const _VisualDirectionCard({
    super.key,
    required this.direction,
    required this.width,
    this.onSendMessage,
    this.editorialCover = const {},
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final title = _text(direction['title'], 'Style Direction');
    final archetype = _text(direction['archetype'], '');
    // Backend's editorial polish surfaces a curated direction_name which
    // should win over the looser archetype/title fallbacks.
    final directionName = _text(
      direction['direction_name'] ?? direction['directionName'],
      '',
    );
    final primaryLabel = directionName.isNotEmpty
        ? directionName
        : (archetype.isNotEmpty ? archetype : title);
    // Prefer the server-capped short_note (≤2 sentences) so the card never
    // shows a wall of LLM prose. Falls back to existing fields.
    final whyItWorks = _text(
      direction['short_note'] ??
          direction['shortNote'] ??
          direction['why_it_works'] ??
          direction['whyThisWorks'] ??
          direction['why_this_works'],
      '',
    );
    final adjectives = _stringList(
      direction['adjectives'],
    ).take(3).toList(growable: false);
    final wardrobeMatchPct =
        direction['wardrobe_match_pct'] ?? direction['wardrobeMatchPct'];
    final badge = direction['badge'];
    final badgeMap = badge is Map ? Map<String, dynamic>.from(badge) : const {};
    final occasionFit = _text(badgeMap['occasion_fit'], '');
    final completeTheLookCopy = _text(
      direction['complete_the_look_copy'] ?? direction['completeTheLookCopy'],
      '',
    );
    final styleNote = _text(
      direction['styling_tip'] ??
          direction['style_note'] ??
          direction['styleNote'],
      '',
    );
    final imageUrl = _nullableText(
      direction['normalized_url'] ??
          direction['normalizedUrl'] ??
          direction['masked_url'] ??
          direction['maskedUrl'] ??
          direction['image_url'] ??
          direction['imageUrl'],
    );
    final missing = direction['missing_piece'];
    final rawMissing = missing is Map
        ? Map<String, dynamic>.from(missing)
        : const <String, dynamic>{};
    // Missing piece must be a fashion item — never recommend buying a
    // charger to "complete the look".
    final missingMap = rawMissing.isNotEmpty && isFashionItem(rawMissing)
        ? rawMissing
        : const <String, dynamic>{};

    // Discard the noisy legacy sections (description, palette, components
    // list, DNA section) so the experience reads as a stylist board, not a
    // metadata dump. Imagery + a single stylist line carry the card.
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            primaryLabel,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          if (adjectives.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              adjectives.map(_titleCaseWord).join('  •  '),
              style: TextStyle(
                color: t.mutedText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
          if (whyItWorks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              whyItWorks,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.42,
              ),
            ),
          ],
          if (styleNote.isNotEmpty &&
              styleNote.toLowerCase() != whyItWorks.toLowerCase()) ...[
            const SizedBox(height: 8),
            Text(
              styleNote,
              style: TextStyle(
                color: t.mutedText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (wardrobeMatchPct is int || occasionFit.isNotEmpty) ...[
            const SizedBox(height: 16),
            _LuxuryBadgeRow(
              matchPct: wardrobeMatchPct is int ? wardrobeMatchPct : null,
              occasionFit: occasionFit,
              tokens: t,
            ),
          ],
          if (_text(missingMap['name'], '').isNotEmpty ||
              completeTheLookCopy.isNotEmpty) ...[
            const SizedBox(height: 16),
            _MissingPieceCard(
              missing: missingMap,
              copy: completeTheLookCopy,
              tokens: t,
              onFindSimilar: onSendMessage == null
                  ? null
                  : () => onSendMessage!.call(
                      'Show shopping ideas for: ${_text(missingMap['name'], primaryLabel)}',
                    ),
            ),
          ],
          _OwnershipBlock(
            // Safety net: backend already sanitizes, but older payloads may
            // still carry non-fashion rows. Never render a charger chip.
            ownedItems: filterFashionItems(_mapList(direction['owned_items'])),
            // Single source of truth: the match % is shown by _LuxuryBadgeRow
            // above. Passing null here stops the duplicate "67% / WARDROBE
            // MATCH 67%" double-render — this block now shows only the owned
            // wardrobe chips.
            matchPct: null,
            tokens: t,
          ),
          const SizedBox(height: 12),
          _StickyActionBar(
            direction: direction,
            primaryLabel: primaryLabel,
            onSendMessage: onSendMessage,
            editorialCover: editorialCover,
            tokens: t,
          ),
        ],
      ),
    );
  }
}

// Family-inference fallback removed in favour of backend-provided
// owned_items. Trust > completeness — see _OwnershipBlock.

/// Renders true-ownership signals:
///
/// * Backend-provided ``owned_items`` become real thumbnail / name chips.
/// * If ``owned_items`` is absent but ``wardrobe_match_pct`` is known we
///   show the percentage banner alone — never fabricate chips.
/// * Without any signal we render nothing.
class _OwnershipBlock extends StatelessWidget {
  final List<Map<String, dynamic>> ownedItems;
  final int? matchPct;
  final dynamic tokens;

  const _OwnershipBlock({
    required this.ownedItems,
    required this.matchPct,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    if (ownedItems.isEmpty && matchPct == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Header now sits above the owned-item chips only; the match %
            // lives solely in the badge row to avoid a duplicate label.
            matchPct != null ? 'WARDROBE MATCH' : 'IN YOUR WARDROBE',
            style: TextStyle(
              color: t.mutedText,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          if (matchPct != null) ...[
            const SizedBox(height: 4),
            Text(
              '$matchPct%',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ],
          if (ownedItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ownedItems
                  .take(8)
                  .map((item) => _OwnedChip(item: item, tokens: t))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnedChip extends StatelessWidget {
  final Map<String, dynamic> item;
  final dynamic tokens;
  const _OwnedChip({required this.item, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final name = (item['name'] ?? '').toString();
    if (name.isEmpty) return const SizedBox.shrink();
    final url = (item['normalized_url'] ??
            item['normalizedUrl'] ??
            item['masked_url'] ??
            item['maskedUrl'] ??
            item['image_url'] ??
            item['imageUrl'])
        ?.toString()
        .trim();
    final thumb = (url != null && url.isNotEmpty)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _iconBox(t),
            ),
          )
        : _iconBox(t);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          thumb,
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(dynamic t) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: t.accent.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    alignment: Alignment.center,
    child: Icon(Icons.checkroom_rounded, size: 14, color: t.accent.primary),
  );
}

class _StickyActionBar extends StatefulWidget {
  final Map<String, dynamic> direction;
  final String primaryLabel;
  final DirectionMessageSender? onSendMessage;
  final Map<String, dynamic> editorialCover;
  final dynamic tokens;
  const _StickyActionBar({
    required this.direction,
    required this.primaryLabel,
    required this.onSendMessage,
    required this.editorialCover,
    required this.tokens,
  });

  @override
  State<_StickyActionBar> createState() => _StickyActionBarState();
}

class _StickyActionBarState extends State<_StickyActionBar> {
  bool _saved = false;
  bool _saving = false;

  String get _occasion {
    final coverOccasion = (widget.editorialCover['occasion_label'] ?? '')
        .toString()
        .trim();
    if (coverOccasion.isNotEmpty) return coverOccasion;
    final direct = (widget.direction['occasion'] ?? '').toString().trim();
    return direct.isNotEmpty ? direct : 'Curated Look';
  }

  String get _id => SavedBoardsStore.idFor(
    occasion: _occasion,
    directionName: widget.primaryLabel,
  );

  @override
  void initState() {
    super.initState();
    () async {
      final saved = await SavedBoardsStore.isSaved(_id);
      if (!mounted) return;
      setState(() => _saved = saved);
    }();
  }

  Future<void> _toggleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_saved) {
        await SavedBoardsStore.remove(_id);
        if (!mounted) return;
        setState(() {
          _saved = false;
          _saving = false;
        });
        return;
      }
      await SavedBoardsStore.saveBoard(
        occasion: _occasion,
        directionName: widget.primaryLabel,
        direction: widget.direction,
        editorialCover: widget.editorialCover,
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Saved to Style Boards'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final missingName = _text(
      (widget.direction['missing_piece'] is Map
              ? (widget.direction['missing_piece'] as Map)['name']
              : null) ??
          (widget.direction['missing_piece_name']),
      '',
    );
    final canSend = widget.onSendMessage != null;

    Future<void> emit(String message) async {
      if (!canSend) return;
      widget.onSendMessage!.call(message);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ActionButton(
          icon: _saved
              ? Icons.check_circle_rounded
              : Icons.favorite_border_rounded,
          label: _saved ? 'Saved' : 'Save',
          tokens: t,
          enabled: !_saving,
          accentColor: _saved ? const Color(0xFF2E7D5B) : null,
          onTap: _toggleSave,
        ),
        _ActionButton(
          icon: Icons.shuffle_rounded,
          label: 'Shuffle',
          tokens: t,
          enabled: canSend,
          onTap: () => emit('Show more looks like ${widget.primaryLabel}'),
        ),
        _ActionButton(
          icon: Icons.shopping_bag_outlined,
          label: 'Missing',
          tokens: t,
          enabled: canSend,
          onTap: () => emit(
            missingName.isNotEmpty
                ? 'Show shopping ideas for: $missingName'
                : 'Show shopping ideas for: ${widget.primaryLabel}',
          ),
        ),
        _ActionButton(
          icon: Icons.auto_awesome_rounded,
          label: 'Try On',
          tokens: t,
          enabled: false,
          onTap: () {},
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final dynamic tokens;
  final Color? accentColor;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.tokens,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final base = enabled ? t.textPrimary : t.mutedText.withValues(alpha: 0.55);
    final color = accentColor ?? base;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                icon,
                key: ValueKey('$icon-${color.toARGB32()}'),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// Luxury badge row: three discrete pills (stars + Recommended, wardrobe
/// match %, occasion fit). Reuses AHVI house weights / sizes; spacing
/// does the premium lift.
class _LuxuryBadgeRow extends StatelessWidget {
  final int? matchPct;
  final String occasionFit;
  final dynamic tokens;
  const _LuxuryBadgeRow({
    required this.matchPct,
    required this.occasionFit,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final pct = matchPct;
    String matchLabel;
    if (pct == null) {
      matchLabel = '';
    } else if (pct >= 95) {
      matchLabel = 'Perfect Wardrobe Match';
    } else if (pct >= 70) {
      matchLabel = '$pct% Wardrobe Match';
    } else {
      matchLabel = '$pct% Wardrobe Match';
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BadgePill(
          tokens: t,
          icon: Icons.star_rounded,
          label: 'Recommended',
          showStars: true,
        ),
        if (matchLabel.isNotEmpty)
          _BadgePill(
            tokens: t,
            icon: Icons.emoji_events_outlined,
            label: matchLabel,
          ),
        if (occasionFit.isNotEmpty)
          _BadgePill(
            tokens: t,
            icon: Icons.bolt_rounded,
            label: 'Occasion Fit: $occasionFit',
          ),
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic tokens;
  final bool showStars;
  const _BadgePill({
    required this.tokens,
    required this.icon,
    required this.label,
    this.showStars = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStars)
            for (var i = 0; i < 5; i++)
              Icon(Icons.star_rounded, size: 12, color: t.accent.primary)
          else
            Icon(icon, size: 13, color: t.accent.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium "Complete The Look" card. Stylist-led opportunity, never a
/// warning. Larger image, breathing room, optional Find Similar action.
class _MissingPieceCard extends StatelessWidget {
  final Map<String, dynamic> missing;
  final String copy;
  final VoidCallback? onFindSimilar;
  final dynamic tokens;
  const _MissingPieceCard({
    required this.missing,
    required this.copy,
    required this.tokens,
    this.onFindSimilar,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final name = _text(missing['name'], '');
    final imageUrl = _nullableText(
      missing['normalized_url'] ??
          missing['normalizedUrl'] ??
          missing['masked_url'] ??
          missing['maskedUrl'] ??
          missing['image_url'] ??
          missing['imageUrl'],
    );
    if (name.isEmpty && copy.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Complete the Look',
            style: TextStyle(
              color: t.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _missingPieceIcon(t),
                      )
                    : _missingPieceIcon(t),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    if (copy.isNotEmpty) ...[
                      if (name.isNotEmpty) const SizedBox(height: 4),
                      Text(
                        copy,
                        style: TextStyle(
                          color: t.mutedText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (onFindSimilar != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onFindSimilar,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Find Similar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _missingPieceIcon(dynamic t) => Container(
    width: 64,
    height: 64,
    color: t.accent.primary.withValues(alpha: 0.08),
    alignment: Alignment.center,
    child: Icon(Icons.checkroom_rounded, size: 28, color: t.accent.primary),
  );
}

bool _isBoardViable(Map<String, dynamic> direction, Map<String, dynamic> editorialCover) {
  // Garment-aware: classic (top+bottom+footwear) OR dress (dress+footwear) OR
  // >=3 real-image pieces with known roles. No positional "hero" requirement.
  return outfitBoardViable(direction, editorialCover: editorialCover);
}

/// Title-case a single word so adjectives render as "Refined" / "Sharp"
/// regardless of backend capitalization. Sentence-case only — does not
/// touch surrounding words or introduce upper-case-only treatment.
String _titleCaseWord(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
}

String _text(dynamic value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? fallback : text;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? null : text;
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

class _AllBoardsIncompleteFallback extends StatelessWidget {
  const _AllBoardsIncompleteFallback();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        "I could not build a complete outfit from those pieces yet - I need a "
        "top or dress with a bottom and footwear. Tell me the occasion or add a "
        "missing piece and I will restyle it.",
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
