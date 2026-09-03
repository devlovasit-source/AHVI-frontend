import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/ahvi_style_diagnostics.dart';
import 'package:myapp/feature/chat/services/ahvi_processing_message.dart';
import 'package:myapp/feature/chat/services/fashion_item_filter.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/editorial_collage.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/style_board_controller.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/shareable_outfit_board.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

typedef OutfitBoardMessageSender = void Function(String message);
typedef OutfitBoardTap = void Function(Map<String, dynamic> board);
typedef OutfitBoardStateChanged = void Function(Map<String, dynamic> board);

const double editorialBoardHeaderHeight = 30;
const double editorialBoardContextHeight = 72;

/// Approved db7f925 presentation contract. Layout templates consume both axes,
/// so every item count must receive the same canvas aspect ratio.
double editorialBoardCanvasHeightForWidth(double width) {
  final safeWidth = width.isFinite && width > 0 ? width : 320.0;
  return (safeWidth * 0.68).clamp(194.0, 270.0).toDouble();
}

/// Keeps bounded display copy at a word or sentence boundary instead of using
/// a fading paint effect that can leave a visibly incomplete thought.
String editorialSentenceSafeCopy(String value, {required int maxCharacters}) {
  final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.length <= maxCharacters) return text;
  final limit = math.min(maxCharacters, text.length);
  for (var i = limit - 1; i >= (limit * 0.55).floor(); i--) {
    if ('.!?'.contains(text[i])) return text.substring(0, i + 1).trim();
  }
  final wordEnd = text.lastIndexOf(' ', limit);
  final end = wordEnd > 0 ? wordEnd : limit;
  return '${text.substring(0, end).trimRight()}…';
}

enum BoardInteractionMode { recommendation, styleThis, buildOutfit }

extension BoardInteractionModeName on BoardInteractionMode {
  String get wireName => switch (this) {
    BoardInteractionMode.recommendation => 'recommendation',
    BoardInteractionMode.styleThis => 'style_this',
    BoardInteractionMode.buildOutfit => 'build_outfit',
  };

  bool get supportsMutation => this != BoardInteractionMode.recommendation;
}

BoardInteractionMode inferBoardInteractionMode(Map<String, dynamic> board) {
  String normalized(Object? value) =>
      value?.toString().trim().toLowerCase().replaceAll(
        RegExp(r'[\s-]+'),
        '_',
      ) ??
      '';

  final value = [
    board['interaction_mode'],
    board['interactionMode'],
    board['scenario'],
  ].map(normalized).firstWhere((value) => value.isNotEmpty, orElse: () => '');
  return switch (value) {
    'style_this' => BoardInteractionMode.styleThis,
    'build_outfit' => BoardInteractionMode.buildOutfit,
    _ => BoardInteractionMode.recommendation,
  };
}

String _shuffleFailureMessage(String code) => switch (code) {
  'ALL_ITEMS_LOCKED' => 'Unlock an item to shuffle.',
  'NO_REPLACEMENT_FOUND' =>
    'AHVI couldn’t find a stronger replacement right now.',
  'FIXED_ITEMS_INCOMPATIBLE' =>
    'These locked pieces can’t form a complete look together. Unlock one piece and try again.',
  'BOARD_REVISION_CONFLICT' =>
    'This board changed. Your current look has been preserved.',
  'SOURCE_POLICY_CHANGED' || 'SOURCE_POLICY_VIOLATION' =>
    'The board’s styling source changed unexpectedly. Your current look has been preserved.',
  'STYLE_ASSET_POOL_EMPTY' =>
    'No curated pieces are available for this look right now.',
  'BOARD_SOURCE_POLICY_UNKNOWN' =>
    'This board is missing its styling source. Ask AHVI for a fresh look to continue.',
  'BOARD_NOT_PERSISTED' =>
    'This Style This look can’t be shuffled yet. Ask AHVI for a fresh look to continue.',
  'SHUFFLE_NOT_AVAILABLE' => 'Shuffle isn’t available for this recommendation.',
  _ =>
    'We couldn’t refresh these pieces. Your current look has been preserved.',
};

/// Persists a board and returns the created document id (or null on failure).
/// Overridable so tests can drive Save without a live Appwrite backend.
typedef BoardSaveFn =
    Future<String?> Function({
      required String occasion,
      required String outfitDescription,
      required String imageUrl,
      required String title,
      required List<String> itemIds,
      required List<Map<String, dynamic>> items,
      required bool isFavourite,
    });

class AhviOutfitBoardCard extends StatefulWidget {
  final Map<String, dynamic> direction;
  final double width;
  final OutfitBoardMessageSender? onSendMessage;
  final Map<String, dynamic> editorialCover;
  final OutfitBoardStateChanged? onBoardStateChanged;

  /// Tap on the flat-lay visual opens the legacy stylist-reasoning detail
  /// sheet. The action bar keeps its own handlers and is excluded from this
  /// gesture so Save / Shuffle / Style This / Missing never trigger the sheet.
  final OutfitBoardTap? onTapBoard;
  final StyleBoardShuffleCall? shuffleCall;
  final BoardSaveFn? saveBoardOverride;
  final Map<String, Map<String, dynamic>> wardrobeById;

  const AhviOutfitBoardCard({
    super.key,
    required this.direction,
    required this.width,
    this.onSendMessage,
    this.editorialCover = const {},
    this.onBoardStateChanged,
    this.onTapBoard,
    this.shuffleCall,
    this.saveBoardOverride,
    this.wardrobeById = const {},
  });

  @override
  State<AhviOutfitBoardCard> createState() => _AhviOutfitBoardCardState();
}

class _AhviOutfitBoardCardState extends State<AhviOutfitBoardCard> {
  late OutfitBoardModel _model;
  late StyleBoardData _initialBoard;
  Map<String, Map<String, dynamic>> _wardrobeById = const {};
  StyleBoardController? _controller;
  StyleBoardData? _pendingBoard;
  StyleBoardData? _pendingImageBoard;
  // Wraps ONLY the shareable board visual (context strip + collage), never the
  // mutation/action controls, so Share captures a clean image.
  final GlobalKey _shareBoundaryKey = GlobalKey();

  BoardInteractionMode get _interactionMode =>
      inferBoardInteractionMode(widget.direction);

  @override
  void initState() {
    super.initState();
    _wardrobeById = widget.wardrobeById;
    _replaceBoard(_parseBoard(widget));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.wardrobeById.isNotEmpty) return;
    try {
      final appwrite = Provider.of<AppwriteService>(context);
      final next = buildWardrobeImageMap(appwrite.cachedWardrobeItems);
      if (mapEquals(_wardrobeById, next)) return;
      _wardrobeById = next;
      _refreshBoardImages(_parseBoard(widget));
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AhviOutfitBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousWardrobe = _wardrobeById;
    if (widget.wardrobeById.isNotEmpty || oldWidget.wardrobeById.isNotEmpty) {
      _wardrobeById = widget.wardrobeById;
    }
    final incoming = _parseBoard(widget);
    final wardrobeChanged = !mapEquals(previousWardrobe, _wardrobeById);
    final modeChanged =
        inferBoardInteractionMode(oldWidget.direction) !=
        inferBoardInteractionMode(widget.direction);
    final boardChanged =
        modeChanged || _isMeaningfulBoardUpdate(_initialBoard, incoming.board);
    if (wardrobeChanged && !boardChanged) {
      _refreshBoardImages(incoming);
      return;
    }
    if (!boardChanged) {
      return;
    }
    if (_controller?.state.isShuffling == true &&
        incoming.board.boardId == _initialBoard.boardId) {
      _pendingBoard = incoming.board;
      return;
    }
    _replaceBoard(incoming);
  }

  ({OutfitBoardModel model, StyleBoardData board}) _parseBoard(
    AhviOutfitBoardCard source,
  ) {
    final model = OutfitBoardModel.fromPayload(
      source.direction,
      editorialCover: source.editorialCover,
    );
    return (
      model: model,
      board: _toStyleBoardData(
        model,
        source.direction,
        wardrobeById: _wardrobeById,
      ),
    );
  }

  bool _isMeaningfulBoardUpdate(StyleBoardData current, StyleBoardData next) {
    if (current.boardId != next.boardId || current.revision != next.revision) {
      return true;
    }
    final currentIds = current.items.map((item) => item.itemId).toList()
      ..sort();
    final nextIds = next.items.map((item) => item.itemId).toList()..sort();
    return currentIds.join('\u0000') != nextIds.join('\u0000');
  }

