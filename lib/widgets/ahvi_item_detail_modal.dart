// ============================================================
// ahvi_item_detail_modal.dart
// Premium "AI Stylist" item detail modal (V2)
//
// Drop-in replacement for the old inventory-style item modal.
// Implements P0 #2-5 from the Monday demo punch list:
//   - Bigger garment image, cleaner header
//   - "Works Well With" section (computed via PairingEngine)
//   - "Best For" chips (computed via PairingEngine)
//   - Primary CTA "✨ Style This" -> routes to AHVI chat with item context
//   - Secondary CTA "Edit"
//   - Like / Share / Remove moved into an overflow menu
//
// USAGE:
//   showItemDetailModal(
//     context,
//     item: wardrobeItem,
//     allItems: _items, // full wardrobe list, for "Works Well With"
//     onWore: () { ... },
//     onEdit: () { ... },
//     onLike: () { ... },
//     onShare: () { ... },
//     onRemove: () { ... },
//   );
//
// "Style This" requires AhviStylistChat (already imported in wardrobe.dart
// via package:myapp/widgets/ahvi_stylist_chat.dart) to expose a constructor
// param for an initial/seed prompt. If your chat widget's constructor has a
// different name for this field, update STYLE_THIS_ENTRY_POINT below.
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/models/detected_item.dart'; // WardrobeItem lives here
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'pairing_engine.dart';

// ============================================================
// SEMANTIC COLORS
// AppThemeTokens has no success/danger group, so these are
// centralized here for consistency across the modal + sheets.
// ============================================================
const Color _kSuccessColor = Color(0xFF34C759);
const Color _kDangerColor = Color(0xFFA32D2D);

// ============================================================
// PUBLIC ENTRY POINT
// ============================================================
void showItemDetailModal(
  BuildContext context, {
  required WardrobeItem item,
  required List<WardrobeItem> allItems,
  VoidCallback? onWore,
  VoidCallback? onEdit,
  VoidCallback? onLike,
  VoidCallback? onShare,
  VoidCallback? onRemove,
  VoidCallback? onBuildOutfit,
  VoidCallback? onViewWearHistory,
  VoidCallback? onSetWearReminder,
  VoidCallback? onSetCareReminder,
}) {
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black54,
    builder: (_) => _ItemDetailModal(
      item: item,
      allItems: allItems,
      onWore: onWore,
      onEdit: onEdit,
      onLike: onLike,
      onShare: onShare,
      onRemove: onRemove,
      onBuildOutfit: onBuildOutfit,
      onViewWearHistory: onViewWearHistory,
      onSetWearReminder: onSetWearReminder,
      onSetCareReminder: onSetCareReminder,
    ),
  );
}

// ============================================================
// MODAL WIDGET
// ============================================================
class _ItemDetailModal extends StatelessWidget {
  final WardrobeItem item;
  final List<WardrobeItem> allItems;
  final VoidCallback? onWore;
  final VoidCallback? onEdit;
  final VoidCallback? onLike;
  final VoidCallback? onShare;
  final VoidCallback? onRemove;
  final VoidCallback? onBuildOutfit;
  final VoidCallback? onViewWearHistory;
  final VoidCallback? onSetWearReminder;
  final VoidCallback? onSetCareReminder;

