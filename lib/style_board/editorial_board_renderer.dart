import 'package:flutter/material.dart';

import 'board_models.dart';
import 'editorial_board_layout_engine.dart';
import 'editorial_board_widgets.dart';

/// Inner canvas only: no save/share bar, no item boxes.
/// Put this inside the existing AHVI board card body.
class EditorialBoardCanvas extends StatelessWidget {
  final StyleBoardData board;
  final Set<String> lockedItemIds;
  final ValueChanged<String>? onToggleLock;

  const EditorialBoardCanvas({
    super.key,
    required this.board,
    this.lockedItemIds = const {},
    this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final generated = EditorialBoardLayoutEngine.resolve(
            board,
            width: w,
            height: h,
          );

          final placements = generated.placements.map((placement) {
            final position = placement.item.position;
            if (position == null || !position.isUsable) return placement;
            return placement.copyWith(
              x: position.x! * w,
              y: position.y! * h,
              width: position.width! * w,
              height: position.height! * h,
              rotation: position.rotation ?? placement.rotation,
              zIndex: position.z ?? placement.zIndex,
            );
          }).toList()..sort((a, b) => a.zIndex.compareTo(b.zIndex));
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const _EditorialBackgroundDecor(),
              ...placements.map((p) {
                final locked = lockedItemIds.contains(p.item.itemId);
                return Positioned(
                  left: p.x,
                  top: p.y,
                  width: p.width,
                  height: p.height,
                  child: KeyedSubtree(
                    key: p.item.hasStableIdentity
                        ? ValueKey<String>(p.item.itemId)
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: locked
                                ? Border.all(
                                    color: const Color(0xFF8A6A78),
                                    width: 1.5,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: EditorialBoardItem(
                            item: p.item,
                            rotation: p.rotation,
                          ),
                        ),
                        if (p.item.isRegenerating)
                          const ColoredBox(
                            color: Color(0x22FFFFFF),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        if (onToggleLock != null && p.item.isLockable)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Semantics(
                              button: true,
                              label:
                                  '${locked ? 'Unlock' : 'Lock'} ${p.item.name}',
                              child: IconButton(
                                key: ValueKey<String>('lock-${p.item.itemId}'),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                onPressed: () => onToggleLock!(p.item.itemId),
                                icon: Icon(
                                  locked
                                      ? Icons.lock_rounded
                                      : Icons.lock_outline_rounded,
                                  size: 19,
                                ),
                                tooltip: locked
                                    ? 'Locked ${p.item.name}'
                                    : 'Lock ${p.item.name}',
                              ),
                            ),
                          ),
                        if (locked)
                          const Positioned(
                            left: 4,
                            bottom: 4,
                            child: _LockedPill(),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _LockedPill extends StatelessWidget {
  const _LockedPill();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xDD8A6A78),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      'Locked',
      style: TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Premium board headline + summary above the collage.
///
/// Keep this lightweight (max two text lines) so the collage stays the focal
/// point. The expandable detail lives in [BoardStoryExpandable] below.
class BoardStoryHeader extends StatelessWidget {
  final StyleBoardData board;
  final EdgeInsetsGeometry padding;

  const BoardStoryHeader({
    super.key,
    required this.board,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final headline = board.story?.headline?.trim();
    final summary = board.summaryText?.trim();
    final hasHeadline = headline != null && headline.isNotEmpty;
    final hasSummary = summary != null && summary.isNotEmpty;
    if (!hasHeadline && !hasSummary) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeadline)
            Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: Color(0xFF2A2A2A),
              ),
            ),
          if (hasSummary) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.25,
                color: Color(0xFF6E6968),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsed-by-default "Why this works ›" panel that expands to show full
/// story details. Only renders rows where the backend supplied copy.
class BoardStoryExpandable extends StatefulWidget {
  final StyleBoardData board;
  final EdgeInsetsGeometry padding;

  const BoardStoryExpandable({
    super.key,
    required this.board,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  State<BoardStoryExpandable> createState() => _BoardStoryExpandableState();
}

class _BoardStoryExpandableState extends State<BoardStoryExpandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final story = widget.board.story;
    if (story == null || !story.hasExpandableContent) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Why this works',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A2A2A),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _open ? Icons.expand_less : Icons.chevron_right,
                  size: 16,
                  color: const Color(0xFF8A6A78),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: !_open
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _row('Why this works', widget.board.whyText),
                        _row('Personalized for you', story.personalNote),
                        _row('Occasion fit', story.occasionFit),
                        _row('Styling tip', widget.board.tipText),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _row(String label, String? body) {
    final text = body?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A6A78),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.32,
              color: Color(0xFF3C3A39),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorialBackgroundDecor extends StatelessWidget {
  const _EditorialBackgroundDecor();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _EditorialBackgroundPainter()),
      ),
    );
  }
}

class _EditorialBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Clean flat off-white canvas. The card's 0xFFFAF9F6 backing shows
    // through without decorative ovals competing with the garment cutouts.
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