  void _replaceBoard(({OutfitBoardModel model, StyleBoardData board}) parsed) {
    _controller?.removeListener(_handleControllerChange);
    _controller?.dispose();
    _model = parsed.model;
    _initialBoard = parsed.board;
    _pendingBoard = null;
    _pendingImageBoard = null;
    final lockedItemIds = parsed.board.items
        .where((item) => item.isLocked && item.hasStableIdentity)
        .map((item) => item.itemId)
        .toSet();
    StyleBoardItem? originatingItem;
    var requestedAnchor = '';
    if (_interactionMode == BoardInteractionMode.styleThis) {
      lockedItemIds.clear();
      requestedAnchor = _text(
        widget.direction['originating_item_id'] ??
            widget.direction['originatingItemId'] ??
            widget.direction['anchor_item_id'] ??
            widget.direction['anchorItemId'],
      );
      final anchor = parsed.board.items.where((item) {
        return item.hasStableIdentity && item.itemId == requestedAnchor;
      }).firstOrNull;
      final wardrobeAnchor = parsed.board.items.where((item) {
        return item.hasStableIdentity && item.source == 'wardrobe';
      }).firstOrNull;
      final fallbackAnchor = parsed.board.items
          .where((item) => item.hasStableIdentity)
          .firstOrNull;
      originatingItem =
          anchor ??
          (requestedAnchor.isEmpty ? wardrobeAnchor ?? fallbackAnchor : null);
      if (originatingItem != null) lockedItemIds.add(originatingItem.itemId);
    }
    final stateItems = parsed.board.items
        .map(
          (item) => _interactionMode == BoardInteractionMode.styleThis
              ? item.copyWith(isLocked: lockedItemIds.contains(item.itemId))
              : lockedItemIds.contains(item.itemId)
              ? item.copyWith(isLocked: true)
              : item,
        )
        .toList(growable: false);
    final state = StyleBoardState(
      boardId: parsed.board.boardId,
      revision: parsed.board.revision,
      scenario: parsed.board.scenario,
      sourcePolicy: parsed.board.sourcePolicy,
      allowWardrobeFallback: parsed.board.allowWardrobeFallback,
      shuffleAvailable: parsed.board.shuffleAvailable,
      items: stateItems,
      lockedItemIds: lockedItemIds,
    );
    if (_interactionMode == BoardInteractionMode.styleThis) {
      final initialLockedIds = state.lockedItemIds.toList()..sort();
      final anchorItemId = requestedAnchor.isNotEmpty
          ? requestedAnchor
          : originatingItem?.itemId ?? '';
      final supportingLockedCount = state.items.where((item) {
        return item.itemId != anchorItemId &&
            state.lockedItemIds.contains(item.itemId);
      }).length;
      debugPrint(
        'AHVI_STYLE_THIS_ANCHOR '
        'anchor_item_id=${AhviStyleDiagnostics.maskIdentifier(anchorItemId)} '
        'anchor_present=${originatingItem != null} '
        'initial_locked_count=${initialLockedIds.length} '
        'supporting_locked_count=$supportingLockedCount',
      );
    }
    final failedPredicates = state.failedContractPredicates;
    debugPrint(
      'AHVI_BOARD_CONTRACT_CHECK '
      'board_id=${AhviStyleDiagnostics.maskIdentifier(state.boardId)} '
      'board_id_ok=${state.boardIdOk} '
      'revision=${state.revision} '
      'revision_ok=${state.revisionOk} '
      'source_policy_present=${state.sourcePolicy.isNotEmpty} '
      'source_policy_ok=${state.sourcePolicyOk} '
      'item_count=${state.items.length} '
      'stable_item_ids_ok=${state.stableItemIdsOk} '
      'positions_ok=${state.positionsOk} '
      'request_carried_items_ok=${state.requestCarriedItemsOk} '
      'canonical_item_count=${state.items.length} '
      'items_with_stable_id=${state.items.where((i) => i.hasStableIdentity).length} '
      'items_with_role=${state.items.where((i) => i.role != BoardItemRole.unknown).length} '
      'items_with_required_payload=${state.items.where((i) => i.raw.isNotEmpty && i.source != "unknown").length} '
      'request_carried_source=${state.items.every((i) => i.raw.isNotEmpty) ? "canonical_reconstruction" : "none"} '
      'can_lock=${state.canLock} '
      'can_shuffle=${state.canShuffle} '
      'failed_predicates=${failedPredicates.isEmpty ? "none" : failedPredicates.join(",")}',
    );
    final modeAllowsMutation = _interactionMode.supportsMutation;
    // Build the controller for LOCAL lock/unlock whenever the mode allows
    // mutation and the board can be locked. Shuffle (a backend mutation) is
    // gated separately by state.canShuffle inside the mutation bar, so a
    // synthetic Style This board still renders lock UI without a broken
    // shuffle button.
    final controlsEnabled = modeAllowsMutation && state.canLock;
    debugPrint(
      'AHVI_BOARD_INTERACTION_MODE '
      'board_id=${AhviStyleDiagnostics.maskIdentifier(state.boardId)} '
      'mode=${_interactionMode.wireName} '
      'lock=$controlsEnabled '
      'shuffle=${controlsEnabled && state.canShuffle} '
      'undo=$controlsEnabled '
      'save=true share=true '
      'like=${_interactionMode == BoardInteractionMode.recommendation} '
      'dislike=${_interactionMode == BoardInteractionMode.recommendation}',
    );
    if (!controlsEnabled) {
      _controller = null;
      return;
    }
    _controller = StyleBoardController(
      initialState: state,
      shuffleCall: widget.shuffleCall ?? _shuffleThroughApi,
    )..addListener(_handleControllerChange);
  }

  Future<StyleBoardShuffleResult> _shuffleThroughApi(
    StyleBoardState board,
  ) async {
    final backend = Provider.of<BackendService>(context, listen: false);
    final result = await StyleBoardApiService(backend).shuffle(
      board: board,
      occasion: _initialBoard.occasion,
      styleDirection: _initialBoard.styleArchetype,
    );
    return StyleBoardShuffleResult(
      boardId: result.boardId,
      revision: result.revision,
      previousRevision: result.previousRevision,
      lockedItemsPreserved: result.lockedItemsPreserved,
      changedSlots: result.changedSlots,
      scenario: result.scenario,
      sourcePolicy: result.sourcePolicy,
      items: result.items
          .map((item) {
            final resolved = resolveStyleBoardItemImage(
              item.toContractJson(),
              _wardrobeById,
              surface: 'style_board_live',
            );
            return StyleBoardItem.fromJson(resolved);
          })
          .toList(growable: false),
    );
  }

  void _refreshBoardImages(
    ({OutfitBoardModel model, StyleBoardData board}) parsed,
  ) {
    final controller = _controller;
    if (controller?.state.isShuffling == true) {
      _pendingImageBoard = parsed.board;
      return;
    }
    final current = controller?.state.items ?? _initialBoard.items;
    final refreshedById = {
      for (final item in parsed.board.items) item.itemId: item,
    };
    final refreshed = current
        .map((item) {
          final image = refreshedById[item.itemId];
          if (image == null) return item;
          return StyleBoardItem(
            id: item.id,
            slot: item.slot,
            boardRole: item.boardRole,
            source: item.source,
            accessoryType: item.accessoryType,
            name: item.name,
            imageUrl: image.imageUrl,
            maskedUrl: image.maskedUrl,
            boardImageUrl: image.boardImageUrl,
            normalizedUrl: image.normalizedUrl,
            assetCutoutUrl: image.assetCutoutUrl,
            assetMaskedUrl: image.assetMaskedUrl,
            category: item.category,
            subCategory: item.subCategory,
            role: item.role,
            position: item.position,
            isLocked: item.isLocked,
            isRegenerating: item.isRegenerating,
            raw: image.raw,
          );
        })
        .toList(growable: false);
    _model = parsed.model;
    _initialBoard = parsed.board;
    if (controller == null) {
      _initialBoard = StyleBoardData(
        boardId: parsed.board.boardId,
        revision: parsed.board.revision,
        scenario: parsed.board.scenario,
        sourcePolicy: parsed.board.sourcePolicy,
        allowWardrobeFallback: parsed.board.allowWardrobeFallback,
        title: parsed.board.title,
        styleArchetype: parsed.board.styleArchetype,
        boardRole: parsed.board.boardRole,
        occasion: parsed.board.occasion,
        whyItWorks: parsed.board.whyItWorks,
        items: refreshed,
        story: parsed.board.story,
        stylingTip: parsed.board.stylingTip,
      );
      if (mounted) setState(() {});
      return;
    }
    controller.refreshItemImages(refreshed);
  }

  Future<void> _shuffleBoard() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.state;
    debugPrint(
      'AHVI_BOARD_SHUFFLE board_id=${state.boardId} '
      'revision=${state.revision} source_policy=${state.sourcePolicy} '
      'locked_count=${state.lockedItemIds.length}',
    );
    final code = await controller.shuffle();
    if (!mounted || code == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(_shuffleFailureMessage(code)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleControllerChange() {
    if (!mounted) return;
    setState(() {});
    widget.onBoardStateChanged?.call(_currentDirection);
    if (_controller?.state.isShuffling == false && _pendingImageBoard != null) {
      final pending = _pendingImageBoard!;
      _pendingImageBoard = null;
      _refreshBoardImages((model: _model, board: pending));
    }
    if (_controller?.state.isShuffling == false && _pendingBoard != null) {
      final pending = _pendingBoard!;
      _pendingBoard = null;
      final current = _currentBoard;
      final isNewBoard = pending.boardId != current.boardId;
      final isNewerRevision = pending.revision > current.revision;
      if (!isNewBoard && !isNewerRevision) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _replaceBoard((
          model: OutfitBoardModel.fromPayload(
            widget.direction,
            editorialCover: widget.editorialCover,
          ),
          board: pending,
        ));
        setState(() {});
      });
    }
  }