  const _ItemDetailModal({
    required this.item,
    required this.allItems,
    this.onWore,
    this.onEdit,
    this.onLike,
    this.onShare,
    this.onRemove,
    this.onBuildOutfit,
    this.onViewWearHistory,
    this.onSetWearReminder,
    this.onSetCareReminder,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;

    final pairings = PairingEngine.worksWellWith(item, allItems);
    final bestFor = PairingEngine.bestFor(item);
    final avoid = PairingEngine.avoid(item);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // -------------------------------------------
                    // HEADER: name + close
                    // (overflow menu moved into the sticky action bar)
                    // -------------------------------------------
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: GoogleFonts.inter(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A1A1A),
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE5E5EA)),
                            ),
                            child: const Icon(Icons.close, size: 18, color: Color(0xFF6B6B6B)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // category + worn badge
                    Row(
                      children: [
                        _Pill(
                          label: item.cat,
                          bg: t.accent.primary.withOpacity(0.12),
                          fg: t.accent.primary,
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          label: item.worn == 0 ? 'Never worn' : 'Worn ${item.worn}x',
                          bg: const Color(0xFFF2F2F7),
                          fg: const Color(0xFF8A8A8E),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // -------------------------------------------
                    // IMAGE + WORKS WELL WITH (responsive row)
                    // -------------------------------------------
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 360;
                        final image = AspectRatio(
                          aspectRatio: narrow ? 1.0 : 0.85,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFEFF7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: item.displayUrl != null && item.displayUrl!.isNotEmpty
                                ? Image.network(
                                    item.displayUrl!,
                                    fit: BoxFit.contain, // P0 #1: never cover
                                  )
                                : const Icon(Icons.checkroom, size: 64, color: Color(0xFFBFBFD6)),
                          ),
                        );

                        final works = _WorksWellWithCard(
                          pairings: pairings,
                          allItems: allItems,
                          onSelectPairing: (p) => _onSelectPairing(context, p),
                          onShowAllPairings: pairings.length > 3
                              ? () => _showAllPairings(context, pairings)
                              : null,
                        );

                        if (narrow) {
                          return Column(
                            children: [
                              image,
                              const SizedBox(height: 12),
                              works,
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: image),
                              const SizedBox(width: 12),
                              Expanded(flex: 4, child: works),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // -------------------------------------------
                    // WARDROBE MATCH (NEW)
                    // -------------------------------------------
                    _WardrobeMatchCard(matchCount: pairings.length, t: t),
                    const SizedBox(height: 16),

                    // -------------------------------------------
                    // OCCASION CHIPS (existing)
                    // -------------------------------------------
                    if (item.occasions.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.occasions
                            .map((o) => _Pill(
                                  label: o,
                                  bg: const Color(0xFFF7F7FB),
                                  fg: const Color(0xFF3C3C43),
                                  border: const Color(0xFFE5E5EA),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // -------------------------------------------
                    // STYLE INSIGHTS: Best For / Avoid
                    // -------------------------------------------
                    _StyleInsightsCard(bestFor: bestFor, avoid: avoid, t: t),
                  ],
                ),
              ),

              // -------------------------------------------
              // STICKY ACTION BAR
              // Row 1: Style This (primary) + Build Outfit
              // Row 2: Wore Today + Edit + overflow (Like/Share/Remove)
              // -------------------------------------------
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(top: BorderSide(color: Color(0xFFF0F0F4))),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Row 1: Style This + Build Outfit
                      Row(
                        children: [
                          Expanded(
                            child: _PrimaryStyleThisButton(
                              item: item,
                              t: t,
                              onTap: () => _onStyleThis(context, item),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.groups_2_outlined,
                              label: 'Build Outfit',
                              onTap: () => _onBuildOutfit(context, item),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Row 2: Wore Today + Edit + overflow
                      Row(
                        children: [
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.check,
                              label: 'Wore Today',
                              onTap: () => _onWoreToday(context, item),
                              accentColor: _kSuccessColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              onTap: onEdit,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _MoreOptionsButton(
                            onTap: () => _showMoreOptions(context, item),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SELECT PAIRING -> close this modal and open the detail modal
  // for the tapped "Works well with" item (data-driven drill-down)
  // ============================================================
  void _onSelectPairing(BuildContext context, WardrobeItem pairedItem) {
    Navigator.of(context).pop(); // close current modal

    showItemDetailModal(
      context,
      item: pairedItem,
      allItems: allItems,
      onWore: onWore,
      onEdit: onEdit,
      onLike: onLike,
      onShare: onShare,
      onRemove: onRemove,
      onBuildOutfit: onBuildOutfit,
      onViewWearHistory: onViewWearHistory,
      onSetWearReminder: onSetWearReminder,
      onSetCareReminder: onSetCareReminder,
    );
  }

  // ============================================================
  // SHOW ALL PAIRINGS -> bottom sheet listing every computed match,
  // each tappable to drill into that item's detail modal
  // ============================================================
  void _showAllPairings(BuildContext context, List<WardrobeItem> pairings) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllPairingsSheet(
        sourceItemName: item.name,
        pairings: pairings,
        onSelect: (p) => _onSelectPairing(context, p),
      ),
    );
  }

  // ============================================================
  // STYLE THIS -> route into AHVI chat with item context
  // ============================================================
  void _onStyleThis(BuildContext context, WardrobeItem item) {
    Navigator.of(context).pop(); // close modal first

    // ------------------------------------------------------------
    // STYLE_THIS_ENTRY_POINT
    // Adjust this call to match AhviStylistChat's actual API.
    // Two common shapes are supported below — keep whichever matches.
    // ------------------------------------------------------------

    // Option A: chat screen takes an initial prompt + item id
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AhviStylistChat(
          initialPrompt: 'Style this item: ${item.name}',
          contextItemId: item.id,
        ),
      ),
    );

    // Option B (alternative): if AhviStylistChat is shown as a bottom sheet
    // or already lives on a tab and exposes a static method instead, replace
    // the above with something like:
    //
    // AhviStylistChat.openWithPrompt(
    //   context,
    //   prompt: 'Style this item: ${item.name}',
    //   itemId: item.id,
    // );
  }

  // ============================================================
  // BUILD OUTFIT -> route into AHVI chat with item context
  // (mirrors _onStyleThis with a different seed prompt; falls back
  // to onBuildOutfit callback if provided instead)
  // ============================================================
  void _onBuildOutfit(BuildContext context, WardrobeItem item) {
    if (onBuildOutfit != null) {
      Navigator.of(context).pop(); // close modal first
      onBuildOutfit!.call();
      return;
    }

    Navigator.of(context).pop(); // close modal first

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AhviStylistChat(
          initialPrompt: 'Build an outfit around: ${item.name}',
          contextItemId: item.id,
        ),
      ),
    );
  }

  // ============================================================
  // WORE TODAY -> mark item as worn + show confirmation, then
  // close the modal
  // ============================================================
  void _onWoreToday(BuildContext context, WardrobeItem item) {
    onWore?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Marked "${item.name}" as worn today'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    Navigator.of(context).pop();
  }

  // ============================================================
  // MORE OPTIONS -> open bottom sheet (Favorites / Wear History /
  // Share / Reminders / Delete)
  // ============================================================
  void _showMoreOptions(BuildContext context, WardrobeItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ItemMoreOptionsSheet(
        item: item,
        onAddToFavorites: () => onLike?.call(),
        onViewWearHistory: () => onViewWearHistory?.call(),
        onShare: () => onShare?.call(),
        onSetWearReminder: () => onSetWearReminder?.call(),
        onSetCareReminder: () => onSetCareReminder?.call(),
        onDelete: () => _confirmDelete(context, item),
      ),
    );
  }

  // ============================================================
  // DELETE PERMANENTLY -> confirm, then close sheet + parent modal
  // ============================================================
  void _confirmDelete(BuildContext context, WardrobeItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text(
          '"${item.name}" will be permanently removed from your wardrobe. This action cannot be undone.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // close confirm dialog
              Navigator.of(context).pop(); // close more-options sheet
              Navigator.of(context).pop(); // close item detail modal
              onRemove?.call();
            },
            style: TextButton.styleFrom(foregroundColor: _kDangerColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PRIMARY CTA BUTTON
// ============================================================
class _PrimaryStyleThisButton extends StatelessWidget {
  final WardrobeItem item;
  final AppThemeTokens t;
  final VoidCallback onTap;

  const _PrimaryStyleThisButton({
    required this.item,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [t.accent.primary, t.accent.secondary],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Style This',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SECONDARY ACTION BUTTON (Build Outfit / Wore Today / Edit)
// ============================================================
class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accentColor;

  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? const Color(0xFF1A1A1A);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: Color(0xFFE5E5EA)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// "WORKS WELL WITH" CARD
// ============================================================
class _WorksWellWithCard extends StatelessWidget {
  final List<WardrobeItem> pairings;
  final List<WardrobeItem> allItems;
  final void Function(WardrobeItem)? onSelectPairing;
  final VoidCallback? onShowAllPairings;

  const _WorksWellWithCard({
    required this.pairings,
    required this.allItems,
    this.onSelectPairing,
    this.onShowAllPairings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WORKS WELL WITH',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: const Color(0xFF8A8A8E),
            ),
          ),
          const SizedBox(height: 10),
          if (pairings.isEmpty)
            Text(
              'Add more items to your wardrobe to see pairing ideas.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF8A8A8E)),
            )
          else
            ...pairings.take(3).map((p) => InkWell(
                  onTap: onSelectPairing != null ? () => onSelectPairing!(p) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 32,
                            height: 32,
                            color: const Color(0xFFEFEFF7),
                            child: (p.displayUrl != null && p.displayUrl!.isNotEmpty)
                                ? Image.network(p.displayUrl!, fit: BoxFit.contain)
                                : const Icon(Icons.checkroom, size: 16, color: Color(0xFFBFBFD6)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          if (pairings.length > 3)
            InkWell(
              onTap: onShowAllPairings,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+ ${pairings.length - 3} more item${pairings.length - 3 == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8A8A8E),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// STYLE INSIGHTS CARD (Best For / Avoid)
// ============================================================
class _StyleInsightsCard extends StatelessWidget {
  final List<String> bestFor;
  final List<String> avoid;
  final AppThemeTokens t;

  const _StyleInsightsCard({
    required this.bestFor,
    required this.avoid,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: t.accent.primary),
              const SizedBox(width: 6),
              Text(
                'STYLE INSIGHTS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: const Color(0xFF8A8A8E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _InsightColumn(title: 'Best for', items: bestFor, good: true)),
              const SizedBox(width: 16),
              Expanded(child: _InsightColumn(title: 'Avoid', items: avoid, good: false)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightColumn extends StatelessWidget {
  final String title;
  final List<String> items;
  final bool good;

  const _InsightColumn({
    required this.title,
    required this.items,
    required this.good,
  });

  @override
  Widget build(BuildContext context) {
    final color = good ? _kSuccessColor : _kDangerColor;
    final icon = good ? Icons.check_circle : Icons.cancel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text('—', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF8A8A8E)))
        else
          ...items.map((label) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF3C3C43)),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

// ============================================================
// WARDROBE MATCH CARD (NEW)
// ============================================================
class _WardrobeMatchCard extends StatelessWidget {
  final int matchCount;
  final AppThemeTokens t;

  // Thresholds centralized here so product/design can tune copy
  // without hunting through layout code.
  static const int greatThreshold = 6;
  static const int goodThreshold = 3;
  static const int limitedThreshold = 1;

  const _WardrobeMatchCard({required this.matchCount, required this.t});

  @override
  Widget build(BuildContext context) {
    String label;
    if (matchCount >= greatThreshold) {
      label = 'Great match potential';
    } else if (matchCount >= goodThreshold) {
      label = 'Good match potential';
    } else if (matchCount >= limitedThreshold) {
      label = 'Limited match potential';
    } else {
      label = 'Add more items to see matches';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.accent.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: t.accent.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checkroom, size: 14, color: t.accent.primary),
              const SizedBox(width: 6),
              Text(
                'WARDROBE MATCH',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: const Color(0xFF8A8A8E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$matchCount item${matchCount == 1 ? '' : 's'}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: t.accent.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.accent.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SMALL UI HELPERS
// ============================================================
class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;

  const _Pill({required this.label, required this.bg, required this.fg, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _MoreOptionsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MoreOptionsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.more_horiz, color: Color(0xFF6B6B6B)),
      ),
    );
  }
}

// ============================================================
// MORE OPTIONS BOTTOM SHEET
// 6 essential actions: Favorites, Wear History, Share,
// Wear Reminder, Care Reminder, Delete (danger zone)
// ============================================================
class ItemMoreOptionsSheet extends StatelessWidget {
  final WardrobeItem item;
  final VoidCallback? onAddToFavorites;
  final VoidCallback? onViewWearHistory;
  final VoidCallback? onShare;
  final VoidCallback? onSetWearReminder;
  final VoidCallback? onSetCareReminder;
  final VoidCallback? onDelete;

  const ItemMoreOptionsSheet({
    super.key,
    required this.item,
    this.onAddToFavorites,
    this.onViewWearHistory,
    this.onShare,
    this.onSetWearReminder,
    this.onSetCareReminder,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF8A8A8E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'More options',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5, color: Color(0xFFF0F0F4)),

            _OptionRow(
              icon: Icons.favorite_border,
              label: 'Add to favorites',
              onTap: () {
                Navigator.of(context).pop();
                onAddToFavorites?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Added to favorites'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                );
              },
            ),
            _OptionRow(
              icon: Icons.history,
              label: 'Wear history',
              onTap: () {
                Navigator.of(context).pop();
                onViewWearHistory?.call();
              },
            ),
            _OptionRow(
              icon: Icons.ios_share,
              label: 'Share',
              onTap: () {
                Navigator.of(context).pop();
                onShare?.call();
              },
            ),
            _OptionRow(
              icon: Icons.notifications_outlined,
              label: 'Remind me to wear it',
              onTap: () {
                Navigator.of(context).pop();
                onSetWearReminder?.call();
              },
            ),
            _OptionRow(
              icon: Icons.local_laundry_service_outlined,
              label: 'Care reminder',
              onTap: () {
                Navigator.of(context).pop();
                onSetCareReminder?.call();
              },
            ),
            _OptionRow(
              icon: Icons.delete_outline,
              label: 'Delete permanently',
              color: _kDangerColor,
              showDivider: false,
              onTap: onDelete, // sheet closed by _confirmDelete after confirm
            ),

            // Cancel footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFE5E5EA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool showDivider;

  const _OptionRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? const Color(0xFF1A1A1A);
    final iconColor = color ?? const Color(0xFF8A8A8E);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 0.5, color: Color(0xFFF0F0F4)),
      ],
    );
  }
}

// ============================================================
// ALL PAIRINGS BOTTOM SHEET
// Full list of items computed by PairingEngine.worksWellWith,
// each row tappable to drill into that item's detail modal
// ============================================================
class _AllPairingsSheet extends StatelessWidget {
  final String sourceItemName;
  final List<WardrobeItem> pairings;
  final void Function(WardrobeItem) onSelect;

  const _AllPairingsSheet({
    required this.sourceItemName,
    required this.pairings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sourceItemName,
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF8A8A8E)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pairings.length} pairing match${pairings.length == 1 ? '' : 'es'}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5, color: Color(0xFFF0F0F4)),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: pairings.length,
                separatorBuilder: (_, __) => const Divider(height: 0.5, color: Color(0xFFF0F0F4)),
                itemBuilder: (context, index) {
                  final p = pairings[index];
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop(); // close sheet
                      onSelect(p);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: const Color(0xFFEFEFF7),
                              child: (p.displayUrl != null && p.displayUrl!.isNotEmpty)
                                  ? Image.network(p.displayUrl!, fit: BoxFit.contain)
                                  : const Icon(Icons.checkroom, size: 18, color: Color(0xFFBFBFD6)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                Text(
                                  p.cat,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF8A8A8E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8A8A8E)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFE5E5EA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
