import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';

/// Compact, AHVI-branded processing card shown while Style This builds
/// directions for a wardrobe item. Presentation only -- the request, anchor,
/// and result handling all live in the caller; this widget just renders the
/// "waiting" state over the existing dimmed item-detail barrier.
class AhviStyleThisProcessingCard extends StatelessWidget {
  final String itemName;

  const AhviStyleThisProcessingCard({super.key, required this.itemName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final name = itemName.trim();
    final title = name.isEmpty ? 'Styling your piece' : 'Styling your $name';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✦',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'AHVI',
                style: TextStyle(
                  fontFamily: 'Anton',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: t.accent.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Finding the best pieces from your wardrobe…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: t.mutedText,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                color: t.accent.primary,
                backgroundColor: t.accent.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
