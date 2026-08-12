import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One garment for the share composition. [role] is a lowercase slot
/// (top / bottom / footwear / dress / outerwear / accessory).
class ShareBoardItem {
  final String role;
  final String imageUrl;
  const ShareBoardItem({required this.role, required this.imageUrl});
}

/// A purpose-built, share-only outfit board.
///
/// The device Share previously captured the in-app card's RepaintBoundary, whose
/// opaque parent decoration sat OUTSIDE the boundary — so the exported PNG could
/// be transparent (black in WhatsApp dark mode), the dark text nearly invisible,
/// and the long why-it-works / styling-tip copy was baked into the image and
/// duplicated the WhatsApp caption.
///
/// This widget fixes all of that: an explicit opaque [_bg] lives INSIDE the
/// [RepaintBoundary], only branding + title + occasion + a tightened garment
/// canvas + a small footer are captured, and the paragraphs are excluded. The
/// in-app card is untouched.
class ShareableOutfitBoard extends StatelessWidget {
  final GlobalKey boundaryKey;
  final String title;
  final String occasion;
  final List<ShareBoardItem> items;
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
            Expanded(child: _ShareCanvas(items: items)),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: 'Styled on ',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 11,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: 'AHVI',
                    style: GoogleFonts.anton(
                      color: _accent,
                      fontSize: 11,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w400,
                      height: 1.0,
                    ),
                  ),
                ],
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
      Text(
        'AHVI',
        style: GoogleFonts.anton(
          color: _ink,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w400,
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

/// Tight three-piece flat-lay: top upper-left, bottom large on the right,
/// footwear larger in the lower-left — occupying ~75% of the canvas. Extra
/// pieces (accessory / outerwear / dress) get sensible slots so nothing is lost.
class _ShareCanvas extends StatelessWidget {
  final List<ShareBoardItem> items;
  const _ShareCanvas({required this.items});

  // Normalized (x, y, width, height) boxes per role.
  static const Map<String, List<double>> _slots = {
    'top': [0.02, 0.00, 0.48, 0.46],
    'outerwear': [0.00, 0.00, 0.50, 0.52],
    'bottom': [0.50, 0.28, 0.48, 0.66],
    'dress': [0.30, 0.02, 0.52, 0.82],
    'footwear': [0.04, 0.60, 0.46, 0.36],
    'accessory': [0.66, 0.02, 0.26, 0.26],
    'bag': [0.66, 0.02, 0.28, 0.28],
  };
  // Fallback boxes for unknown roles / overflow, still ~75% coverage.
  static const List<List<double>> _generic = [
    [0.03, 0.02, 0.46, 0.46],
    [0.50, 0.28, 0.47, 0.66],
    [0.05, 0.60, 0.44, 0.36],
    [0.62, 0.04, 0.30, 0.30],
    [0.30, 0.32, 0.34, 0.34],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0 || items.isEmpty) {
          return const SizedBox.shrink();
        }
        final placed = <Widget>[];
        final usedRoles = <String>{};
        var genericIndex = 0;
        for (final item in items.take(5)) {
          List<double>? box = _slots[item.role];
          if (box == null || usedRoles.contains(item.role)) {
            box = _generic[genericIndex % _generic.length];
            genericIndex++;
          } else {
            usedRoles.add(item.role);
          }
          placed.add(
            Positioned(
              left: box[0] * w,
              top: box[1] * h,
              width: box[2] * w,
              height: box[3] * h,
              child: _ShareGarment(url: item.imageUrl, role: item.role),
            ),
          );
        }
        return Stack(clipBehavior: Clip.hardEdge, children: placed);
      },
    );
  }
}

class _ShareGarment extends StatelessWidget {
  final String url;
  final String role;
  const _ShareGarment({required this.url, required this.role});

  @override
  Widget build(BuildContext context) {
    // Footwear reads small inside its transparent PNG, so nudge its zoom up.
    final scale = role == 'footwear' ? 1.30 : 1.06;
    return Transform.scale(
      scale: scale,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
