import 'package:flutter/material.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/editorial_board_renderer.dart';

/// A purpose-built, share-only outfit board.
///
/// The device Share previously captured the in-app card's RepaintBoundary, whose
/// opaque parent decoration sat OUTSIDE the boundary — so the exported PNG could
/// be transparent (black in WhatsApp dark mode), the dark text nearly invisible,
/// and the long why-it-works / styling-tip copy was baked into the image and
/// duplicated the WhatsApp caption.
///
/// This widget fixes all of that: an explicit opaque [_bg] lives INSIDE the
/// [RepaintBoundary], only branding + title + occasion + the canonical garment
/// canvas + a small footer are captured, and the paragraphs are excluded.
class ShareableOutfitBoard extends StatelessWidget {
  final GlobalKey boundaryKey;
  final String title;
  final String occasion;
  final List<StyleBoardItem> items;
  final double width;

  const ShareableOutfitBoard({
    super.key,
    required this.boundaryKey,
    required this.title,
    required this.occasion,
    required this.items,
    this.width = 360,
  });

  // Opaque canvas — never transparent, safe in dark-mode chat apps.
  static const Color kShareBackground = Color(0xFFFAF9F6);
  static const Color _ink = Color(0xFF2A2A2A);
  static const Color _accent = Color(0xFF8A6A78);

  @override
  Widget build(BuildContext context) {
    final height = width * 5 / 4; // 4:5 share ratio.
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        width: width,
        height: height,
        color: kShareBackground,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            _brandingRow(),
            const SizedBox(height: 10),
            Text(
              title.isEmpty ? 'AHVI Look' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 20,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (occasion.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _occasionChip(occasion.trim()),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: EditorialBoardCanvas(
                board: StyleBoardData(
                  title: title,
                  occasion: occasion,
                  items: items,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Styled on AHVI',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandingRow() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _ink, shape: BoxShape.circle),
            child: const Text(
              'A',
              style: TextStyle(
                color: kShareBackground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'AHVI',
            style: TextStyle(
              color: _ink,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _occasionChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _accent,
            fontSize: 11.5,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
