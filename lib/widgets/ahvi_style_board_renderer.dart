// ============================================================
// AHVI canonical style board renderer
//
// Single source of truth for how a style board is laid out across
// the app — replaces the divergent paths in boards.dart / occasion.dart
// / editorial_board_renderer.dart so every screen shows the same
// curated AHVI structure:
//
//    Curated by AHVI
//   Title
//   Occasion Chip
//   Style DNA Chips
//   Hero Composition (collage)
//   Dynamic Accessories
//   AHVI Stylist Note (story.why)
//   Complete The Look
//   [Find This] [Save Look] [More Like This] [Virtual Try-On]
//
// Consumers pass:
//   - a StyleBoardData
//   - optional callbacks for the action buttons
//
// The renderer is purely presentational — no networking, no state —
// so it can be embedded inside any existing scaffold without changing
// the host screen's behavior.
// ============================================================

import 'package:flutter/material.dart';

import '../style_board/board_models.dart';
import '../style_board/editorial_board_renderer.dart';

/// Action callback signature for the bottom-row buttons.
typedef BoardActionCallback = void Function(StyleBoardData board);

class AhviStyleBoardRenderer extends StatelessWidget {
  final StyleBoardData board;
  final BoardActionCallback? onFindThis;
  final BoardActionCallback? onSaveLook;
  final BoardActionCallback? onMoreLikeThis;
  final BoardActionCallback? onVirtualTryOn;

  /// Compact mode trims the action row and the Complete-The-Look section
  /// for use inside dense lists (occasion.dart preview cards).
  final bool compact;

  /// Height of the central collage panel. Defaults to 360 for the full
  /// chat board, 220 for compact mode.
  final double? collageHeight;

  const AhviStyleBoardRenderer({
    super.key,
    required this.board,
    this.onFindThis,
    this.onSaveLook,
    this.onMoreLikeThis,
    this.onVirtualTryOn,
    this.compact = false,
    this.collageHeight,
  });

  @override
  Widget build(BuildContext context) {
    final story = board.story;
    final occasionLabel = board.roleLabel?.trim();
    final generatedTitle = (story?.headline?.trim().isNotEmpty == true)
        ? story!.headline!.trim()
        : board.title;
    final title = generatedTitle.trim().isNotEmpty
        ? generatedTitle.trim()
        : (board.styleArchetype?.trim().isNotEmpty == true
              ? board.styleArchetype!.trim()
              : 'Styled for You');
    final secondaryTitle = [
      if (board.boardRole?.trim().isNotEmpty == true) board.boardRole!.trim(),
      if (generatedTitle.trim().isNotEmpty &&
          generatedTitle.trim().toLowerCase() != title.toLowerCase())
        generatedTitle.trim(),
    ].join(' · ');
    final summary = board.summaryText?.trim();
    final why = board.whyText?.trim();
    final tip = board.tipText?.trim();
    final personalNote = story?.personalNote?.trim();
    final occasionFit = story?.occasionFit?.trim();
    final styleDnaChips = _styleDnaChips(board);
    final accessories = _accessoryItems(board);
    final coreItems = _nonAccessoryItems(board);

    final double effectiveCollageHeight =
        collageHeight ?? (compact ? 220.0 : 360.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Curated by AHVI strip ─────────────────────────────────
            const _CuratedByAhviBadge(),
            const SizedBox(height: 8),

            // ── Title ─────────────────────────────────────────────────
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 16 : 19,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: const Color(0xFF1F1F1F),
                height: 1.15,
              ),
            ),
            if (secondaryTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                secondaryTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6E6968),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6E6968),
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 10),

            // ── Occasion chip + Style DNA chips ───────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (occasionLabel != null && occasionLabel.isNotEmpty)
                  _Chip(label: occasionLabel, kind: _ChipKind.occasion),
                ...styleDnaChips.map(
                  (c) => _Chip(label: c, kind: _ChipKind.dna),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Hero collage (EditorialBoardCanvas does the work) ─────
            SizedBox(
              height: effectiveCollageHeight,
              child: EditorialBoardCanvas(board: board),
            ),

            // ── Dynamic Accessories strip ─────────────────────────────
            if (accessories.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AccessoryStrip(accessories: accessories),
            ],

            // ── AHVI Stylist Note (story.why) ─────────────────────────
            if (why != null && why.isNotEmpty) ...[
              const SizedBox(height: 12),
              _StylistNote(text: why),
            ],

            // ── Expanded story rows (personalized / occasion / tip) ────
            if (!compact && story != null && story.hasExpandableContent)
              BoardStoryExpandable(board: board),

            // ── Complete The Look (core items) ─────────────────────────
            if (!compact && coreItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CompleteTheLook(items: coreItems),
            ],

            // ── Action row ─────────────────────────────────────────────
            if (!compact) ...[
              const SizedBox(height: 14),
              _ActionRow(
                board: board,
                onFindThis: onFindThis,
                onSaveLook: onSaveLook,
                onMoreLikeThis: onMoreLikeThis,
                onVirtualTryOn: onVirtualTryOn,
              ),
              if (personalNote != null || occasionFit != null || tip != null)
                const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  static List<String> _styleDnaChips(StyleBoardData board) {
    final chips = <String>[];
    final story = board.story;
    // Headline isn't a DNA chip — it's the title. Pull a few keywords
    // from story.summary / occasionFit to give the user a quick read.
    void addFromText(String? text) {
      if (text == null) return;
      final t = text.toLowerCase();
      for (final kw in [
        'minimal',
        'editorial',
        'modern',
        'clean',
        'tailored',
        'polished',
        'casual',
        'street',
        'classic',
      ]) {
        if (t.contains(kw) && !chips.contains(kw)) chips.add(kw);
      }
    }

    addFromText(story?.summary);
    addFromText(story?.occasionFit);
    return chips.take(3).toList();
  }

  static List<StyleBoardItem> _accessoryItems(StyleBoardData board) =>
      board.items.where((i) => i.role == BoardItemRole.accessory).toList();

  static List<StyleBoardItem> _nonAccessoryItems(StyleBoardData board) =>
      board.items.where((i) => i.role != BoardItemRole.accessory).toList();
}

// ============================================================
// Sub-widgets
// ============================================================

class _CuratedByAhviBadge extends StatelessWidget {
  const _CuratedByAhviBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.auto_awesome, size: 12, color: Color(0xFF8A6A78)),
        SizedBox(width: 4),
        Text(
          'CURATED BY AHVI',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: Color(0xFF8A6A78),
          ),
        ),
      ],
    );
  }
}

