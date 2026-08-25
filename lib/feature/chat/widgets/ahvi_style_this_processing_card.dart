import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/app_localizations.dart';
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
    final title = AppLocalizations.t(
      context,
      'item_detail_style_processing_title',
    ).replaceAll('{item}', name.isEmpty ? 'piece' : name);
    final subtitle = AppLocalizations.t(
      context,
      'item_detail_style_processing_subtitle',
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 10, color: t.accent.primary),
              const SizedBox(width: 4),
              Text(
                'AHVI',
                // Locally bundled (assets/fonts/Anton-Regular.ttf, declared
                // in pubspec.yaml) rather than GoogleFonts.anton() - zero
                // network/cache dependency so this deterministically renders
                // correctly on first launch, no fallback-font flash.
                style: TextStyle(
                  fontFamily: 'Anton',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.2,
                  height: 1.0,
                  color: t.accent.primary,
                  shadows: const [],
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.auto_awesome, size: 10, color: t.accent.primary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: t.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 3,
              width: double.infinity,
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
