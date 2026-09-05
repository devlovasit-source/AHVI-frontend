import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';

/// Premium, AHVI-branded processing card shown while Style This builds
/// directions for a wardrobe item. Presentation only -- the request, anchor,
/// and result handling all live in the caller; this widget just renders the
/// "waiting" state over the existing dimmed item-detail barrier. The caller
/// centers and width-constrains this widget (see ahvi_item_detail_modal.dart).
class AhviStyleThisProcessingCard extends StatelessWidget {
  final String itemName;

  const AhviStyleThisProcessingCard({super.key, required this.itemName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final name = itemName.trim();
    final title = name.isEmpty ? 'Styling your piece' : 'Styling your $name';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
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
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: t.accent.primary),
              const SizedBox(width: 7),
              Text(
                'AHVI',
                style: TextStyle(
                  fontFamily: 'Anton',
                  fontSize: 24,
                  letterSpacing: 1.8,
                  color: t.accent.primary,
                ),
              ),
              const SizedBox(width: 7),
              Icon(Icons.auto_awesome, size: 16, color: t.accent.primary),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Finding the best pieces from your wardrobe…',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              color: t.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
