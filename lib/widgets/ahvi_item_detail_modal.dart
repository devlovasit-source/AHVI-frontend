// ============================================================
// ahvi_item_detail_modal.dart
// Premium "AI Stylist" item detail modal (V2)
//
//   - Bigger garment image, cleaner header
//   - "Works Well With" (computed via PairingEngine)
//   - "Best For" chips (computed via PairingEngine)
//   - Primary CTA "Style This" -> opens AHVI stylist chat sheet seeded
//     with this item (via the existing showAhviStylistChatSheet API)
//   - Like / Share / Remove in an overflow menu
//
// NOTE: WardrobeItem is the existing repo model from wardrobe.dart — not a
// separate model file. Chat is opened through showAhviStylistChatSheet, the
// only public entry point the chat widget exposes.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/wardrobe.dart'; // WardrobeItem lives here
import 'package:myapp/services/backend_service.dart'; // styleWardrobeItem
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_layout_engine.dart';
import 'pairing_engine.dart';

// ============================================================
// SEMANTIC COLORS
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
                    // HEADER: name + close
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
                              border: Border.all(
                                color: const Color(0xFFE5E5EA),
                              ),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Color(0xFF6B6B6B),
                            ),
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
                          bg: t.accent.primary.withValues(alpha: 0.12),
                          fg: t.accent.primary,
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          label: item.worn == 0
                              ? 'Never worn'
                              : 'Worn ${item.worn}x',
                          bg: const Color(0xFFF2F2F7),
                          fg: const Color(0xFF8A8A8E),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // IMAGE + WORKS WELL WITH (responsive row)
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
                            child:
                                item.displayUrl != null &&
                                    item.displayUrl!.isNotEmpty
                                ? Image.network(
                                    item.displayUrl!,
                                    fit: BoxFit.contain,
                                  )
                                : const Icon(
                                    Icons.checkroom,
                                    size: 64,
                                    color: Color(0xFFBFBFD6),
                                  ),
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

                    // WARDROBE MATCH
                    _WardrobeMatchCard(matchCount: pairings.length, t: t),
                    const SizedBox(height: 16),

                    // OCCASION CHIPS
                    if (item.occasions.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.occasions
                            .map(
                              (o) => _Pill(
                                label: o,
                                bg: const Color(0xFFF7F7FB),
                                fg: const Color(0xFF3C3C43),
                                border: const Color(0xFFE5E5EA),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // STYLE INSIGHTS: Best For / Avoid
                    _StyleInsightsCard(bestFor: bestFor, avoid: avoid, t: t),
                  ],
                ),
              ),

              // STICKY ACTION BAR
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFF0F0F4))),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
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

  // SELECT PAIRING -> drill into that item's detail modal
  void _onSelectPairing(BuildContext context, WardrobeItem pairedItem) {
    Navigator.of(context).pop();
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
  // STYLE THIS -> 3 styling directions from the backend stylist pipeline.
  // BUILD OUTFIT -> 1 practical outfit anchored on this item.
  // Both show a loading spinner, then a result sheet, and never dead-end.
  // ============================================================
  void _onStyleThis(BuildContext context, WardrobeItem item) {
    _runStyleCta(context, item, mode: 'style_this');
  }

  void _onBuildOutfit(BuildContext context, WardrobeItem item) {
    if (onBuildOutfit != null) {
      Navigator.of(context).pop();
      onBuildOutfit!.call();
      return;
    }
    _runStyleCta(context, item, mode: 'build_outfit');
  }

  Future<void> _runStyleCta(
    BuildContext context,
    WardrobeItem item, {
    required String mode,
  }) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final BuildContext appContext = rootNav.context;
    rootNav.pop(); // close the item-detail dialog

    // Loading state.
    showDialog<void>(
      context: appContext,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    debugPrint('AHVI_MODAL_GUARD start flow=styleCta');
    Map<String, dynamic>? result;
    var timedOut = false;
    try {
      // Timeout so a slow backend can never strand the user behind the
      // barrierDismissible:false spinner (ANR / frozen-screen class).
      result = await BackendService()
          .styleWardrobeItem(
            itemId: item.id,
            mode: mode,
            anchorItem: {
              'item_id': item.id,
              'name': item.name,
              'category': item.cat,
              if (item.displayUrl != null) 'image_url': item.displayUrl,
              // Display/context hint only: this modal renders the user's own
              // wardrobe records. The backend re-verifies the item against
              // the authenticated wardrobe and remains the trust boundary.
              'source': 'wardrobe',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      timedOut = true;
      debugPrint('AHVI_MODAL_GUARD timeout flow=styleCta');
      result = null;
    } catch (_) {
      result = null;
    } finally {
      if (rootNav.canPop()) rootNav.pop(); // always dismiss the spinner
      debugPrint('AHVI_MODAL_GUARD close flow=styleCta');
    }

    if (!appContext.mounted) return;
    if (timedOut) {
      ScaffoldMessenger.maybeOf(appContext)?.showSnackBar(
        const SnackBar(content: Text('This took too long. Please try again.')),
      );
      return;
    }
    _showStyleResultSheet(appContext, mode: mode, item: item, result: result);
  }

  static const String _friendlyFail =
      'AHVI could not build a complete outfit yet. '
      'Try adding shoes or accessories.';

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  void _showStyleResultSheet(
    BuildContext context, {
    required String mode,
    required WardrobeItem item,
    required Map<String, dynamic>? result,
  }) {
    final bool ok = result != null && result['success'] == true;
    final String? message = result?['message']?.toString();
    final List<Map<String, dynamic>> directions = mode == 'style_this'
        ? _asMapList(result?['style_directions'])
        : <Map<String, dynamic>>[];
    final Map<String, dynamic>? outfit =
        (mode == 'build_outfit' && result?['outfit'] is Map)
        ? Map<String, dynamic>.from(result!['outfit'] as Map)
        : null;
    final bool isAnchorBoard =
        outfit != null && outfit['payload_type'] == 'ANCHOR_OUTFIT_BOARD';
    final bool hasBuildBoardContract =
        outfit != null &&
        (outfit['board_id'] ?? '').toString().trim().isNotEmpty &&
        outfit['revision'] is num;
    final bool hasStyleBoardContract = directions.any(
      (direction) =>
          (direction['board_id'] ?? '').toString().trim().isNotEmpty &&
          direction['revision'] is num,
    );
    final bool usesActiveBoard = hasBuildBoardContract || hasStyleBoardContract;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: isAnchorBoard || usesActiveBoard ? 0.9 : 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: isAnchorBoard || usesActiveBoard
                ? Colors.white
                : const Color(0xFF14110F),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isAnchorBoard || usesActiveBoard
                        ? const Color(0x1A000000)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                mode == 'style_this' ? 'Style Directions' : 'Build Outfit',
                style: TextStyle(
                  color: isAnchorBoard || usesActiveBoard
                      ? const Color(0xFF1A1A1A)
                      : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.name,
                style: TextStyle(
                  color: isAnchorBoard || usesActiveBoard
                      ? const Color(0xFF8A8A8E)
                      : Colors.white60,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              if (!ok || (message != null && message.isNotEmpty))
                _StyleNotice(
                  text: (message != null && message.isNotEmpty)
                      ? message
                      : _friendlyFail,
                ),
              if (mode == 'style_this' && hasStyleBoardContract)
                ...directions.map(
                  (direction) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AhviOutfitBoardCard(
                      direction: {
                        ...direction,
                        'direction_name': direction['title'],
                        'board_items': direction['items'],
                      },
                      width: MediaQuery.sizeOf(ctx).width - 40,
                    ),
                  ),
                ),
              if (mode == 'style_this' && !hasStyleBoardContract)
                ...directions.map((d) => _StyleDirectionCard(direction: d)),
              if (mode == 'build_outfit' && hasBuildBoardContract)
                AhviOutfitBoardCard(
                  direction: {
                    ...outfit,
                    'direction_name': outfit['title'],
                    'board_items': outfit['items'],
                  },
                  width: MediaQuery.sizeOf(ctx).width - 40,
                ),
              if (mode == 'build_outfit' &&
                  !hasBuildBoardContract &&
                  isAnchorBoard)
                _AnchorOutfitBoardCard(outfit: outfit),
              if (mode == 'build_outfit' &&
                  !hasBuildBoardContract &&
                  !isAnchorBoard &&
                  outfit != null)
                _StyleDirectionCard(direction: outfit, reasonKey: 'reason'),
            ],
          ),
        ),
      ),
    );
  }

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
        // Close the sheet + this modal, then hand off to the host's own
        // delete-confirm (onRemove). Avoids a second confirm dialog here.
        onDelete: () {
          Navigator.of(context).pop(); // close more-options sheet
          Navigator.of(context).pop(); // close item detail modal
          onRemove?.call();
        },
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
// SECONDARY ACTION BUTTON
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF8A8A8E),
              ),
            )
          else
            ...pairings
                .take(3)
                .map(
                  (p) => InkWell(
                    onTap: onSelectPairing != null
                        ? () => onSelectPairing!(p)
                        : null,
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
                              child:
                                  (p.displayUrl != null &&
                                      p.displayUrl!.isNotEmpty)
                                  ? Image.network(
                                      p.displayUrl!,
                                      fit: BoxFit.contain,
                                    )
                                  : const Icon(
                                      Icons.checkroom,
                                      size: 16,
                                      color: Color(0xFFBFBFD6),
                                    ),
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
                  ),
                ),
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
              Expanded(
                child: _InsightColumn(
                  title: 'Best for',
                  items: bestFor,
                  good: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InsightColumn(
                  title: 'Avoid',
                  items: avoid,
                  good: false,
                ),
              ),
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
          Text(
            '—',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF8A8A8E),
            ),
          )
        else
          ...items.map(
            (label) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF3C3C43),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// WARDROBE MATCH CARD
