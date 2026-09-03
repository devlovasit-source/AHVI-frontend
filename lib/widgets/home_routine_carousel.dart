import 'package:flutter/material.dart';

/// One Home daily-summary card's data. All text comes from the existing Home
/// summary provider / fallback logic — this widget only lays it out.
@immutable
class HomeRoutineCardData {
  final IconData icon;
  final Color color; // module pastel accent
  final String label; // module name — never ellipsized
  final String primary; // headline (max 2 lines)
  final String context; // supporting copy (up to 2 lines)
  final String stateLabel; // compact pill text (e.g. Done / In progress)
  final String cta; // always-visible call to action
  final bool done;
  final bool overdue; // medicine-only subtle red tint
  final VoidCallback onOpen;

  const HomeRoutineCardData({
    required this.icon,
    required this.color,
    required this.label,
    required this.primary,
    required this.context,
    required this.stateLabel,
    required this.cta,
    required this.done,
    required this.overdue,
    required this.onOpen,
  });
}

/// Palette pulled from the Home theme so the carousel matches the surrounding
/// UI without importing the theme extension (keeps it unit-testable).
@immutable
class HomeRoutinePalette {
  final Color accent;
  final Color border;
  final Color cardColor; // card background
  final Color textHeading;
  final Color textMuted;
  final Color onAccent;
  const HomeRoutinePalette({
    required this.accent,
    required this.border,
    required this.cardColor,
    required this.textHeading,
    required this.textMuted,
    required this.onAccent,
  });
}

/// Horizontally snapping five-card carousel: one readable card + a peek of the
/// next, with a compact segmented page indicator. Replaces the old fixed-width
/// row where every card was clipped to ~88 logical px.
class HomeRoutineCarousel extends StatefulWidget {
  final List<HomeRoutineCardData> cards;
  final HomeRoutinePalette palette;
  final double viewportFraction;

  const HomeRoutineCarousel({
    super.key,
    required this.cards,
    required this.palette,
    this.viewportFraction = 0.86,
  });

  @override
  State<HomeRoutineCarousel> createState() => _HomeRoutineCarouselState();
}

class _HomeRoutineCarouselState extends State<HomeRoutineCarousel> {
  late final PageController _pageCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: widget.viewportFraction);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    if (!mounted) return;
    setState(() => _page = i);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox.shrink();
    final p = widget.palette;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: cards.length,
            padEnds: false, // left-align the first card, peek the next
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RoutineCard(data: cards[i], palette: p),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _SegmentedIndicator(
          count: cards.length,
          active: _page.clamp(0, cards.length - 1),
          activeColor: p.accent,
          inactiveColor: p.border,
        ),
      ],
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final HomeRoutineCardData data;
  final HomeRoutinePalette palette;
  const _RoutineCard({required this.data, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final overdue = data.overdue && !data.done;
    // Subtle red/pink tint only when medicine is overdue.
    final bg = overdue
        ? Color.alphaBlend(const Color(0x22E5484D), p.cardColor)
        : p.cardColor;
    final borderColor = overdue
        ? const Color(0xFFE5484D).withOpacity(0.45)
        : (data.done ? p.accent.withOpacity(0.25) : p.border.withOpacity(0.5));

    return GestureDetector(
      behavior: HitTestBehavior.opaque, // entire card tappable
      onTap: data.onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1 & 2 — icon + module name + compact status pill
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.color.withOpacity(0.15),
                  ),
                  child: Icon(data.icon, size: 18, color: data.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible, // title never ellipsized
                    style: TextStyle(
                      color: p.textHeading,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  text: data.stateLabel,
                  done: data.done,
                  overdue: overdue,
                  palette: p,
                ),
              ],
            ),
            // 3 — primary headline (max 2 lines). Flexible so it yields first
            // if the card is unusually short — never overflows.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  data.primary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textHeading,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // 4 — supporting context, up to 2 lines. Flexible + LayoutBuilder
            // (same pattern as the Prep & Plan card's description): on a
            // short card this hides cleanly once there's no room for even
            // one full line, instead of being squeezed into a partial-line
            // clipped fragment.
            if (data.context.trim().isNotEmpty)
              Flexible(
                child: LayoutBuilder(
                  builder: (context, contextConstraints) {
                    const oneLineHeight = 12.0 * 1.3;
                    if (contextConstraints.maxHeight < oneLineHeight) {
                      return const SizedBox.shrink();
                    }
                    final allowTwoLines =
                        contextConstraints.maxHeight >= oneLineHeight * 2;
                    return Text(
                      data.context,
                      maxLines: allowTwoLines ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: overdue ? const Color(0xFFE5484D) : p.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            // 5 — always-visible CTA
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.cta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_forward_rounded, size: 14, color: p.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool done;
  final bool overdue;
  final HomeRoutinePalette palette;
  const _StatusPill({
    required this.text,
    required this.done,
    required this.overdue,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = overdue
        ? const Color(0xFFE5484D)
        : (done ? palette.accent : palette.textMuted);
    final hasText = text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hasText ? 8 : 5, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : (overdue
                    ? Icons.error_outline_rounded
                    : Icons.access_time_rounded),
            size: 13,
            color: fg,
          ),
          if (hasText) ...[
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentedIndicator extends StatelessWidget {
  final int count;
  final int active;
  final Color activeColor;
  final Color inactiveColor;
  const _SegmentedIndicator({
    required this.count,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: isActive ? 18 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: isActive ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(100),
          ),
        );
      }),
    );
  }
}
