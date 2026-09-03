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
// NOTE: WardrobeItem is the existing repo model from wardrobe.dart ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â not a
// separate model file. Chat is opened through showAhviStylistChatSheet, the
// only public entry point the chat widget exposes.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/wardrobe.dart'; // WardrobeItem lives here
import 'package:myapp/services/backend_service.dart'; // styleWardrobeItem
import 'package:myapp/services/ahvi_style_diagnostics.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_layout_engine.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';
import 'package:myapp/app_localizations.dart'; // ÃƒÂ°Ã…Â¸Ã¢â‚¬Â Ã¢â‚¬Â¢ Localization
import 'pairing_engine.dart';
import 'package:myapp/feature/chat/models/ahvi_response_block.dart';
import 'package:myapp/feature/chat/services/ahvi_block_response_parser.dart';
import 'package:myapp/feature/chat/services/ahvi_processing_message.dart';
import 'package:myapp/feature/chat/widgets/ahvi_processing_bubble.dart';
import 'package:myapp/feature/chat/widgets/ahvi_style_this_processing_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/ahvi_outfit_board_card.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/widgets/try_on_coming_soon.dart';

// ============================================================
// SEMANTIC COLORS
// ============================================================
const Color _kSuccessColor = Color(0xFF34C759);
const Color _kDangerColor = Color(0xFFA32D2D);

typedef StyleWardrobeItemCall =
Future<Map<String, dynamic>?> Function({
required String itemId,
required String scenario,
Map<String, dynamic>? anchorItem,
String? occasion,
});

// ============================================================
// PUBLIC ENTRY POINT
// ============================================================
Future<void> showItemDetailModal(
    BuildContext context, {
      required WardrobeItem item,
      required List<WardrobeItem> allItems,
      Future<bool> Function(WardrobeItem item)? onWore,
      VoidCallback? onEdit,
      VoidCallback? onLike,
      VoidCallback? onShare,
      VoidCallback? onRemove,
      VoidCallback? onBuildOutfit,
      VoidCallback? onViewWearHistory,
      VoidCallback? onSetWearReminder,
      VoidCallback? onSetCareReminder,
      StyleWardrobeItemCall? styleWardrobeItemCall,
    }) {
  return showDialog<void>(
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
      styleWardrobeItemCall: styleWardrobeItemCall,
    ),
  );
}