enum _ChipKind { occasion, dna }

class _Chip extends StatelessWidget {
  final String label;
  final _ChipKind kind;

  const _Chip({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isOccasion = kind == _ChipKind.occasion;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOccasion ? const Color(0xFFF3EAF1) : const Color(0xFFF1F4FB),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: isOccasion
              ? const Color(0xFF8A6A78)
              : const Color(0xFF4E5C7F),
        ),
      ),
    );
  }
}

class _AccessoryStrip extends StatelessWidget {
  final List<StyleBoardItem> accessories;

  const _AccessoryStrip({required this.accessories});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accessories.length,
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final acc = accessories[i];
          return Container(
            width: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4EE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E1D8)),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(4),
            child: acc.imageUrl.isNotEmpty
                ? Image.network(acc.imageUrl, fit: BoxFit.contain)
                : const Center(
                    child: Icon(Icons.check_box_outline_blank,
                        size: 16, color: Color(0xFF8A6A78)),
                  ),
          );
        },
      ),
    );
  }
}

class _StylistNote extends StatelessWidget {
  final String text;

  const _StylistNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE6DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.format_quote, size: 14, color: Color(0xFF8A6A78)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF3C3A39),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteTheLook extends StatelessWidget {
  final List<StyleBoardItem> items;

  const _CompleteTheLook({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COMPLETE THE LOOK',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Color(0xFF8A6A78),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (it) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F4EE),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Text(
                    it.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3C3A39),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final StyleBoardData board;
  final BoardActionCallback? onFindThis;
  final BoardActionCallback? onSaveLook;
  final BoardActionCallback? onMoreLikeThis;
  final BoardActionCallback? onVirtualTryOn;

  const _ActionRow({
    required this.board,
    this.onFindThis,
    this.onSaveLook,
    this.onMoreLikeThis,
    this.onVirtualTryOn,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onFindThis != null)
          _ActionButton(
            label: 'Find This',
            icon: Icons.search,
            onTap: () => onFindThis!(board),
          ),
        if (onSaveLook != null)
          _ActionButton(
            label: 'Save Look',
            icon: Icons.bookmark_outline,
            primary: true,
            onTap: () => onSaveLook!(board),
          ),
        if (onMoreLikeThis != null)
          _ActionButton(
            label: 'More Like This',
            icon: Icons.refresh,
            onTap: () => onMoreLikeThis!(board),
          ),
        if (onVirtualTryOn != null)
          _ActionButton(
            label: 'Virtual Try-On',
            icon: Icons.camera_alt_outlined,
            onTap: () => onVirtualTryOn!(board),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? const Color(0xFF1F1F1F) : const Color(0xFFF1ECE2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: primary ? Colors.white : const Color(0xFF3C3A39),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : const Color(0xFF3C3A39),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