// ============================================================
class _WardrobeMatchCard extends StatelessWidget {
  final int matchCount;
  final AppThemeTokens t;

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
        color: t.accent.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: t.accent.primary, width: 3)),
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

  const _Pill({
    required this.label,
    required this.bg,
    required this.fg,
    this.border,
  });

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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
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
              onTap: onDelete,
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
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
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF8A8A8E),
                    ),
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
                separatorBuilder: (_, __) =>
                    const Divider(height: 0.5, color: Color(0xFFF0F0F4)),
                itemBuilder: (context, index) {
                  final p = pairings[index];
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(p);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: const Color(0xFFEFEFF7),
                              child:
                                  (p.displayUrl != null &&
                                      p.displayUrl!.isNotEmpty)
                                  ? Image.network(
                                      p.displayUrl!,
                                      fit: BoxFit.contain,
                                    )
                                  : const Icon(
                                      Icons.checkroom,
                                      size: 18,
                                      color: Color(0xFFBFBFD6),
                                    ),
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
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFF8A8A8E),
                          ),
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

// ============================================================
// STYLE RESULT SHEET WIDGETS (Style This / Build Outfit)
// ============================================================
class _StyleNotice extends StatelessWidget {
  final String text;
  const _StyleNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33A32D2D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StyleDirectionCard extends StatelessWidget {
  final Map<String, dynamic> direction;
  final String reasonKey;
  const _StyleDirectionCard({
    required this.direction,
    this.reasonKey = 'styling_note',
  });

  static List<String> _names(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final e in value) {
      if (e is Map) {
        final n = (e['name'] ?? e['label'] ?? '').toString().trim();
        if (n.isNotEmpty) out.add(n);
      }
    }
    return out;
  }