// ============================================================
// MODAL WIDGET
// ============================================================
class _ItemDetailModal extends StatelessWidget {
  final WardrobeItem item;
  final List<WardrobeItem> allItems;
  final Future<bool> Function(WardrobeItem item)? onWore;
  final VoidCallback? onEdit;
  final VoidCallback? onLike;
  final VoidCallback? onShare;
  final VoidCallback? onRemove;
  final VoidCallback? onBuildOutfit;
  final VoidCallback? onViewWearHistory;
  final VoidCallback? onSetWearReminder;
  final VoidCallback? onSetCareReminder;
  final StyleWardrobeItemCall? styleWardrobeItemCall;

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
    this.styleWardrobeItemCall,
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
                              ? AppLocalizations.t(
                            context,
                            'item_detail_never_worn',
                          )
                              : AppLocalizations.t(
                            context,
                            'item_detail_worn_times',
                          ).replaceAll('{n}', '${item.worn}'),
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
                            item
                                .resolveImage(
                              surface: 'wardrobe_detail',
                            )
                                .url !=
                                null &&
                                item
                                    .resolveImage(
                                  surface: 'wardrobe_detail',
                                )
                                    .url!
                                    .isNotEmpty
                                ? Image.network(
                              item
                                  .resolveImage(
                                surface: 'wardrobe_detail',
                              )
                                  .url!,
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
                              onTap: () => _runStyleCta(
                                context,
                                item,
                                mode: 'style_this',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.groups_2_outlined,
                              label: 'Try-On',
                              onTap: () => _onTryOnComingSoon(context),
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
                              label: AppLocalizations.t(
                                context,
                                'item_detail_wore_today',
                              ),
                              onTap: () => _onWoreToday(context, item),
                              accentColor: _kSuccessColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SecondaryActionButton(
                              icon: Icons.edit_outlined,
                              label: AppLocalizations.t(context, 'common_edit'),
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
  // TRY-ON -> local Coming Soon UI until the feature is available.
  // ============================================================
  void _onTryOnComingSoon(BuildContext context) {
    unawaited(showTryOnComingSoon(context));
  }

  Future<void> _runStyleCta(
      BuildContext context,
      WardrobeItem item, {
        required String mode,
      }) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final BuildContext appContext = rootNav.context;
    await _performStyleRequest(appContext, item, mode: mode);
  }

  // ============================================================
  // Shared style-request runner: shows the loading spinner, calls the
  // backend, and routes the result to either the "insufficient wardrobe"
  // alert or the normal result sheet.
  //
  // Assumes any modal that needed dismissing (the item-detail dialog) has
  // already been popped by the caller ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â this lets it be called a second
  // time directly from the insufficient-wardrobe alert's "Stylize Using
  // Curated Assets" fallback without trying to pop anything extra.
  // ============================================================
  Future<void> _performStyleRequest(
      BuildContext appContext,
      WardrobeItem item, {
        required String mode,
      }) async {
    final rootNav = Navigator.of(appContext, rootNavigator: true);
    final diagnosticCorrelationId = AhviStyleDiagnostics.nextCorrelationId();

    // Loading state. Style This gets the premium branded card (pitch-facing
    // flow); every other mode keeps the original small AhviProcessingBubble
    // pill unchanged. AhviProcessingBubble itself is shared with the regular
    // chat "AHVI is thinking" bubble, so its own shape/colors stay untouched.
    showDialog<void>(
      context: appContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final maxWidth = size.width * 0.86;
        final maxHeight = size.height * 0.72;

        // Keep the processing surface inside the viewport on small phones.
        // The card itself remains unchanged; if its content becomes taller
        // than the available height, it can scroll instead of overflowing.
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(2),
                child: mode == 'style_this'
                    ? AhviStyleThisProcessingCard(itemName: item.name)
                    : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: AhviProcessingBubble(
                      message: ahviProcessingMessage(
                        AhviProcessingContext.buildOutfit,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    debugPrint('AHVI_MODAL_GUARD start flow=styleCta mode=$mode');
    Map<String, dynamic>? result;
    var timedOut = false;
    try {
      // Timeout so a slow backend can never strand the user behind the
      // barrierDismissible:false spinner (ANR / frozen-screen class).
      final resolvedImage = item.resolveImage(surface: 'style_this_request');
      final request =
          styleWardrobeItemCall ?? BackendService().styleWardrobeItem;
      debugPrint(
        'AHVI_STYLE_THIS_REQUEST correlation_id=$diagnosticCorrelationId '
            'anchor_item_id=${AhviStyleDiagnostics.maskIdentifier(item.id)} '
            'scenario=$mode source_policy=wardrobe',
      );
      result = await request(
        itemId: item.id,
        scenario: mode,
        anchorItem: {
          ...item.raw,
          'item_id': item.id,
          'id': item.id,
          'name': item.name,
          'category': item.cat,
          'role': item.cat,
          if (item.imageUrl != null) 'image_url': item.imageUrl,
          if (item.maskedUrl != null) 'masked_url': item.maskedUrl,
          if (item.normalizedUrl != null) 'normalized_url': item.normalizedUrl,
          if (resolvedImage.url != null)
            'resolved_image_url': resolvedImage.url,
          'resolved_image_field': resolvedImage.field,
          'image_source_kind': resolvedImage.sourceKind,
          'expected_transparent': resolvedImage.expectedTransparent,
          'source': 'wardrobe',
          'source_policy': 'wardrobe',
          'anchor_item_id': item.id,
          'selected_item_id': item.id,
          'scenario': mode,
          'interaction_mode': mode,
          'locked': true,
          'anchor': true,
        },
      ).timeout(const Duration(seconds: 60));
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

    final resultData = result?['data'] is Map
        ? Map<String, dynamic>.from(result!['data'] as Map)
        : const <String, dynamic>{};
    final resultOutfit = result?['outfit'] ?? resultData['outfit'];
    final resultItems = resultOutfit is Map
        ? (resultOutfit['items'] ??
        resultOutfit['board_items'] ??
        resultOutfit['boardItems'])
        : null;
    debugPrint(
      'AHVI_LIVE_STYLE_HANDLER '
          'source_file=ahvi_item_detail_modal.dart function=_performStyleRequest '
          'resolved_route=$mode board_policy=wardrobe '
          'selected_alias=${resultOutfit is Map ? 'outfit' : 'none'} '
          'raw_count=${resultOutfit is Map ? 1 : 0} '
          'accepted_count=${resultOutfit is Map ? 1 : 0} rejected_count=0 '
          'rejection_predicates=none '
          'first_board_keys=${resultOutfit is Map ? resultOutfit.keys.join(',') : 'none'} '
          'first_item_keys=${resultItems is List && resultItems.isNotEmpty && resultItems.first is Map ? (resultItems.first as Map).keys.join(',') : 'none'} '
          'final_renderer=${mode == 'build_outfit' && resultOutfit is Map ? 'canonical_editorial_style' : 'pending'} '
          'final_rendered_count=${resultOutfit is Map ? 1 : 0}',
    );

    if (!appContext.mounted) return;
    if (timedOut) {
      _showStyleRequestFailure(
        appContext,
        item: item,
        message: AppLocalizations.t(appContext, 'item_detail_timeout_message'),
        failedFields: const ['timeout'],
      );
      return;
    }

    if (mode == 'style_this') {
      final diagnosticDirections = _styleThisDirectionsFromResponse(result);
      final diagnosticFailures = diagnosticDirections.isEmpty
          ? [
        const ['visual_directions'],
      ]
          : diagnosticDirections
          .map(
            (direction) => _directionContractFailures(direction, item.id),
      )
          .toList(growable: false);
      AhviStyleDiagnostics.logStyleThisContract(
        correlationId: diagnosticCorrelationId,
        response: result,
        directions: diagnosticDirections,
        failures: diagnosticFailures,
        anchorItemId: item.id,
      );
      final directions = _canonicalStyleThisDirections(result, item.id);
      if (result?['success'] != true || directions.isEmpty) {
        final failedFields = _styleThisContractFailures(result, item.id);
        _showStyleRequestFailure(
          appContext,
          item: item,
          message: 'AHVI couldn’t complete that.',
          failedFields: failedFields,
        );
        return;
      }

      if (rootNav.canPop()) rootNav.pop(); // close item detail after success
      _showStyleResultSheet(
        appContext,
        mode: mode,
        item: item,
        result: result,
        visualDirections: directions,
      );
      return;
    }

    // DATA SUFFICIENCY CHECK ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the backend couldn't assemble a real
    // outfit/board from the user's own pieces. Surface a dedicated alert
    // (with a one-tap fallback into curated-asset styling) instead of
    // dropping the user into an empty/broken result sheet.
    final bool insufficientWardrobe =
        result?['intent'] == 'insufficient_wardrobe' ||
            result?['alert'] == true;
    if (insufficientWardrobe) {
      _showInsufficientWardrobeAlert(appContext, item: item, result: result!);
      return;
    }

    _showStyleResultSheet(appContext, mode: mode, item: item, result: result);
  }

  List<Map<String, dynamic>> _canonicalStyleThisDirections(
      Map<String, dynamic>? result,
      String anchorItemId,
      ) {
    if (result == null) return const [];
    final parsed = parseAhviResponse(result);
    AhviResponseBlock? visualDirectionsBlock;
    for (final block in parsed.blocks) {
      if (block.type == AhviBlockType.visualDirections) {
        visualDirectionsBlock = block;
        break;
      }
    }
    final rawDirections = _asMapList(visualDirectionsBlock?.data['directions']);
    final directions = rawDirections
        .map((direction) {
      final interactionMode = (direction['interaction_mode'] ?? '')
          .toString()
          .trim();
      return <String, dynamic>{
        ...direction,
        if (interactionMode.isEmpty) 'interaction_mode': 'style_this',
        'anchor_item_id':
        direction['anchor_item_id'] ??
            direction['anchorItemId'] ??
            direction['selected_item_id'] ??
            direction['selectedItemId'] ??
            anchorItemId,
        'selected_item_id':
        direction['selected_item_id'] ??
            direction['selectedItemId'] ??
            direction['anchor_item_id'] ??
            direction['anchorItemId'] ??
            anchorItemId,
        'originating_item_id': anchorItemId,
      };
    })
        .toList(growable: false);
    return directions
        .where(
          (direction) =>
      _directionContractFailures(direction, anchorItemId).isEmpty,
    )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _styleThisDirectionsFromResponse(
      Map<String, dynamic>? result,
      ) {
    if (result == null) return const [];
    final parsed = parseAhviResponse(result);
    for (final block in parsed.blocks) {
      if (block.type == AhviBlockType.visualDirections) {
        return _asMapList(block.data['directions']);
      }
    }
    return const [];
  }

  List<String> _styleThisContractFailures(
      Map<String, dynamic>? result,
      String anchorItemId,
      ) {
    if (result == null) return const ['response'];
    if (result['success'] != true) return const ['success'];
    final parsed = parseAhviResponse(result);
    final failures = <String>[];
    var foundDirections = false;
    for (final block in parsed.blocks) {
      if (block.type != AhviBlockType.visualDirections) continue;
      final directions = _asMapList(block.data['directions']);
      foundDirections = directions.isNotEmpty;
      for (final direction in directions) {
        failures.addAll(_directionContractFailures(direction, anchorItemId));
      }
    }
    if (!foundDirections) failures.add('visual_directions');
    return failures.toSet().toList(growable: false);
  }

  List<String> _directionContractFailures(
      Map<String, dynamic> direction,
      String anchorItemId,
      ) {
    final failures = <String>[];
    final boardId = (direction['board_id'] ?? '').toString().trim();
    final revision = direction['revision'];
    final sourcePolicy = (direction['source_policy'] ?? '').toString().trim();
    final scenario = (direction['scenario'] ?? '').toString().trim();
    final interactionMode = (direction['interaction_mode'] ?? 'style_this')
        .toString()
        .trim();
    final declaredAnchor =
    (direction['anchor_item_id'] ??
        direction['anchorItemId'] ??
        direction['originating_item_id'] ??
        direction['originatingItemId'] ??
        '')
        .toString()
        .trim();
    final items = _asMapList(
      direction['board_items'] ?? direction['boardItems'],
    );
    String itemId(Map<String, dynamic> item) =>
        (item['item_id'] ?? item['id'] ?? item[r'$id'] ?? '').toString().trim();

    if (boardId.isEmpty || boardId.toLowerCase().startsWith('outfit_card_')) {
      failures.add('board_id');
    }
    if (revision is! num || revision < 1) failures.add('revision');
    if (sourcePolicy != 'wardrobe') failures.add('source_policy');
    if (scenario != 'style_this') failures.add('scenario');
    if (interactionMode != 'style_this') failures.add('interaction_mode');
    if (items.isEmpty || items.any((item) => itemId(item).isEmpty)) {
      failures.add('stable_item_ids');
    }
    final anchorMatches = items
        .where((item) => itemId(item) == anchorItemId)
        .length;
    if (declaredAnchor != anchorItemId) {
      failures.add('anchor_declaration');
    }
    if (anchorMatches != 1) {
      failures.add('anchor_item_id');
    }
    return failures;
  }

  void _showStyleRequestFailure(
      BuildContext appContext, {
        required WardrobeItem item,
        required String message,
        required List<String> failedFields,
      }) {
    debugPrint(
      'AHVI_STYLE_THIS_CONTRACT_FAILED '
          'anchor_item_id=${AhviStyleDiagnostics.maskIdentifier(item.id)} '
          'failed_fields=${failedFields.isEmpty ? "unknown" : failedFields.join(",")}',
    );
    final messenger = ScaffoldMessenger.maybeOf(appContext);
    if (messenger == null) return;

    // SnackBarAction can keep an action snackbar visible until the user
    // interacts with it. Use a normal button inside the snackbar instead,
    // so the failure message disappears automatically.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  unawaited(
                    _performStyleRequest(
                      appContext,
                      item,
                      mode: 'style_this',
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ============================================================
  // INSUFFICIENT WARDROBE ALERT
  // Shown when response['intent'] == 'insufficient_wardrobe' (or
  // response['alert'] == true). Displays the backend's own explanation
  // verbatim and offers:
  //   - "Got it"                         -> dismiss
  //   - "Stylize Using Curated Assets"   -> retry in 'style_this' mode,
  //     which the backend answers from curated styling directions rather
  //     than requiring real pairings from the user's own wardrobe.
  // ============================================================
  void _showInsufficientWardrobeAlert(
      BuildContext appContext, {
        required WardrobeItem item,
        required Map<String, dynamic> result,
      }) {
    final String message =
        (result['context'] ?? result['message'])?.toString() ??
            AppLocalizations.t(
              appContext,
              'item_detail_insufficient_wardrobe_default',
            );

    showDialog<void>(
      context: appContext,
      builder: (dialogContext) {
        final t = Theme.of(dialogContext).extension<AppThemeTokens>()!;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0x33A32D2D),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: _kDangerColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            AppLocalizations.t(
                              dialogContext,
                              'item_detail_wardrobe_alert_title',
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.4,
                      color: const Color(0xFF4A4A4A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: const BorderSide(color: Color(0xFFE5E5EA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.t(
                              dialogContext,
                              'item_detail_wardrobe_alert_dismiss',
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            // Fallback: retry as 'style_this', which the
                            // backend can answer from curated assets
                            // instead of the user's own wardrobe pairings.
                            _performStyleRequest(
                              appContext,
                              item,
                              mode: 'style_this',
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [t.accent.primary, t.accent.secondary],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                            child: Text(
                              AppLocalizations.t(
                                dialogContext,
                                'item_detail_wardrobe_alert_stylize',
                              ),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
        List<Map<String, dynamic>> visualDirections = const [],
      }) {
    final bool ok = result != null && result['success'] == true;
    final String? message = result?['message']?.toString();
    final List<Map<String, dynamic>> directions = mode == 'style_this'
        ? visualDirections
        : <Map<String, dynamic>>[];
    final resultData = result?['data'] is Map
        ? Map<String, dynamic>.from(result!['data'] as Map)
        : const <String, dynamic>{};
    final rawOutfit = mode == 'build_outfit'
        ? (result?['outfit'] ?? resultData['outfit'])
        : null;
    final Map<String, dynamic>? outfit = rawOutfit is Map
        ? Map<String, dynamic>.from(rawOutfit)
        : null;
    final buildItems = outfit == null
        ? const []
        : outfit['items'] ??
        outfit['board_items'] ??
        outfit['boardItems'] ??
        [];
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

    debugPrint(
      'AHVI_ACTIVE_${mode == 'style_this' ? 'STYLE_THIS' : 'BUILD_OUTFIT'}_SURFACE '
          'source_file=ahvi_item_detail_modal.dart function=_showStyleResultSheet '
          'requested_mode=$mode '
          'interaction_mode=${mode == 'style_this' ? 'style_this' : 'build_outfit'} '
          'canonical_renderer_reached=$usesActiveBoard '
          'board_count=${mode == 'style_this'
          ? directions.length
          : hasBuildBoardContract
          ? 1
          : 0} '
          'selected_surface=${usesActiveBoard ? 'canonical_editorial_carousel' : 'legacy_fallback'}',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: isAnchorBoard || usesActiveBoard ? 0.9 : 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) {
          // Theme-aware: follows the app's current light/dark mode instead
          // of a palette hardcoded to the content type.
          final colors = _ResultSheetColors.of(ctx);
          return Container(
            decoration: BoxDecoration(
              color: colors.sheetBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
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
                      color: colors.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  mode == 'style_this'
                      ? AppLocalizations.t(ctx, 'item_detail_style_directions')
                      : AppLocalizations.t(ctx, 'item_detail_build_outfit'),
                  style: TextStyle(
                    color: colors.title,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.name,
                  style: TextStyle(color: colors.subtitle, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (!ok || (message != null && message.isNotEmpty))
                  _StyleNotice(
                    text: (message != null && message.isNotEmpty)
                        ? message
                        : AppLocalizations.t(ctx, 'item_detail_friendly_fail'),
                    colors: colors,
                  ),
                if (mode == 'style_this' && hasStyleBoardContract)
                  VisualDirectionCarousel(
                    directions: directions,
                    cardWidth: MediaQuery.sizeOf(ctx).width - 40,
                    curationReveal: false,
                    wardrobeById: buildWardrobeImageMap([
                      for (final wardrobeItem in allItems)
                        {
                          ...wardrobeItem.raw,
                          'id': wardrobeItem.id,
                          r'$id': wardrobeItem.id,
                        },
                    ]),
                  ),

                if (mode == 'build_outfit' &&
                    hasBuildBoardContract &&
                    outfit != null)
                  AhviOutfitBoardCard(
                    direction: <String, dynamic>{
                      ...outfit,
                      'direction_name': outfit['title'],
                      'interaction_mode': 'build_outfit',
                      'scenario': 'build_outfit',
                      'board_items': buildItems,
                    },
                    width: MediaQuery.sizeOf(ctx).width - 40,
                    wardrobeById: buildWardrobeImageMap([
                      for (final wardrobeItem in allItems)
                        {
                          ...wardrobeItem.raw,
                          'id': wardrobeItem.id,
                          r'$id': wardrobeItem.id,
                        },
                    ]),
                  ),

                if (mode == 'build_outfit' &&
                    !hasBuildBoardContract &&
                    isAnchorBoard &&
                    outfit != null)
                  _AnchorOutfitBoardCard(outfit: outfit, colors: colors),

                if (mode == 'build_outfit' &&
                    !hasBuildBoardContract &&
                    !isAnchorBoard &&
                    outfit != null)
                  _StyleDirectionCard(
                    direction: outfit,
                    reasonKey: 'reason',
                    colors: colors,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onWoreToday(BuildContext context, WardrobeItem item) async {
    final logged = await onWore?.call(item) ?? false;
    if (!logged || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.t(
            context,
            'item_detail_marked_worn',
          ).replaceAll('{name}', item.name),
        ),
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
      isScrollControlled: true,
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
              AppLocalizations.t(context, 'item_detail_style_this'),
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
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
            AppLocalizations.t(context, 'item_detail_works_well_with'),
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
              AppLocalizations.t(context, 'item_detail_works_well_empty'),
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
                          (p
                              .resolveImage(
                            surface: 'works_well_with',
                          )
                              .url !=
                              null &&
                              p
                                  .resolveImage(
                                surface: 'works_well_with',
                              )
                                  .url!
                                  .isNotEmpty)
                              ? Image.network(
                            p
                                .resolveImage(
                              surface: 'works_well_with',
                            )
                                .url!,
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
                  AppLocalizations.t(
                    context,
                    pairings.length - 3 == 1
                        ? 'item_detail_more_items'
                        : 'item_detail_more_items_plural',
                  ).replaceAll('{n}', '${pairings.length - 3}'),
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
                AppLocalizations.t(context, 'item_detail_style_insights'),
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
                  title: AppLocalizations.t(context, 'item_detail_best_for'),
                  items: bestFor,
                  good: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InsightColumn(
                  title: AppLocalizations.t(context, 'item_detail_avoid'),
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
            'ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â',
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
      label = AppLocalizations.t(context, 'item_detail_match_great');
    } else if (matchCount >= goodThreshold) {
      label = AppLocalizations.t(context, 'item_detail_match_good');
    } else if (matchCount >= limitedThreshold) {
      label = AppLocalizations.t(context, 'item_detail_match_limited');
    } else {
      label = AppLocalizations.t(context, 'item_detail_match_add_more');
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
                AppLocalizations.t(context, 'item_detail_wardrobe_match'),
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
            AppLocalizations.t(
              context,
              matchCount == 1
                  ? 'item_detail_match_item'
                  : 'item_detail_match_items',
            ).replaceAll('{n}', '$matchCount'),
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
                    AppLocalizations.t(context, 'item_detail_more_options'),
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
              label: AppLocalizations.t(
                context,
                'item_detail_add_to_favorites',
              ),
              onTap: () {
                Navigator.of(context).pop();
                onAddToFavorites?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.t(
                        context,
                        'item_detail_added_favorites',
                      ),
                    ),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                );
              },
            ),
            _OptionRow(
              icon: Icons.history,
              label: AppLocalizations.t(context, 'item_detail_wear_history'),
              onTap: () {
                Navigator.of(context).pop();
                onViewWearHistory?.call();
              },
            ),
            _OptionRow(
              icon: Icons.ios_share,
              label: AppLocalizations.t(context, 'item_detail_share'),
              onTap: () {
                Navigator.of(context).pop();
                onShare?.call();
              },
            ),
            _OptionRow(
              icon: Icons.notifications_outlined,
              label: AppLocalizations.t(context, 'item_detail_remind_wear'),
              onTap: () {
                Navigator.of(context).pop();
                onSetWearReminder?.call();
              },
            ),
            _OptionRow(
              icon: Icons.local_laundry_service_outlined,
              label: AppLocalizations.t(context, 'item_detail_care_reminder'),
              onTap: () {
                Navigator.of(context).pop();
                onSetCareReminder?.call();
              },
            ),
            _OptionRow(
              icon: Icons.delete_outline,
              label: AppLocalizations.t(
                context,
                'item_detail_delete_permanently',
              ),
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
                    AppLocalizations.t(context, 'item_detail_close'),
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
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: fg,
                    ),
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
                    AppLocalizations.t(
                      context,
                      pairings.length == 1
                          ? 'item_detail_pairing_match'
                          : 'item_detail_pairing_matches',
                    ).replaceAll('{n}', '${pairings.length}'),
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
                              (p
                                  .resolveImage(
                                surface: 'works_well_with',
                              )
                                  .url !=
                                  null &&
                                  p
                                      .resolveImage(
                                    surface: 'works_well_with',
                                  )
                                      .url!
                                      .isNotEmpty)
                                  ? Image.network(
                                p
                                    .resolveImage(
                                  surface: 'works_well_with',
                                )
                                    .url!,
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
                    AppLocalizations.t(context, 'item_detail_close'),
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
//
// Theme-aware: these sheets used to be hardcoded to a fixed dark
// palette (or fixed white, for the anchor board). They now follow the
// app's ambient Theme brightness via _ResultSheetColors.of(context), so
// the sheet matches whichever mode (light/dark) the rest of the app is
// currently in.
// ============================================================
class _ResultSheetColors {
  final bool isDark;
  final Color sheetBg;
  final Color dragHandle;
  final Color title;
  final Color subtitle;
  final Color cardBg;
  final Color cardBorder;
  final Color cardTitle;
  final Color cardBody;
  final Color cardMuted;
  final Color chipBg;
  final Color chipBorder;
  final Color chipText;
  final Color chipAccentBg;
  final Color chipAccentBorder;
  final Color chipAccentText;
  final Color noticeBg;
  final Color noticeText;
  // The flat-lay board canvas intentionally stays a light, neutral
  // "photography backdrop" in both modes ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the tiles use dark drop
  // shadows that read correctly only against a light surface, and
  // outfit-board UIs conventionally keep the image canvas light even
  // inside a dark shell (Pinterest, Instagram, etc). Flip this if you'd
  // rather the whole board go dark too.
  final Color boardCanvasBg;
  final Color anchorItemThumbBg;
  final Color anchorItemName;

  const _ResultSheetColors({
    required this.isDark,
    required this.sheetBg,
    required this.dragHandle,
    required this.title,
    required this.subtitle,
    required this.cardBg,
    required this.cardBorder,
    required this.cardTitle,
    required this.cardBody,
    required this.cardMuted,
    required this.chipBg,
    required this.chipBorder,
    required this.chipText,
    required this.chipAccentBg,
    required this.chipAccentBorder,
    required this.chipAccentText,
    required this.noticeBg,
    required this.noticeText,
    required this.boardCanvasBg,
    required this.anchorItemThumbBg,
    required this.anchorItemName,
  });

  factory _ResultSheetColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _dark : _light;
  }

  static const _dark = _ResultSheetColors(
    isDark: true,
    sheetBg: Color(0xFF14110F),
    dragHandle: Colors.white24,
    title: Colors.white,
    subtitle: Colors.white60,
    cardBg: Color(0x0DFFFFFF), // Colors.white @ 5%
    cardBorder: Colors.white12,
    cardTitle: Colors.white,
    cardBody: Colors.white60,
    cardMuted: Colors.white38,
    chipBg: Color(0x14FFFFFF), // Colors.white @ 8%
    chipBorder: Colors.white12,
    chipText: Colors.white,
    chipAccentBg: Color(0x332E7D5B),
    chipAccentBorder: Color(0x662E7D5B),
    chipAccentText: Color(0xFF8FE3BE),
    noticeBg: Color(0x33A32D2D),
    noticeText: Colors.white70,
    boardCanvasBg: Colors.white,
    anchorItemThumbBg: Color(0xFFF7F4EE),
    anchorItemName: Colors.white,
  );

  static const _light = _ResultSheetColors(
    isDark: false,
    sheetBg: Colors.white,
    dragHandle: Color(0x1A000000),
    title: Color(0xFF1A1A1A),
    subtitle: Color(0xFF8A8A8E),
    cardBg: Color(0xFFF7F7FA),
    cardBorder: Color(0xFFEDEDF2),
    cardTitle: Color(0xFF1A1A1A),
    cardBody: Color(0xFF6B6B6B),
    cardMuted: Color(0xFF8A8A8E),
    chipBg: Color(0xFFF2F2F7),
    chipBorder: Color(0xFFE5E5EA),
    chipText: Color(0xFF1A1A1A),
    chipAccentBg: Color(0x1A2E7D5B),
    chipAccentBorder: Color(0x662E7D5B),
    chipAccentText: Color(0xFF1F8F5F),
    noticeBg: Color(0x1AA32D2D),
    noticeText: Color(0xFF7A2323),
    boardCanvasBg: Colors.white,
    anchorItemThumbBg: Color(0xFFF7F4EE),
    anchorItemName: Color(0xFF1A1A1A),
  );
}

class _StyleNotice extends StatelessWidget {
  final String text;
  final _ResultSheetColors colors;
  const _StyleNotice({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.noticeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: colors.noticeText, fontSize: 13, height: 1.35),
      ),
    );
  }
}

class _StyleDirectionCard extends StatelessWidget {
  final Map<String, dynamic> direction;
  final String reasonKey;
  final _ResultSheetColors colors;
  const _StyleDirectionCard({
    required this.direction,
    required this.colors,
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
    final title =
    (direction['title'] ??
        AppLocalizations.t(context, 'item_detail_your_look'))
        .toString();
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
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.cardTitle,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(
                color: colors.cardBody,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              AppLocalizations.t(context, 'item_detail_wear_label'),
              style: TextStyle(
                color: colors.cardMuted,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map(
                    (n) => _StyleChip(label: n, accent: false, colors: colors),
              )
                  .toList(),
            ),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              AppLocalizations.t(context, 'item_detail_missing_shop_these'),
              style: TextStyle(
                color: colors.cardMuted,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: missing
                  .map(
                    (n) => _StyleChip(label: n, accent: true, colors: colors),
              )
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
  final _ResultSheetColors colors;
  const _StyleChip({
    required this.label,
    required this.accent,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent ? colors.chipAccentBg : colors.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent ? colors.chipAccentBorder : colors.chipBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent ? colors.chipAccentText : colors.chipText,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ============================================================
// ANCHOR OUTFIT BOARD ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â visual 9:16 board with source badges
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
  final _ResultSheetColors colors;
  const _AnchorOutfitBoardCard({required this.outfit, required this.colors});

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
              color: colors.boardCanvasBg,
              child: _AnchorBoardCanvas(items: rawItems),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // item list with source badges
        ...rawItems.map((raw) => _AnchorItemRow(raw: raw, colors: colors)),
        if (stylingNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            stylingNote,
            style: TextStyle(color: colors.cardBody, fontSize: 13, height: 1.4),
          ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            AppLocalizations.t(context, 'item_detail_missing_shop_these'),
            style: TextStyle(
              color: colors.cardMuted,
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
              return _StyleChip(label: label, accent: true, colors: colors);
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
  final _ResultSheetColors colors;
  const _AnchorItemRow({required this.raw, required this.colors});

  @override
  Widget build(BuildContext context) {
    final name = raw['name']?.toString() ?? '';
    final isAnchor = raw['is_anchor'] == true;
    final source = raw['source']?.toString() ?? 'wardrobe';
    final imageUrl = raw['image_url']?.toString() ?? '';

    final sourceLabel = isAnchor
        ? AppLocalizations.t(context, 'item_detail_source_your_piece')
        : (source == 'wardrobe'
        ? AppLocalizations.t(context, 'item_detail_source_wardrobe')
        : AppLocalizations.t(context, 'item_detail_source_suggested'));
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
              color: colors.anchorItemThumbBg,
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
              style: TextStyle(
                color: colors.anchorItemName,
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
// FLAT-LAY BOARD CANVAS ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â absolute-positioned 9:16 layout
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
              child: Text(
                AppLocalizations.t(context, 'item_detail_yours_badge'),
                style: const TextStyle(
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