  StyleBoardData get _currentBoard {
    final state = _controller?.state;
    if (state == null) return _initialBoard;
    return StyleBoardData(
      boardId: state.boardId,
      revision: state.revision,
      scenario: state.scenario,
      sourcePolicy: state.sourcePolicy,
      allowWardrobeFallback: state.allowWardrobeFallback,
      title: _initialBoard.title,
      styleArchetype: _initialBoard.styleArchetype,
      boardRole: _initialBoard.boardRole,
      occasion: _initialBoard.occasion,
      whyItWorks: _initialBoard.whyItWorks,
      items: state.items,
      story: _initialBoard.story,
      stylingTip: _initialBoard.stylingTip,
    );
  }

  Map<String, dynamic> get _currentDirection {
    final board = _currentBoard;
    return {
      ...widget.direction,
      'board_id': board.boardId,
      'revision': board.revision,
      'scenario': board.scenario,
      'source_policy': board.sourcePolicy,
      'allow_wardrobe_fallback': board.allowWardrobeFallback,
      'title': board.title,
      'occasion': board.occasion,
      'why_it_works': board.whyItWorks,
      'styling_tip': board.stylingTip,
      'locked_item_ids':
          _controller?.state.lockedItemIds.toList(growable: false) ??
          board.items
              .where((item) => item.isLocked && item.hasStableIdentity)
              .map((item) => item.itemId)
              .toList(growable: false),
      'board_items': board.items
          .map((item) => item.toContractJson())
          .toList(growable: false),
    }..removeWhere((_, value) => value == null);
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChange);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = _currentBoard;
    if (!board.items.any((item) => item.displayImageUrl.trim().isNotEmpty)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final mode = _interactionMode;
    final contextStrip = OutfitContextStrip(model: _model);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return SizedBox(
      key: const ValueKey('active-chat-outfit-board-card'),
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: _shareBoundaryKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: editorialBoardHeaderHeight,
                      child: _PremiumBoardHeader(mode: mode),
                    ),
                    SizedBox(
                      height: editorialBoardContextHeight,
                      child: ClipRect(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onTapBoard == null
                              ? null
                              : () => widget.onTapBoard!(_currentDirection),
                          child: textScale > 1
                              ? SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: contextStrip,
                                )
                              : contextStrip,
                        ),
                      ),
                    ),
                    GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onTapBoard == null
                            ? null
                            : () => widget.onTapBoard!(_currentDirection),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: AhviUnifiedOutfitGrid(
                            items: board.items
                                .map(
                                  (item) => AhviUnifiedOutfitGridItem.fromStyleBoardItem(
                                    item,
                                    isLocked: _controller?.state.lockedItemIds
                                            .contains(item.itemId) ??
                                        item.isLocked,
                                    // Style This uses its own typed,
                                    // normalized-first presentation surface
                                    // (wardrobe_image_resolver.dart) so a
                                    // stale board/cutout asset can never
                                    // outrank the correct normalized image.
                                    // Other modes keep the generic board-safe
                                    // cutout-first surface.
                                    surface: mode == BoardInteractionMode.styleThis
                                        ? 'style_this_unified_grid'
                                        : 'style_board_active_unified_grid',
                                  ),
                                )
                                .toList(growable: false),
                            onToggleLock: mode.supportsMutation
                                ? _controller?.toggleLock
                                : null,
                          ),
                        ),
                    ),
                    OutfitReasoningStrip(
                      key: const ValueKey('active-chat-board-reasoning'),
                      model: _model,
                      mode: mode,
                    ),
                  ],
                ),
              ),
              if (_controller != null)
                BoardMutationBar(
                  controller: _controller!,
                  onShuffle: _shuffleBoard,
                  showUndo: mode.supportsMutation,
                ),
              OutfitActionBar(
                interactionMode: mode,
                direction: _currentDirection,
                editorialCover: widget.editorialCover,
                primaryLabel: _model.title,
                missingName: _model.missingName,
                onSendMessage: widget.onSendMessage,
                shareBoundaryKey: _shareBoundaryKey,
                saveBoardOverride: widget.saveBoardOverride,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumBoardHeader extends StatelessWidget {
  final BoardInteractionMode mode;

  const _PremiumBoardHeader({required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (mode) {
      BoardInteractionMode.recommendation => 'AHVI EDIT',
      BoardInteractionMode.styleThis => 'STYLE THIS',
      BoardInteractionMode.buildOutfit => 'TRY-ON',
    };
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class OutfitCollageGrid extends StatelessWidget {
  final List<OutfitBoardItem> items;

  const OutfitCollageGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (items.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Icon(
            Icons.checkroom_rounded,
            color: colors.primary.withValues(alpha: 0.55),
            size: 42,
          ),
        ),
      );
    }

    // Callers pass image-bearing items only (see OutfitBoardModel.imageItems +
    // the >=3 gate in the carousel), so no placeholder slots are ever drawn.
    final hero = items.first;
    // Cap visible items to 5 total (hero + 4) for a clean flat-lay.
    final support = items.skip(1).take(4).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 330 ? 6.0 : 8.0;
        final bottomHeight = support.length > 2
            ? constraints.maxHeight * 0.30
            : 0.0;
        final topHeight =
            constraints.maxHeight - bottomHeight - (bottomHeight > 0 ? gap : 0);
        final topSupport = support.take(2).toList(growable: false);
        final bottomSupport = support.skip(2).take(3).toList(growable: false);

        return Column(
          children: [
            SizedBox(
              height: topHeight,
              child: Row(
                children: [
                  Expanded(
                    flex: topSupport.isEmpty ? 1 : 3,
                    child: OutfitHeroTile(item: hero),
                  ),
                  if (topSupport.isNotEmpty) ...[
                    SizedBox(width: gap),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < topSupport.length;
                            index++
                          ) ...[
                            Expanded(
                              child: OutfitSupportTile(item: topSupport[index]),
                            ),
                            if (index != topSupport.length - 1)
                              SizedBox(height: gap),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (bottomSupport.isNotEmpty) ...[
              SizedBox(height: gap),
              SizedBox(
                height: bottomHeight,
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < bottomSupport.length;
                      index++
                    ) ...[
                      Expanded(
                        child: OutfitSupportTile(item: bottomSupport[index]),
                      ),
                      if (index != bottomSupport.length - 1)
                        SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class OutfitHeroTile extends StatelessWidget {
  final OutfitBoardItem item;

  const OutfitHeroTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return _OutfitTile(item: item, hero: true);
  }
}

class OutfitSupportTile extends StatelessWidget {
  final OutfitBoardItem item;

  const OutfitSupportTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return _OutfitTile(item: item);
  }
}

class _OutfitTile extends StatelessWidget {
  final OutfitBoardItem item;
  final bool hero;

  const _OutfitTile({required this.item, this.hero = false});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final url = item.imageUrl;
    final image = url == null
        ? _placeholder(t)
        : Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(t),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _placeholder(t),
          );

    // Flat-lay treatment: garment floats on a soft off-white card with no dark
    // gradient overlay and no label printed over the image. Item names live in
    // the tap-detail sheet instead. Hero gets more breathing room.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFFF4F2EC),
        child: Padding(padding: EdgeInsets.all(hero ? 12 : 8), child: image),
      ),
    );
  }

  Widget _placeholder(AppThemeTokens t) {
    return Center(
      child: Icon(
        collageIconForPiece(item.name),
        color: t.accent.primary.withValues(alpha: 0.5),
        size: hero ? 44 : 28,
      ),
    );
  }
}

class OutfitContextStrip extends StatelessWidget {
  final OutfitBoardModel model;

  const OutfitContextStrip({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              editorialSentenceSafeCopy(model.title, maxCharacters: 88),
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            if (model.chips.isNotEmpty || model.wardrobeMatchPct != null) ...[
              const SizedBox(height: 5),
              SizedBox(
                height: 20,
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (model.wardrobeMatchPct != null)
                        _WardrobeMatchPill(pct: model.wardrobeMatchPct!),
                      ...model.chips
                          .take(3)
                          .map(
                            (chip) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _ContextChip(label: chip),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OutfitReasoningStrip extends StatelessWidget {
  final OutfitBoardModel model;
  final BoardInteractionMode mode;

  const OutfitReasoningStrip({
    super.key,
    required this.model,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (model.intelligenceText.isEmpty && model.stylingTip.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final why = _naturalCopy(model.intelligenceText);
    final tip = _naturalCopy(model.stylingTip);
    debugPrint(
      'AHVI_ACTIVE_EDITORIAL_COPY '
      'source_file=ahvi_outfit_board_card.dart widget=OutfitReasoningStrip '
      'requested_mode=${mode.wireName} interaction_mode=${mode.wireName} '
      'canonical_renderer_reached=true board_count=1 '
      'selected_surface=editorial_reasoning_strip '
      'why_chars=${why.length} tip_chars=${tip.length}',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (why.isNotEmpty) ...[
            Text(
              'WHY IT WORKS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              why,
              key: const ValueKey('style-why-it-works'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
          if (tip.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'STYLING TIP',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tip,
              key: const ValueKey('style-styling-tip'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                height: 1.22,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _naturalCopy(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _ContextChip extends StatelessWidget {
  final String label;

  const _ContextChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant, width: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Compact "NN% wardrobe match" pill — only shown for wardrobe boards
/// (catalog / visual-inspiration looks carry no match and hide it).
class _WardrobeMatchPill extends StatelessWidget {
  final int pct;

  const _WardrobeMatchPill({required this.pct});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.35),
          width: 0.7,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checkroom_rounded, size: 11, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            '$pct% wardrobe match',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class BoardMutationBar extends StatelessWidget {
  final StyleBoardController controller;
  final Future<void> Function() onShuffle;
  final bool showUndo;

  const BoardMutationBar({
    super.key,
    required this.controller,
    required this.onShuffle,
    this.showUndo = false,
  });

  Future<void> _shuffle() async {
    await onShuffle();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = controller.state;
    final locked = state.lockedItemIds.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            // Shuffle is a backend mutation — only surface it for a real
            // persisted, shuffleable board. Synthetic Style This boards keep
            // lock/unlock but never a broken shuffle control.
            if (state.canShuffle)
              Expanded(
                child: _BoardAction(
                  icon: state.isShuffling
                      ? Icons.hourglass_top_rounded
                      : Icons.shuffle_rounded,
                  label: state.isShuffling
                      ? ahviProcessingMessage(AhviProcessingContext.shuffle)
                      : state.allItemsLocked
                      ? 'Unlock an item to shuffle'
                      : 'Shuffle unlocked pieces',
                  enabled: !state.isShuffling && !state.allItemsLocked,
                  onTap: _shuffle,
                ),
              ),
            if (locked > 0)
              Expanded(
                child: _BoardAction(
                  icon: Icons.lock_open_rounded,
                  label: 'Unlock all',
                  enabled: !state.isShuffling,
                  onTap: controller.unlockAll,
                ),
              ),
            if (showUndo)
              Expanded(
                child: _BoardAction(
                  icon: Icons.undo_rounded,
                  label: 'Undo shuffle',
                  enabled: controller.canUndo && !state.isShuffling,
                  onTap: controller.undo,
                ),
              ),
            Expanded(
              child: Center(
                child: Text(
                  '$locked of ${state.items.length} items locked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
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

class OutfitActionBar extends StatefulWidget {
  final BoardInteractionMode interactionMode;
  final Map<String, dynamic> direction;
  final Map<String, dynamic> editorialCover;
  final String primaryLabel;
  final String missingName;
  final OutfitBoardMessageSender? onSendMessage;
  final GlobalKey? shareBoundaryKey;
  // Test seams (production uses the real Appwrite + share_plus paths).
  final BoardSaveFn? saveBoardOverride;
  final Future<Uint8List?> Function()? captureOverride;
  final Future<void> Function(Uint8List bytes, String caption)?
  shareImageOverride;
  final Future<void> Function(String text)? shareTextOverride;

  const OutfitActionBar({
    super.key,
    required this.direction,
    required this.editorialCover,
    required this.primaryLabel,
    required this.missingName,
    this.interactionMode = BoardInteractionMode.recommendation,
    this.onSendMessage,
    this.shareBoundaryKey,
    this.saveBoardOverride,
    this.captureOverride,
    this.shareImageOverride,
    this.shareTextOverride,
  });

  @override
  State<OutfitActionBar> createState() => _OutfitActionBarState();
}

class _OutfitActionBarState extends State<OutfitActionBar> {
  bool _saved = false;
  bool _saving = false;
  bool _liked = false;
  bool _disliked = false;
  BackendService? _backend;
  ScaffoldMessengerState? _messenger;

  String _boardIdentity(OutfitActionBar value) {
    final boardId = _text(
      value.direction['board_id'] ?? value.direction['boardId'],
    );
    final revision = value.direction['revision']?.toString() ?? '0';
    final rawTitle = _text(
      value.direction['title'] ?? value.direction['direction_name'],
    );
    return '$boardId|$revision|$rawTitle|${value.primaryLabel}';
  }

  @override
  void didUpdateWidget(covariant OutfitActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_boardIdentity(oldWidget) == _boardIdentity(widget)) return;
    _saved = false;
    _saving = false;
    _liked = false;
    _disliked = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    try {
      _backend = Provider.of<BackendService>(context, listen: false);
    } catch (_) {
      _backend = null;
    }
  }

  void _sendFeedback(String action) {
    // Fire-and-forget; also the adaptive stylist-brain training signal.
    // Never let a missing provider or feedback error break Save/Share.
    try {
      _backend?.sendBoardFeedback(action: action, board: widget.direction);
    } catch (_) {}
  }

  void _toggleLike() {
    setState(() {
      _liked = !_liked;
      if (_liked) _disliked = false;
    });
    if (_liked) _sendFeedback('like');
  }

  void _toggleDislike() {
    setState(() {
      _disliked = !_disliked;
      if (_disliked) _liked = false;
    });
    if (_disliked) _sendFeedback('dislike');
  }

  String _shareCaption() {
    final title = widget.primaryLabel.trim().isEmpty
        ? _occasion
        : widget.primaryLabel.trim();
    return 'My "$title" look, styled on AHVI.';
  }

  List<StyleBoardItem> _shareBoardItems() {
    final out = <StyleBoardItem>[];
    for (final item in _saveItems()) {
      final parsed = StyleBoardItem.fromJson(item);
      if (parsed.displayImageUrl.isNotEmpty) out.add(parsed);
    }
    return out;
  }

  /// Build a dedicated opaque ShareableOutfitBoard offscreen and capture it, so
  /// the exported PNG is never transparent and never bakes in the paragraph
  /// copy. Returns null when it cannot mount (caller falls back).
  Future<Uint8List?> _captureShareComposition() async {
    if (!mounted) return null;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    final items = _shareBoardItems();
    if (items.isEmpty) return null;
    final key = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            color: Colors.transparent,
            child: ShareableOutfitBoard(
              boundaryKey: key,
              title: widget.primaryLabel.trim().isEmpty
                  ? _occasion
                  : widget.primaryLabel.trim(),
              occasion: _occasion,
              items: items,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Let it lay out + paint. The garment images are already in Flutter's
      // image cache from the visible card, so they resolve within a few frames.
      for (var i = 0; i < 5; i++) {
        await WidgetsBinding.instance.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await WidgetsBinding.instance.endOfFrame;
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final image = await ro.toImage(pixelRatio: 3.0);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }

  Future<Uint8List?> _captureBoardPng() async {
    final composed = await _captureShareComposition();
    if (composed != null && composed.isNotEmpty) return composed;
    // Fallback: the in-app boundary (kept so Share never does nothing).
    final ctx = widget.shareBoundaryKey?.currentContext;
    final renderObject = ctx?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _shareImageDefault(Uint8List bytes, String caption) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/ahvi_board_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: caption,
        subject: caption,
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('native_share_unavailable');
    }
  }

  Future<void> _share() async {
    debugPrint('AHVI_BOARD_ACTION_TAP action=share surface=outfit_board');
    debugPrint('AHVI_BOARD_SHARE_TAP');
    final caption = _shareCaption();
    try {
      debugPrint('AHVI_BOARD_SHARE_CAPTURE_START');
      final bytes = await (widget.captureOverride ?? _captureBoardPng)();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('capture_returned_no_bytes');
      }
      debugPrint('AHVI_BOARD_SHARE_CAPTURE_SUCCESS bytes=${bytes.length}');
      final shareImage = widget.shareImageOverride ?? _shareImageDefault;
      await shareImage(bytes, caption);
      debugPrint('AHVI_BOARD_SHARE_SHEET_OPENED');
      _sendFeedback('shared');
    } catch (e) {
      // Image path failed -> never do nothing: fall back to text sharing.
      debugPrint('AHVI_BOARD_SHARE_FAILED error=$e');
      try {
        final shareText =
            widget.shareTextOverride ??
            (text) async {
              final result = await SharePlus.instance.share(
                ShareParams(text: text, subject: text),
              );
              if (result.status == ShareResultStatus.unavailable) {
                throw StateError('native_share_unavailable');
              }
            };
        await shareText(caption);
        debugPrint('AHVI_BOARD_SHARE_TEXT_FALLBACK');
        _sendFeedback('shared');
      } catch (e2) {
        debugPrint('AHVI_BOARD_SHARE_FAILED error=$e2');
        if (mounted) {
          _messenger?.showSnackBar(
            const SnackBar(content: Text('Could not open the share sheet.')),
          );
        }
      }
    }
  }

  String get _occasion {
    final cover = _text(widget.editorialCover['occasion_label']);
    if (cover.isNotEmpty) return cover;
    final direct = _text(widget.direction['occasion']);
    return direct.isNotEmpty ? direct : 'Curated Look';
  }

  String get _id => SavedBoardsStore.idFor(
    occasion: _occasion,
    directionName: widget.primaryLabel,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final saved = await SavedBoardsStore.isSaved(_id);
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  List<Map<String, dynamic>> _saveItems() {
    final items = _maps(
      widget.direction['board_items'] ??
          widget.direction['boardItems'] ??
          widget.direction['items'],
    );
    return items;
  }

  List<String> _saveItemIds() {
    final ids = <String>[];
    for (final item in _saveItems()) {
      final id = _text(
        item['item_id'] ??
            item['id'] ??
            item[r'$id'] ??
            item['itemId'] ??
            item['image_id'] ??
            item['asset_id'] ??
            item['wardrobe_item_id'] ??
            item['wardrobeItemId'],
      );
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  String _saveImageUrl() {
    final candidates = <ResolvedWardrobeImage>[
      resolveWardrobeImage(
        widget.direction,
        surface: 'style_board_cover',
        itemId: _id,
      ),
      resolveWardrobeImage(
        widget.editorialCover,
        surface: 'style_board_cover',
        itemId: _id,
      ),
    ];
    for (final item in _saveItems()) {
      candidates.add(
        resolveWardrobeImage(
          item,
          surface: 'style_board_cover',
          itemId: _text(item['item_id'] ?? item['id'] ?? item[r'$id']),
        ),
      );
    }
    candidates.sort((a, b) => a.tier.compareTo(b.tier));
    for (final candidate in candidates) {
      if (isValidSavedBoardHttpUrl(candidate.url)) return candidate.url!;
    }
    return '';
  }

  String _saveExplanation() {
    final why = _text(
      widget.direction['why'] ??
          widget.direction['why_it_works'] ??
          widget.direction['explanation'] ??
          widget.direction['style_tip'] ??
          widget.direction['style_tip'],
    );
    return why.isEmpty ? 'AHVI styled look' : why;
  }

  Future<String?> _defaultSaveBoard({
    required String occasion,
    required String outfitDescription,
    required String imageUrl,
    required String title,
    required List<String> itemIds,
    required List<Map<String, dynamic>> items,
    required bool isFavourite,
  }) async {
    final content = buildSavedBoardContent(
      board: widget.direction,
      items: items,
      selection: SavedBoardSelection(
        bucket: occasion,
        isFavourite: isFavourite,
      ),
      title: title,
      originalOccasion: _occasion,
    );
    final doc = await AppwriteService().saveBoardToCollection(
      imageUrl: imageUrl,
      content: content,
    );
    return doc?.$id;
  }

  Future<SavedBoardSelection?> _showSaveSheet() {
    var bucket = inferSavedBoardBucket({
      ...widget.direction,
      'occasion': _occasion,
    });
    var isFavourite = false;
    const categories = <(String, String, IconData)>[
      ('party_looks', 'Party Looks', Icons.celebration_rounded),
      ('office_fits', 'Office Fits', Icons.work_outline_rounded),
      ('vacation', 'Vacation', Icons.flight_takeoff_rounded),
      ('occasion', 'Occasion', Icons.diamond_outlined),
      ('everything_else', 'Everything Else', Icons.auto_awesome_rounded),
    ];
    return showModalBottomSheet<SavedBoardSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.themeTokens;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save this look to',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final category in categories)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(category.$3, color: t.accent.primary),
                      title: Text(
                        category.$2,
                        style: TextStyle(color: t.textPrimary),
                      ),
                      trailing: Icon(
                        bucket == category.$1
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: bucket == category.$1
                            ? t.accent.primary
                            : t.mutedText,
                      ),
                      onTap: () => setSheetState(() => bucket = category.$1),
                    ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Add to Favourites',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    value: isFavourite,
                    onChanged: (value) =>
                        setSheetState(() => isFavourite = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(
                        SavedBoardSelection(
                          bucket: bucket,
                          isFavourite: isFavourite,
                        ),
                      ),
                      child: const Text('Save look'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleSave() async {
    debugPrint('AHVI_BOARD_ACTION_TAP action=save surface=outfit_board');
    debugPrint('AHVI_BOARD_SAVE_TAP');
    // Idempotent: ignore taps while saving or once already saved.
    if (_saving || _saved) return;
    final selection = await _showSaveSheet();
    if (selection == null || !mounted) return;
    final saveIdentity = _boardIdentity(widget);
    setState(() => _saving = true);
    debugPrint('AHVI_BOARD_SAVE_START');
    try {
      final items = _saveItems();
      final saver = widget.saveBoardOverride ?? _defaultSaveBoard;
      final docId = await saver(
        occasion: selection.bucket,
        outfitDescription: _saveExplanation(),
        imageUrl: _saveImageUrl(),
        title: widget.primaryLabel,
        itemIds: _saveItemIds(),
        items: items,
        isFavourite: selection.isFavourite,
      );
      if (!mounted || saveIdentity != _boardIdentity(widget)) return;
      if (docId == null || docId.isEmpty) {
        throw Exception('appwrite_returned_null_document');
      }
      final boardId = _text(
        widget.direction['board_id'] ?? widget.direction['boardId'],
      );
      debugPrint(
        'AHVI_BOARD_SAVE_SUCCESS document_id=$docId '
        'board_id=${boardId.isEmpty ? _id : boardId} '
        'item_count=${items.length} '
        'bucket=${selection.bucket} '
        'is_favourite=${selection.isFavourite}',
      );
      _sendFeedback('saved');
      // Best-effort local echo so the heart persists on reload. Appwrite is the
      // authoritative store; this is UI state only, not a replacement.
      unawaited(
        SavedBoardsStore.saveBoard(
          occasion: _occasion,
          directionName: widget.primaryLabel,
          direction: widget.direction,
          editorialCover: widget.editorialCover,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saved = true; // heart only flips AFTER persistence succeeds
        _saving = false;
      });
      _messenger?.showSnackBar(
        const SnackBar(content: Text('Saved to your boards')),
      );
    } on SavedBoardPersistenceException catch (e) {
      debugPrint('AHVI_BOARD_SAVE_FAILED reason=${e.reason}');
      if (!mounted) return;
      setState(() => _saving = false);
      _messenger?.showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (_) {
      debugPrint('AHVI_BOARD_SAVE_FAILED reason=save_write_failed');
      if (!mounted) return;
      setState(() => _saving = false); // stays unsaved on failure
      _messenger?.showSnackBar(
        const SnackBar(
          content: Text('Could not save board. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = <Widget>[
      _BoardAction(
        icon: _saved
            ? Icons.check_circle_rounded
            : Icons.favorite_border_rounded,
        label: _saved ? 'Saved' : 'Save',
        enabled: !_saving,
        onTap: _toggleSave,
      ),
      if (widget.interactionMode == BoardInteractionMode.recommendation) ...[
        _BoardAction(
          icon: _liked
              ? Icons.thumb_up_alt_rounded
              : Icons.thumb_up_off_alt_rounded,
          label: 'Like',
          enabled: true,
          onTap: _toggleLike,
        ),
        _BoardAction(
          icon: _disliked
              ? Icons.thumb_down_alt_rounded
              : Icons.thumb_down_off_alt_rounded,
          label: 'Dislike',
          enabled: true,
          onTap: _toggleDislike,
        ),
      ],
      _BoardAction(
        icon: Icons.ios_share_rounded,
        label: 'Share',
        enabled: true,
        onTap: _share,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [for (final action in actions) Expanded(child: action)],
        ),
      ),
    );
  }
}

class _BoardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _BoardAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = enabled
        ? colors.onSurface
        : colors.onSurfaceVariant.withValues(alpha: 0.45);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum OutfitRole { hero, bottom, footwear, outerwear, bag, accessory, other }

class OutfitBoardItem {
  final String id;
  final String name;
  final String? imageUrl;
  final OutfitRole role;

  const OutfitBoardItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.role,
  });
}

class OutfitBoardModel {
  final String title;
  final List<String> chips;
  final List<OutfitBoardItem> items;
  final String missingName;
  final String intelligenceText;
  final String stylingTip;
  final int? wardrobeMatchPct;

  /// Items that carry a real image. Placeholders are never shown on the
  /// flat-lay board — the board only renders when there are enough of these.
  List<OutfitBoardItem> get imageItems =>
      items.where((item) => item.imageUrl != null).toList(growable: false);

  const OutfitBoardModel({
    required this.title,
    required this.chips,
    required this.items,
    required this.missingName,
    required this.intelligenceText,
    required this.stylingTip,
    this.wardrobeMatchPct,
  });

  factory OutfitBoardModel.fromPayload(
    Map<String, dynamic> direction, {
    required Map<String, dynamic> editorialCover,
  }) {
    final rawStrategy = direction['style_strategy'];
    final strategy = rawStrategy is Map
        ? Map<String, dynamic>.from(rawStrategy)
        : const <String, dynamic>{};
    final strategyTitle = _text(
      strategy['direction_title'] ??
          strategy['directionTitle'] ??
          strategy['direction'],
    );
    final directionName = _text(
      direction['direction_name'] ??
          direction['directionName'] ??
          direction['style_direction'],
    );
    final archetype = _selectedArchetypeTitle(direction);
    final wardrobeMatchRaw =
        direction['wardrobe_match_pct'] ?? direction['wardrobeMatchPct'];
    final int? wardrobeMatchPct = wardrobeMatchRaw is int
        ? wardrobeMatchRaw
        : (wardrobeMatchRaw is num
              ? wardrobeMatchRaw.round()
              : (wardrobeMatchRaw is String
                    ? int.tryParse(wardrobeMatchRaw)
                    : null));
    final title = resolveOutfitBoardTitle(direction);
    final occasion = _text(
      direction['occasion'] ?? editorialCover['occasion_label'],
    );
    final dressCode = _text(
      direction['dress_code'] ??
          direction['dressCode'] ??
          strategy['dress_code'],
    );
    final weather = _contextText(
      direction['weather_context'] ??
          direction['weatherContext'] ??
          direction['weather'] ??
          strategy['weather_context'],
    );
    final contextLabel = _text(
      direction['context_used'] ??
          direction['contextUsed'] ??
          direction['context_hint'],
    );
    final adjectives = _strings(direction['adjectives']);
    final adjective = adjectives.isEmpty ? '' : adjectives.first;
    final candidates = <String>[
      occasion,
      archetype,
      dressCode,
      weather,
      contextLabel,
      strategyTitle,
      directionName,
      adjective,
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    final hasMeaningfulContext = candidates.any(
      (value) =>
          !_isGenericContext(value) &&
          value.trim().toLowerCase() != title.trim().toLowerCase(),
    );
    final seenChips = <String>{};
    final chips = candidates
        .where((value) {
          final normalized = value.trim().toLowerCase();
          if (normalized == title.trim().toLowerCase()) return false;
          if (hasMeaningfulContext && _isGenericContext(value)) return false;
          return seenChips.add(normalized);
        })
        .take(3)
        .toList(growable: false);
    String normalizeDisplayCopy(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[.!?]+$'), '');
    }

    final intelligenceText = _completeDisplayThought(
      _text(
        direction['short_note'] ??
            direction['shortNote'] ??
            direction['why_it_works'] ??
            direction['whyItWorks'] ??
            direction['why_this_works'] ??
            direction['explanation'] ??
            direction['reason'] ??
            direction['description'] ??
            strategy['why_it_works'] ??
            strategy['reason'] ??
            editorialCover['summary'],
      ),
    );

    final stylingTipCandidate = _completeDisplayThought(
      _text(
        direction['styling_tip'] ??
            direction['style_tip'] ??
            direction['style_note'] ??
            direction['styleNote'] ??
            direction['styling_note'] ??
            strategy['styling_tip'],
      ),
    );

    final stylingTip =
        normalizeDisplayCopy(stylingTipCandidate) ==
            normalizeDisplayCopy(intelligenceText)
        ? ''
        : stylingTipCandidate;

    // Authoritative path: when the backend sends itemized board_items, render
    // EXACTLY those. They already carry correct roles, images, completeness
    // (top+bottom+footwear) and dedup from the backend. Re-mixing hero_piece /
    // complete_the_look / pieces (the legacy path below) silently dropped real
    // slots — footwear, then bottom — inconsistently across prompts/users.
    // Fall back to legacy aggregation only when board_items is absent.
    final backendItems = _maps(
      direction['board_items'] ?? direction['boardItems'],
    );
    if (backendItems.isNotEmpty) {
      final built = <OutfitBoardItem>[];
      final seenKeys = <String>{};
      for (final item in backendItems) {
        final name = _text(item['name'] ?? item['title'] ?? item['label']);
        final itemId = _text(
          item['item_id'] ??
              item['id'] ??
              item[r'$id'] ??
              item['itemId'] ??
              item['image_id'] ??
              item['asset_id'] ??
              item['wardrobe_item_id'] ??
              item['wardrobeItemId'],
        );
        final url = _transparentUrlFor(
          item,
          itemId: itemId,
          itemName: name,
          role: _text(item['role'] ?? item['slot']),
        );
        if (name.isEmpty) continue;
        final key = '${name.toLowerCase()}::${url ?? "no-img"}';
        if (!seenKeys.add(key)) continue;
        built.add(
          OutfitBoardItem(
            id: _text(
              item['item_id'] ??
                  item['id'] ??
                  item[r'$id'] ??
                  item['itemId'] ??
                  item['image_id'] ??
                  item['asset_id'] ??
                  item['wardrobeItemId'] ??
                  item['wardrobe_item_id'],
              fallback: key,
            ),
            name: name,
            imageUrl: url,
            role: _roleFor(item, name),
          ),
        );
      }
      if (built.isNotEmpty) {
        final rawMissingB = direction['missing_piece'];
        final missingB = rawMissingB is Map
            ? Map<String, dynamic>.from(rawMissingB)
            : const <String, dynamic>{};
        return OutfitBoardModel(
          title: title,
          chips: chips,
          items: built,
          missingName: isFashionItem(missingB) ? _text(missingB['name']) : '',
          intelligenceText: intelligenceText,
          stylingTip: stylingTip,
          wardrobeMatchPct: wardrobeMatchPct,
        );
      }
    }

    final itemNames = _strings(direction['items'] ?? direction['pieces']);
    final heroName = _text(
      direction['hero_piece'] ?? direction['heroPiece'],
      fallback: itemNames.isEmpty ? 'Hero piece' : itemNames.first,
    );
    final heroUrl = _transparentUrlFor(
      direction,
      itemName: heroName,
      role: 'hero',
    );
    final items = <OutfitBoardItem>[
      OutfitBoardItem(
        id: _text(direction['asset_id'], fallback: 'hero::$heroName::$heroUrl'),
        name: heroName,
        imageUrl: heroUrl,
        role: OutfitRole.hero,
      ),
    ];

    final complete = filterFashionItems(
      _maps(direction['complete_the_look'] ?? direction['completeTheLook']),
    );
    for (final item in complete) {
      final name = _text(item['name'] ?? item['title'] ?? item['label']);
      if (name.isEmpty) continue;
      final ctlUrl = _transparentUrlFor(
        item,
        itemName: name,
        role: 'complete_the_look',
      );
      items.add(
        OutfitBoardItem(
          id: _text(item['asset_id'] ?? item['id'], fallback: '$name::$ctlUrl'),
          name: name,
          imageUrl: ctlUrl,
          role: _roleFor(item, name),
        ),
      );
    }

    // Itemized board data — backend may send pieces under several keys. These
    // carry real images and are what make the 85 board viable (vs one hero).
    final itemized = <Map<String, dynamic>>[
      ..._maps(direction['board_items'] ?? direction['boardItems']),
      ..._maps(direction['items'] ?? direction['pieces']),
      ..._maps(direction['accessories']),
    ];
    for (final item in itemized) {
      final name = _text(item['name'] ?? item['title'] ?? item['label']);
      if (name.isEmpty) continue;
      final url = _transparentUrlFor(
        item,
        itemId: _text(item['asset_id'] ?? item['id']),
        itemName: name,
        role: _text(item['role'] ?? item['slot']),
      );
      items.add(
        OutfitBoardItem(
          id: _text(
            item['asset_id'] ??
                item['id'] ??
                item['wardrobeItemId'] ??
                item['wardrobe_item_id'],
            fallback: '$name::$url',
          ),
          name: name,
          imageUrl: url,
          role: _roleFor(item, name),
        ),
      );
    }

    for (final name in itemNames) {
      if (name.toLowerCase() == heroName.toLowerCase()) continue;
      items.add(
        OutfitBoardItem(
          id: 'piece::$name',
          name: name,
          imageUrl: null,
          role: _roleFor(const {}, name),
        ),
      );
    }

    final seen = <String>{};
    final unique = items.where((item) {
      final key = item.id.isNotEmpty
          ? item.id.toLowerCase()
          : '${item.name.toLowerCase()}::${item.imageUrl ?? ''}';
      return seen.add(key);
    }).toList();
    final hero = unique.first;
    final support = unique.skip(1).toList()
      ..sort((a, b) => _roleRank(a.role).compareTo(_roleRank(b.role)));

    final rawMissing = direction['missing_piece'];
    final missing = rawMissing is Map
        ? Map<String, dynamic>.from(rawMissing)
        : const <String, dynamic>{};
    final missingName = isFashionItem(missing) ? _text(missing['name']) : '';

    return OutfitBoardModel(
      title: title,
      chips: chips,
      items: [hero, ...support.take(5)],
      missingName: missingName,
      intelligenceText: intelligenceText,
      stylingTip: stylingTip,
      wardrobeMatchPct: wardrobeMatchPct,
    );
  }
}

/// Number of image-bearing items a direction would put on the flat-lay board.
/// The carousel uses this to decide between the flat-lay board (>=3 real
/// images) and the legacy fallback card (fewer) — never a board of blanks.
int outfitBoardImageCount(
  Map<String, dynamic> direction, {
  Map<String, dynamic> editorialCover = const {},
}) {
  return OutfitBoardModel.fromPayload(
    direction,
    editorialCover: editorialCover,
  ).imageItems.length;
}

/// The 85 flat-lay board only renders when it can read as a real outfit:
///   classic  = top + bottom + footwear
///   dress    = dress + footwear
///   fallback = >=3 real-image pieces with known roles
/// Text-only placeholders (no image) never count.
bool outfitBoardHasRoles(
  Map<String, dynamic> direction, {
  Map<String, dynamic> editorialCover = const {},
}) {
  final model = OutfitBoardModel.fromPayload(
    direction,
    editorialCover: editorialCover,
  );
  final slots = model.items.map((item) => _mapItemRole(item.role)).toList();
  final hasTop = slots.contains(BoardItemRole.top);
  final hasBottom = slots.contains(BoardItemRole.bottom);
  final hasFootwear = slots.contains(BoardItemRole.footwear);
  final hasDress = slots.contains(BoardItemRole.dress);
  final classicViable = hasTop && hasBottom && hasFootwear;
  final dressViable = hasDress && hasFootwear;
  final knownRoleImages = slots
      .where((slot) => slot != BoardItemRole.unknown)
      .length;
  return classicViable || dressViable || knownRoleImages >= 3;
}

bool outfitBoardViable(
  Map<String, dynamic> direction, {
  Map<String, dynamic> editorialCover = const {},
}) {
  final model = OutfitBoardModel.fromPayload(
    direction,
    editorialCover: editorialCover,
  );
  final slots = model.imageItems
      .map((item) => _mapItemRole(item.role))
      .toList();
  final hasTop = slots.contains(BoardItemRole.top);
  final hasBottom = slots.contains(BoardItemRole.bottom);
  final hasFootwear = slots.contains(BoardItemRole.footwear);
  final hasDress = slots.contains(BoardItemRole.dress);
  final classicViable = hasTop && hasBottom && hasFootwear;
  final dressViable = hasDress && hasFootwear;
  final knownRoleImages = slots
      .where((slot) => slot != BoardItemRole.unknown)
      .length;
  return classicViable || dressViable || knownRoleImages >= 3;
}

StyleBoardData _toStyleBoardData(
  OutfitBoardModel model,
  Map<String, dynamic> direction, {
  Map<String, Map<String, dynamic>> wardrobeById = const {},
}) {
  final items = <StyleBoardItem>[];
  final seenIds = <String>{};
  final rawItems = <Map<String, dynamic>>[
    ..._maps(direction['board_items'] ?? direction['boardItems']),
    ..._maps(direction['items'] ?? direction['pieces']),
    ..._maps(direction['composition_items']),
  ];
  for (final item in model.items) {
    final image = (item.imageUrl ?? '').trim();
    var role = _mapItemRole(item.role);
    if (role == BoardItemRole.top &&
        RegExp(
          r'\b(dress|gown|saree|sari|lehenga|jumpsuit)\b',
          caseSensitive: false,
        ).hasMatch(item.name.toLowerCase())) {
      role = BoardItemRole.dress;
    }
    final raw = rawItems
        .where(
          (candidate) =>
              _text(
                candidate['item_id'] ??
                    candidate['id'] ??
                    candidate[r'$id'] ??
                    candidate['itemId'] ??
                    candidate['image_id'] ??
                    candidate['asset_id'] ??
                    candidate['wardrobe_item_id'] ??
                    candidate['wardrobeItemId'],
              ) ==
              item.id,
        )
        .firstOrNull;
    final canonical = raw == null ? null : StyleBoardItem.fromJson(raw);
    // Request-carried payload: the persistence-free Shuffle endpoint needs each
    // current item serialisable. When the raw board_items lookup misses (or the
    // item carries no per-item source), reconstruct it from the canonical
    // parsed item. A wardrobe-only board's items ARE wardrobe items, so the
    // board-level source_policy is the honest per-item source fallback. Never
    // fabricates IDs: an item without a stable id keeps raw={} and stays
    // ineligible via requestCarriedItemsOk.
    final boardPolicy = _text(
      direction['source_policy'] ?? direction['sourcePolicy'],
    ).trim().toLowerCase();
    var source = canonical?.source ?? 'unknown';
    if (source == 'unknown' &&
        {'wardrobe', 'style_asset'}.contains(boardPolicy)) {
      source = boardPolicy;
    }
    final hasStableId = item.id.trim().isNotEmpty;
    final carriedRaw = Map<String, dynamic>.from(
      raw ??
          (hasStableId
              ? <String, dynamic>{
                  'item_id': item.id,
                  'name': item.name,
                  'slot': role.name,
                  'role': role.name,
                  'category': item.role.name,
                  'image_url': image,
                  'source': source,
                }
              : const <String, dynamic>{}),
    );
    if (source != 'unknown' &&
        _text(
          carriedRaw['source'] ??
              carriedRaw['item_source'] ??
              carriedRaw['itemSource'],
        ).isEmpty) {
      carriedRaw['source'] = source;
    }
    final resolved = resolveWardrobeImage(
      carriedRaw,
      normalizedUrl: canonical?.normalizedUrl,
      maskedUrl: canonical?.maskedUrl,
      surface: 'style_board_live',
      itemId: item.id,
      wardrobeRecord: wardrobeById[item.id],
    );
    final selectedImage = resolved.url ?? image;
    if (selectedImage.isEmpty) continue;
    if (item.id.isNotEmpty && !seenIds.add(item.id)) continue;
    final originalImage = _text(
      carriedRaw['image_url'] ?? carriedRaw['imageUrl'],
    );
    final resolvedRaw = Map<String, dynamic>.from(carriedRaw)
      ..addAll({
        if (originalImage.isNotEmpty && originalImage != selectedImage)
          'original_image_url': originalImage,
        if (resolved.url != null && resolved.field != 'none')
          resolved.field: resolved.url,
      })
      ..['image_url'] = selectedImage
      ..['selected_field'] = resolved.field
      ..['source_kind'] = resolved.sourceKind
      ..['expected_transparent'] = resolved.expectedTransparent
      ..['_image_should_frame'] = resolved.shouldFrame
      ..['_image_source_kind'] = resolved.sourceKind
      ..['_image_expected_transparent'] = resolved.expectedTransparent;
    items.add(
      StyleBoardItem(
        id: item.id,
        slot: canonical?.slot ?? role.name,
        boardRole: canonical?.boardRole ?? '',
        source: source,
        accessoryType: canonical?.accessoryType ?? '',
        name: item.name,
        imageUrl: selectedImage,
        maskedUrl: canonical?.maskedUrl ?? '',
        boardImageUrl: canonical?.boardImageUrl ?? image,
        normalizedUrl: canonical?.normalizedUrl ?? '',
        assetCutoutUrl: canonical?.assetCutoutUrl ?? '',
        assetMaskedUrl: canonical?.assetMaskedUrl ?? '',
        category: canonical?.category ?? item.role.name,
        subCategory: canonical?.subCategory ?? '',
        role: role,
        position: canonical?.position,
        isLocked: canonical?.isLocked ?? false,
        raw: resolvedRaw,
      ),
    );
  }
  final rendered = _enforceSlots(items);
  final storyValue = direction['story'];
  final story = BoardStory.fromJson(
    storyValue is Map ? Map<String, dynamic>.from(storyValue) : null,
  );
  final totalInput = model.items.length;
  final totalRendered = rendered.length;
  debugPrint(
    'AHVI_BOARD_RENDER_ASSET_SELECTION '
    'total_input=$totalInput '
    'rendered_items=$totalRendered '
    'skipped_items=${totalInput - totalRendered} '
    'roles_rendered=${rendered.map((e) => e.role.name).join(",")} '
    'roles_skipped=${items.where((e) => !rendered.contains(e)).map((e) => e.role.name).join(",")}',
  );
  return StyleBoardData(
    boardId: _text(direction['board_id'] ?? direction['boardId']),
    revision:
        (direction['revision'] as num?)?.toInt() ??
        int.tryParse(_text(direction['revision'])) ??
        0,
    scenario: _text(direction['scenario']),
    sourcePolicy: _text(
      direction['source_policy'] ?? direction['sourcePolicy'],
    ),
    allowWardrobeFallback:
        direction['allow_wardrobe_fallback'] == true ||
        direction['allowWardrobeFallback'] == true,
    shuffleAvailable:
        direction['shuffle_available'] == true ||
        direction['shuffleAvailable'] == true,
    title: model.title,
    styleArchetype: direction['style_archetype'] ?? direction['styleArchetype'],
    boardRole: direction['board_role'] ?? direction['boardRole'],
    occasion: direction['occasion'],
    whyItWorks:
        direction['why_it_works'] ??
        direction['whyThisWorks'] ??
        direction['why_this_works'] ??
        direction['explanation'] ??
        '',
    items: rendered,
    story: story.isEmpty ? null : story,
  );
}

@visibleForTesting
StyleBoardData styleBoardDataFromOutfitBoardForTesting(
  OutfitBoardModel model,
  Map<String, dynamic> direction, {
  Map<String, Map<String, dynamic>> wardrobeById = const {},
}) => _toStyleBoardData(
  model,
  direction,
  wardrobeById: wardrobeById,
);

/// Per-role slot caps so a board never paints a random collage (e.g. three
/// bottoms). Keeps the first item per role (hero-first order), drops extras.
/// top/bottom/footwear/outerwear/dress max 1, accessory max 2.
List<StyleBoardItem> _enforceSlots(List<StyleBoardItem> items) {
  const caps = <BoardItemRole, int>{
    BoardItemRole.top: 1,
    BoardItemRole.bottom: 1,
    BoardItemRole.footwear: 1,
    BoardItemRole.outerwear: 1,
    BoardItemRole.dress: 1,
    BoardItemRole.accessory: 4,
  };
  final counts = <BoardItemRole, int>{};
  final kept = <StyleBoardItem>[];
  var dropped = 0;
  for (final it in items) {
    final cap = caps[it.role] ?? 0;
    final n = counts[it.role] ?? 0;
    if (cap == 0 || n >= cap) {
      final replaceAt = kept.indexWhere(
        (current) =>
            current.role == it.role &&
            !current.isLocked &&
            !current.hasValidatedCutout &&
            it.hasValidatedCutout,
      );
      if (replaceAt >= 0) {
        kept[replaceAt] = it;
        continue;
      }
      dropped++;
      continue;
    }
    counts[it.role] = n + 1;
    kept.add(it);
  }
  if (dropped > 0) {
    debugPrint(
      'AHVI_BOARD_SLOT_CAP dropped=$dropped kept=${kept.length} '
      'roles=${counts.map((k, v) => MapEntry(k.name, v))}',
    );
  }
  return kept;
}

BoardItemRole _mapItemRole(OutfitRole role) {
  return switch (role) {
    OutfitRole.hero => BoardItemRole.top,
    OutfitRole.bottom => BoardItemRole.bottom,
    OutfitRole.footwear => BoardItemRole.footwear,
    OutfitRole.outerwear => BoardItemRole.outerwear,
    OutfitRole.bag => BoardItemRole.accessory,
    OutfitRole.accessory => BoardItemRole.accessory,
    OutfitRole.other => BoardItemRole.unknown,
  };
}

OutfitRole _roleFor(Map<String, dynamic> item, String name) {
  // Honor the backend's explicit role/slot first. It is authoritative and
  // avoids lossy name-regex misses — e.g. "White Shirt" carries no garment
  // keyword, and the role word "footwear"/"top" itself never matched the
  // name-based patterns below, so backend footwear/tops were silently dropped.
  final declared = (item['role'] ?? item['slot'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  switch (declared) {
    case 'footwear':
    case 'shoe':
    case 'shoes':
      return OutfitRole.footwear;
    case 'bottom':
    case 'bottoms':
    case 'bottomwear':
      return OutfitRole.bottom;
    case 'outerwear':
    case 'jacket':
    case 'coat':
    case 'blazer':
      return OutfitRole.outerwear;
    case 'bag':
      return OutfitRole.bag;
    case 'accessory':
    case 'accessories':
    case 'travel':
    case 'grooming':
      return OutfitRole.accessory;
    case 'top':
    case 'tops':
    case 'topwear':
    case 'hero':
    case 'dress':
      // Maps to the top slot via _mapItemRole; a dress is re-detected by name
      // downstream in _toStyleBoardData and promoted to BoardItemRole.dress.
      return OutfitRole.hero;
  }
  final blob = [
    name,
    item['role'],
    item['category'],
    item['subcategory'],
    item['sub_category'],
    item['type'],
  ].whereType<Object>().join(' ').toLowerCase();
  if (RegExp(
    r'\b(trouser|trousers|pant|pants|chino|chinos|jean|jeans|denim|skirt|skirts|short|shorts|bottom|bottoms|bottomwear|churidar|pajama|pyjama|dhoti)\b',
  ).hasMatch(blob)) {
    return OutfitRole.bottom;
  }
  if (RegExp(
    r'\b(shoe|sneaker|loafer|boot|sandal|heel|jutti|mojari)\b',
  ).hasMatch(blob)) {
    return OutfitRole.footwear;
  }
  if (RegExp(
    r'\b(bag|tote|clutch|backpack|sling|duffle|briefcase)\b',
  ).hasMatch(blob)) {
    return OutfitRole.bag;
  }
  if (RegExp(
    r'\b(jacket|blazer|overshirt|coat|cardigan|outerwear)\b',
  ).hasMatch(blob)) {
    return OutfitRole.outerwear;
  }
  if (RegExp(
    r'\b(watch|belt|ring|brooch|necklace|bracelet|earring|scarf|tie|cap|hat|sunglasses|eyewear|travel|grooming|skincare|accessory|accessories)\b',
  ).hasMatch(blob)) {
    return OutfitRole.accessory;
  }
  return OutfitRole.other;
}

int _roleRank(OutfitRole role) {
  return switch (role) {
    OutfitRole.hero => 0,
    OutfitRole.outerwear => 1,
    OutfitRole.bottom => 2,
    OutfitRole.footwear => 3,
    OutfitRole.bag => 4,
    OutfitRole.accessory => 5,
    OutfitRole.other => 6,
  };
}

String _archetypeTitle(dynamic value) {
  if (value is Map) {
    return _text(
      value['title'] ?? value['name'] ?? value['archetype'] ?? value['label'],
    );
  }
  return _text(value);
}

String _selectedArchetypeTitle(Map<String, dynamic> direction) {
  return _archetypeTitle(
    direction['selected_archetype'] ??
        direction['selectedArchetype'] ??
        direction['archetype'] ??
        direction['style_archetype'],
  );
}

/// Canonical primary title shared by the live card and its detail sheet.
String resolveOutfitBoardTitle(Map<String, dynamic> direction) {
  final rawStory = direction['story'];
  final story = BoardStory.fromJson(
    rawStory is Map ? Map<String, dynamic>.from(rawStory) : null,
  );
  if (story.headline?.trim().isNotEmpty == true) return story.headline!.trim();

  // Explicit backend-curated title (e.g. Gemini-curated editorial copy)
  // outranks the generic style_archetype label — see P0.8: the backend
  // always populates both fields, and the archetype label was masking the
  // curated title on the primary live generation path.
  final explicitTitle = _text(
    direction['title'] ?? direction['board_title'] ?? direction['boardTitle'],
  );
  if (explicitTitle.isNotEmpty) {
    return explicitTitle.toLowerCase().startsWith('build outfit')
        ? 'Try-On'
        : explicitTitle;
  }

  final selectedArchetype = _selectedArchetypeTitle(direction);
  if (selectedArchetype.isNotEmpty) return selectedArchetype;

  final rawStrategy = direction['style_strategy'];
  final strategy = rawStrategy is Map
      ? Map<String, dynamic>.from(rawStrategy)
      : const <String, dynamic>{};
  final strategyArchetype = _archetypeTitle(
    strategy['selected_archetype'] ??
        strategy['selectedArchetype'] ??
        strategy['archetype'] ??
        strategy['archetype_name'],
  );
  if (strategyArchetype.isNotEmpty) return strategyArchetype;

  final strategyDirection = _text(
    strategy['direction_title'] ??
        strategy['directionTitle'] ??
        strategy['direction'],
  );
  if (strategyDirection.isNotEmpty) return strategyDirection;

  return 'Styled for You';
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _contextText(dynamic value) {
  if (value is Map) {
    return _text(
      value['label'] ??
          value['summary'] ??
          value['condition'] ??
          value['description'],
    );
  }
  return _text(value);
}

bool _isGenericContext(String value) {
  return const {
    'daily',
    'everyday',
    'general',
    'default',
  }.contains(value.trim().toLowerCase());
}

String _completeDisplayThought(String value) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 220) return text;
  final sentence = RegExp(r'^.{24,220}?[.!?](?:\s|$)').firstMatch(text);
  return sentence?.group(0)?.trim() ?? text;
}

List<String> _strings(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) {
          return _text(item['name'] ?? item['title'] ?? item['label']);
        }
        return _text(item);
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

/// Selects the strongest available image and records whether it needs framing.
String? _transparentUrlFor(
  Map<String, dynamic> item, {
  String? itemId,
  String? itemName,
  String? role,
}) {
  return resolveWardrobeImage(
    item,
    surface: 'style_board_live',
    itemId: itemId ?? '',
  ).url;
}