  static List<String> _missing(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final e in value) {
      if (e is Map) {
        final n = (e['label'] ?? e['name'] ?? '').toString().trim();
        if (n.isNotEmpty) out.add(n);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final title = (direction['title'] ?? 'Your Look').toString();
    final items = _names(direction['items']);
    final missing = _missing(direction['missing_items']);
    final note =
        (direction[reasonKey] ??
                direction['styling_note'] ??
                direction['reason'] ??
                '')
            .toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'WEAR',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((n) => _StyleChip(label: n, accent: false))
                  .toList(),
            ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'MISSING - SHOP THESE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: missing
                  .map((n) => _StyleChip(label: n, accent: true))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final bool accent;
  const _StyleChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0x332E7D5B)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent ? const Color(0x662E7D5B) : Colors.white12,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? const Color(0xFF8FE3BE) : Colors.white,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ============================================================
// ANCHOR OUTFIT BOARD — visual 9:16 board with source badges
// ============================================================

BoardItemRole _anchorBoardRoleFromRaw(Map<String, dynamic> raw) {
  final category = raw['category']?.toString() ?? '';
  final name = raw['name']?.toString() ?? '';
  var role = BoardLayoutEngine.resolveRole(category, name: name);
  if (role == BoardItemRole.unknown) {
    // fall back to explicit backend role field
    switch ((raw['role']?.toString() ?? '').toLowerCase()) {
      case 'top':
        role = BoardItemRole.top;
        break;
      case 'bottom':
        role = BoardItemRole.bottom;
        break;
      case 'footwear':
        role = BoardItemRole.footwear;
        break;
      case 'outerwear':
        role = BoardItemRole.outerwear;
        break;
      case 'dress':
        role = BoardItemRole.dress;
        break;
      case 'accessory':
        role = BoardItemRole.accessory;
        break;
    }
  }
  return role;
}

class _AnchorOutfitBoardCard extends StatelessWidget {
  final Map<String, dynamic> outfit;
  const _AnchorOutfitBoardCard({required this.outfit});

  List<Map<String, dynamic>> _rawItems() {
    final v = outfit['board_items'] ?? outfit['items'];
    if (v is! List) return <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _missingItems() {
    final v = outfit['missing_items'];
    if (v is! List) return <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rawItems = _rawItems();
    final missing = _missingItems();
    final stylingNote =
        outfit['styling_notes']?.toString() ??
        outfit['reason']?.toString() ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 9:16 flat-lay canvas
        AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.white,
              child: _AnchorBoardCanvas(items: rawItems),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // item list with source badges
        ...rawItems.map((raw) => _AnchorItemRow(raw: raw)),
        if (stylingNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            stylingNote,
            style: const TextStyle(
              color: Color(0xFF3C3C43),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'MISSING — SHOP THESE',
            style: TextStyle(
              color: Color(0xFF8A8A8E),
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: missing.map((m) {
              final label = (m['label'] ?? m['name'] ?? '').toString().trim();
              return _StyleChip(label: label, accent: true);
            }).toList(),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AnchorItemRow extends StatelessWidget {
  final Map<String, dynamic> raw;
  const _AnchorItemRow({required this.raw});

  @override
  Widget build(BuildContext context) {
    final name = raw['name']?.toString() ?? '';
    final isAnchor = raw['is_anchor'] == true;
    final source = raw['source']?.toString() ?? 'wardrobe';
    final imageUrl = raw['image_url']?.toString() ?? '';

    final sourceLabel = isAnchor
        ? 'Your piece'
        : (source == 'wardrobe' ? 'Wardrobe' : 'Suggested');
    final sourceColor = isAnchor
        ? const Color(0xFF7B61FF)
        : (source == 'wardrobe'
              ? const Color(0xFF34C759)
              : const Color(0xFFFF9500));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: const Color(0xFFF7F4EE),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.contain)
                  : const Icon(
                      Icons.checkroom,
                      size: 20,
                      color: Color(0xFFBFBFD6),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sourceColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              sourceLabel,
              style: TextStyle(
                color: sourceColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FLAT-LAY BOARD CANVAS — absolute-positioned 9:16 layout
// ============================================================

class _TileCfg {
  final double left;
  final double top;
  final double width;
  final double height;
  final int zIndex;
  const _TileCfg(this.left, this.top, this.width, this.height, this.zIndex);
}

class _AnchorBoardCanvas extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _AnchorBoardCanvas({required this.items});

  static const _l3Classic = <String, _TileCfg>{
    'top': _TileCfg(0.08, 0.04, 0.62, 0.40, 1),
    'bottom': _TileCfg(0.36, 0.46, 0.54, 0.42, 2),
    'footwear': _TileCfg(0.08, 0.76, 0.44, 0.20, 3),
  };
  static const _l3Dress = <String, _TileCfg>{
    'dress': _TileCfg(0.10, 0.04, 0.58, 0.64, 1),
    'footwear': _TileCfg(0.08, 0.72, 0.40, 0.22, 2),
    'accessory': _TileCfg(0.52, 0.68, 0.40, 0.26, 2),
  };
  static const _l4Classic = <String, _TileCfg>{
    'top': _TileCfg(0.08, 0.04, 0.55, 0.34, 1),
    'accessory': _TileCfg(0.55, 0.06, 0.38, 0.26, 1),
    'bottom': _TileCfg(0.34, 0.42, 0.52, 0.38, 2),
    'footwear': _TileCfg(0.08, 0.72, 0.42, 0.22, 3),
  };
  static const _l5 = <String, _TileCfg>{
    'outerwear': _TileCfg(0.06, 0.04, 0.44, 0.30, 1),
    'top': _TileCfg(0.48, 0.04, 0.46, 0.28, 1),
    'bottom': _TileCfg(0.24, 0.36, 0.52, 0.36, 2),
    'footwear': _TileCfg(0.06, 0.68, 0.40, 0.22, 3),
    'accessory': _TileCfg(0.50, 0.64, 0.42, 0.28, 2),
  };

  static String _roleKey(BoardItemRole r) {
    switch (r) {
      case BoardItemRole.top:
        return 'top';
      case BoardItemRole.bottom:
        return 'bottom';
      case BoardItemRole.footwear:
        return 'footwear';
      case BoardItemRole.outerwear:
        return 'outerwear';
      case BoardItemRole.dress:
        return 'dress';
      case BoardItemRole.accessory:
        return 'accessory';
      case BoardItemRole.unknown:
        return 'unknown';
    }
  }

  Map<String, _TileCfg> _pickTemplate() {
    final roles = items.map((r) => _anchorBoardRoleFromRaw(r)).toSet();
    if (roles.contains(BoardItemRole.dress)) return _l3Dress;
    if (items.length >= 5) return _l5;
    if (items.length == 4) return _l4Classic;
    return _l3Classic;
  }

  @override
  Widget build(BuildContext context) {
    final template = _pickTemplate();
    final slots = <String, Map<String, dynamic>>{};
    final usedSlots = <String>{};
    for (final item in items) {
      final key = _roleKey(_anchorBoardRoleFromRaw(item));
      if (template.containsKey(key) && !usedSlots.contains(key)) {
        slots[key] = item;
        usedSlots.add(key);
      }
    }
    final ordered = slots.entries.toList()
      ..sort(
        (a, b) => template[a.key]!.zIndex.compareTo(template[b.key]!.zIndex),
      );

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final W = constraints.maxWidth;
        final H = constraints.maxHeight;
        if (W <= 0 || H <= 0 || !W.isFinite || !H.isFinite) {
          return const SizedBox.shrink();
        }
        debugPrint(
          'AHVI_BOARD_CANVAS slots=${ordered.length} W=${W.toStringAsFixed(0)} H=${H.toStringAsFixed(0)}',
        );
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: ordered.map((entry) {
            final cfg = template[entry.key]!;
            final left = cfg.left * W;
            final top = cfg.top * H;
            final w = cfg.width * W;
            final h = cfg.height * H;
            if (!left.isFinite ||
                !top.isFinite ||
                !w.isFinite ||
                !h.isFinite ||
                w <= 0 ||
                h <= 0) {
              return const SizedBox.shrink();
            }
            final raw = entry.value;
            final imageUrl = raw['image_url']?.toString() ?? '';
            final isAnchor = raw['is_anchor'] == true;
            final name = raw['name']?.toString() ?? '';
            debugPrint(
              'AHVI_BOARD_TILE role=${entry.key} name=$name '
              'x=${left.toStringAsFixed(1)} y=${top.toStringAsFixed(1)} '
              'w=${w.toStringAsFixed(1)} h=${h.toStringAsFixed(1)} z=${cfg.zIndex} anchor=$isAnchor',
            );
            return Positioned(
              left: left,
              top: top,
              width: w,
              height: h,
              child: _FlatLayTile(
                imageUrl: imageUrl,
                isAnchor: isAnchor,
                name: name,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _FlatLayTile extends StatelessWidget {
  final String imageUrl;
  final bool isAnchor;
  final String name;
  const _FlatLayTile({
    required this.imageUrl,
    required this.isAnchor,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.checkroom,
                        color: Color(0xFFD0CAC3),
                        size: 32,
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.checkroom,
                      color: Color(0xFFD0CAC3),
                      size: 32,
                    ),
                  ),
          ),
        ),
        if (isAnchor)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF7B61FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Yours',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
