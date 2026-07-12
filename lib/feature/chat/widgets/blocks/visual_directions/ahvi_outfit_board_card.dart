import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myapp/feature/chat/services/fashion_item_filter.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/editorial_collage.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/style_board_api_service.dart';
import 'package:myapp/style_board/style_board_controller.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/editorial_board_renderer.dart';

typedef OutfitBoardMessageSender = void Function(String message);

class AhviOutfitBoardCard extends StatefulWidget {
  final Map<String, dynamic> direction;
  final double width;
  final OutfitBoardMessageSender? onSendMessage;
  final Map<String, dynamic> editorialCover;

  /// Tap on the flat-lay visual opens the legacy stylist-reasoning detail
  /// sheet. The action bar keeps its own handlers and is excluded from this
  /// gesture so Save / Shuffle / Style This / Missing never trigger the sheet.
  final VoidCallback? onTapBoard;
  final StyleBoardShuffleCall? shuffleCall;

  const AhviOutfitBoardCard({
    super.key,
    required this.direction,
    required this.width,
    this.onSendMessage,
    this.editorialCover = const {},
    this.onTapBoard,
    this.shuffleCall,
  });

  @override
  State<AhviOutfitBoardCard> createState() => _AhviOutfitBoardCardState();
}

class _AhviOutfitBoardCardState extends State<AhviOutfitBoardCard> {
  late OutfitBoardModel _model;
  late StyleBoardData _initialBoard;
  StyleBoardController? _controller;
  StyleBoardData? _pendingBoard;

  @override
  void initState() {
    super.initState();
    _replaceBoard(_parseBoard(widget));
  }

  @override
  void didUpdateWidget(covariant AhviOutfitBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = _parseBoard(widget);
    if (!_isMeaningfulBoardUpdate(_initialBoard, incoming.board)) return;
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
    return (model: model, board: _toStyleBoardData(model, source.direction));
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
    final state = StyleBoardState(
      boardId: parsed.board.boardId,
      revision: parsed.board.revision,
      items: parsed.board.items,
      lockedItemIds: parsed.board.items
          .where((item) => item.isLocked && item.hasStableIdentity)
          .map((item) => item.itemId)
          .toSet(),
    );
    if (!state.supportsShuffle) {
      _controller = null;
      debugPrint(
        'AHVI_STYLE_BOARD_LOCK_DISABLED reason=missing_board_contract '
        'board_id=${state.boardId} revision=${state.revision}',
      );
      return;
    }
    _controller = StyleBoardController(
      initialState: state,
      shuffleCall: widget.shuffleCall ?? _shuffleThroughApi,
    )..addListener(_handleControllerChange);
  }

  Future<StyleBoardShuffleResult> _shuffleThroughApi(StyleBoardState board) {
    final backend = Provider.of<BackendService>(context, listen: false);
    return StyleBoardApiService(backend).shuffle(
      board: board,
      occasion: _initialBoard.occasion,
      styleDirection: _initialBoard.styleArchetype,
    );
  }

  void _handleControllerChange() {
    if (!mounted) return;
    setState(() {});
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

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChange);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = _currentBoard;
    final renderable = _isRenderableOutfit(board.items);

    return SizedBox(
      width: widget.width,
      // 4:5 portrait (Instagram-feed ratio): height = width * 5 / 4.
      height: widget.width * 5 / 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Soft off-white canvas so the board reads as one flat-lay surface,
          // not a stack of product tiles.
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTapBoard,
                child: OutfitContextStrip(model: _model),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTapBoard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                    child: renderable
                        ? EditorialBoardCanvas(
                            board: board,
                            lockedItemIds:
                                _controller?.state.lockedItemIds ?? const {},
                            onToggleLock: _controller?.toggleLock,
                          )
                        : _IncompleteBoardFallback(
                            title: board.title,
                            whyItWorks: board.whyItWorks,
                          ),
                  ),
                ),
              ),
              if (_controller != null)
                BoardMutationBar(controller: _controller!),
              OutfitActionBar(
                direction: widget.direction,
                editorialCover: widget.editorialCover,
                primaryLabel: _model.title,
                missingName: _model.missingName,
                onSendMessage: widget.onSendMessage,
              ),
            ],
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
    final t = context.themeTokens;
    if (items.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: t.accent.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Icon(
            Icons.checkroom_rounded,
            color: t.accent.primary.withValues(alpha: 0.55),
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
    final t = context.themeTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              model.title,
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            if (model.chips.isNotEmpty || model.wardrobeMatchPct != null) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (model.wardrobeMatchPct != null)
                    _WardrobeMatchPill(pct: model.wardrobeMatchPct!),
                  ...model.chips
                      .take(3)
                      .map((chip) => _ContextChip(label: chip)),
                ],
              ),
            ],
            // Style reason (why_it_works) — was never rendered, so boards
            // showed no rationale. Show it under the title.
            if (model.intelligenceText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                model.intelligenceText,
                textAlign: TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.22,
                ),
              ),
            ],
            if (model.stylingTip.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                model.stylingTip,
                textAlign: TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.mutedText,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  height: 1.18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  final String label;

  const _ContextChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      constraints: const BoxConstraints(maxWidth: 98),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        border: Border.all(color: const Color(0xFFE7E0D8), width: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.mutedText,
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
    final t = context.themeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: t.accent.primary.withValues(alpha: 0.45),
          width: 0.7,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checkroom_rounded, size: 11, color: t.accent.primary),
          const SizedBox(width: 4),
          Text(
            '$pct% wardrobe match',
            style: TextStyle(
              color: t.accent.primary,
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

  const BoardMutationBar({super.key, required this.controller});

  Future<void> _shuffle(BuildContext context) async {
    final code = await controller.shuffle();
    if (!context.mounted || code == null) return;
    final message = switch (code) {
      'ALL_ITEMS_LOCKED' => 'Unlock an item to shuffle.',
      'NO_REPLACEMENT_FOUND' =>
        'AHVI couldn’t find a stronger replacement right now.',
      'FIXED_ITEMS_INCOMPATIBLE' =>
        'These locked pieces can’t form a complete look together. Unlock one piece and try again.',
      'BOARD_REVISION_CONFLICT' =>
        'This board changed. Your current look has been preserved.',
      _ =>
        'We couldn’t refresh these pieces. Your current look has been preserved.',
    };
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final state = controller.state;
    final locked = state.lockedItemIds.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.cardBorder)),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            Expanded(
              child: _BoardAction(
                icon: state.isShuffling
                    ? Icons.hourglass_top_rounded
                    : Icons.shuffle_rounded,
                label: state.allItemsLocked
                    ? 'Unlock an item to shuffle'
                    : 'Shuffle unlocked pieces',
                enabled: !state.isShuffling && !state.allItemsLocked,
                onTap: () => _shuffle(context),
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
            if (controller.canUndo)
              Expanded(
                child: _BoardAction(
                  icon: Icons.undo_rounded,
                  label: 'Undo shuffle',
                  enabled: !state.isShuffling,
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
                    color: t.mutedText,
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
  final Map<String, dynamic> direction;
  final Map<String, dynamic> editorialCover;
  final String primaryLabel;
  final String missingName;
  final OutfitBoardMessageSender? onSendMessage;

  const OutfitActionBar({
    super.key,
    required this.direction,
    required this.editorialCover,
    required this.primaryLabel,
    required this.missingName,
    this.onSendMessage,
  });

  @override
  State<OutfitActionBar> createState() => _OutfitActionBarState();
}

class _OutfitActionBarState extends State<OutfitActionBar> {
  bool _saved = false;
  bool _saving = false;
  bool _liked = false;
  bool _disliked = false;

  void _sendFeedback(String action) {
    // Fire-and-forget; also the adaptive stylist-brain training signal.
    Provider.of<BackendService>(
      context,
      listen: false,
    ).sendBoardFeedback(action: action, board: widget.direction);
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

  void _share() {
    _sendFeedback('shared');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Sharing this look…'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  Future<void> _toggleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_saved) {
        await SavedBoardsStore.remove(_id);
      } else {
        await SavedBoardsStore.saveBoard(
          occasion: _occasion,
          directionName: widget.primaryLabel,
          direction: widget.direction,
          editorialCover: widget.editorialCover,
        );
        _sendFeedback('saved');
      }
      if (!mounted) return;
      setState(() {
        _saved = !_saved;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final canSend = widget.onSendMessage != null;
    final actions = <Widget>[
      _BoardAction(
        icon: _saved
            ? Icons.check_circle_rounded
            : Icons.favorite_border_rounded,
        label: _saved ? 'Saved' : 'Save',
        enabled: !_saving,
        onTap: _toggleSave,
      ),
      _BoardAction(
        icon: Icons.shuffle_rounded,
        label: 'Shuffle',
        enabled: canSend,
        onTap: () => widget.onSendMessage?.call(
          'Show me another look for ${widget.primaryLabel}',
        ),
      ),
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
      _BoardAction(
        icon: Icons.ios_share_rounded,
        label: 'Share',
        enabled: true,
        onTap: _share,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.cardBorder)),
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
    final t = context.themeTokens;
    final color = enabled ? t.textPrimary : t.mutedText.withValues(alpha: 0.45);
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
    final directionName = _text(
      direction['direction_name'] ?? direction['directionName'],
    );
    final archetype = _text(direction['archetype']);
    final wardrobeMatchRaw =
        direction['wardrobe_match_pct'] ?? direction['wardrobeMatchPct'];
    final int? wardrobeMatchPct = wardrobeMatchRaw is int
        ? wardrobeMatchRaw
        : (wardrobeMatchRaw is num
              ? wardrobeMatchRaw.round()
              : (wardrobeMatchRaw is String
                    ? int.tryParse(wardrobeMatchRaw)
                    : null));
    // Title preference: the curated archetype name ("Structured Ease",
    // "Clean Minimal") is the intended board title. Only fall back to
    // direction_name / generic title when archetype is absent.
    final title = archetype.isNotEmpty
        ? archetype
        : (directionName.isNotEmpty
              ? directionName
              : _text(direction['title'], fallback: 'Style Direction'));
    final occasion = _text(
      direction['occasion'] ?? editorialCover['occasion_label'],
    );
    final adjectives = _strings(direction['adjectives']);
    final chips = <String>[
      if (occasion.isNotEmpty) occasion,
      if (adjectives.isNotEmpty) adjectives.first,
    ];
    final intelligenceText = _text(
      direction['short_note'] ??
          direction['shortNote'] ??
          direction['why_it_works'] ??
          direction['whyItWorks'] ??
          direction['why_this_works'] ??
          direction['explanation'] ??
          editorialCover['summary'],
    );
    final stylingTip = _text(
      direction['styling_tip'] ??
          direction['style_tip'] ??
          direction['style_note'] ??
          direction['styleNote'],
    );

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
              item['asset_id'],
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
  Map<String, dynamic> direction,
) {
  final items = <StyleBoardItem>[];
  // Render-adjacent safety net: even if the backend (now family-capped) or the
  // upstream id-keyed dedup let a duplicate through, never paint the same image
  // or the same normalized name twice on the collage.
  final seenImages = <String>{};
  final seenNames = <String>{};
  for (final item in model.imageItems) {
    final image = (item.imageUrl ?? '').trim();
    final normName = item.name.trim().toLowerCase();
    if (image.isNotEmpty && !seenImages.add(image)) continue;
    if (normName.isNotEmpty && !seenNames.add(normName)) continue;
    var role = _mapItemRole(item.role);
    if (role == BoardItemRole.top &&
        RegExp(
          r'\b(dress|gown|saree|sari|lehenga|jumpsuit)\b',
          caseSensitive: false,
        ).hasMatch(item.name.toLowerCase())) {
      role = BoardItemRole.dress;
    }
    final rawItems = _maps(direction['board_items'] ?? direction['boardItems']);
    final raw = rawItems
        .where(
          (candidate) =>
              _text(
                candidate['item_id'] ??
                    candidate['id'] ??
                    candidate[r'$id'] ??
                    candidate['itemId'] ??
                    candidate['image_id'] ??
                    candidate['asset_id'],
              ) ==
              item.id,
        )
        .firstOrNull;
    final canonical = raw == null ? null : StyleBoardItem.fromJson(raw);
    items.add(
      StyleBoardItem(
        id: item.id,
        slot: canonical?.slot ?? role.name,
        boardRole: canonical?.boardRole ?? '',
        source: canonical?.source ?? 'unknown',
        accessoryType: canonical?.accessoryType ?? '',
        name: item.name,
        imageUrl: canonical?.imageUrl ?? image,
        maskedUrl: canonical?.maskedUrl ?? '',
        boardImageUrl: canonical?.boardImageUrl ?? image,
        normalizedUrl: canonical?.normalizedUrl ?? '',
        category: canonical?.category ?? item.role.name,
        subCategory: canonical?.subCategory ?? '',
        role: role,
        position: canonical?.position,
        isLocked: canonical?.isLocked ?? false,
        raw: raw ?? const {},
      ),
    );
  }
  final rendered = _enforceSlots(items);
  final totalInput = model.imageItems.length;
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
  );
}

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

/// A board is an outfit only when it carries top+bottom+footwear OR
/// dress(fullBody)+footwear. Otherwise the caller shows the text direction
/// instead of painting a broken board. Logs the missing slots.
bool _isRenderableOutfit(List<StyleBoardItem> items) {
  final roles = items.map((e) => e.role).toSet();
  final classic = roles.containsAll({
    BoardItemRole.top,
    BoardItemRole.bottom,
    BoardItemRole.footwear,
  });
  final dressed =
      roles.contains(BoardItemRole.dress) &&
      roles.contains(BoardItemRole.footwear);

  final knownRoleImages = items
      .where((i) => i.role != BoardItemRole.unknown)
      .length;

  if (!classic && !dressed && knownRoleImages < 3) {
    final missing = <String>[];
    if (!roles.contains(BoardItemRole.footwear)) missing.add('footwear');
    if (!roles.contains(BoardItemRole.dress)) {
      if (!roles.contains(BoardItemRole.top)) missing.add('top');
      if (!roles.contains(BoardItemRole.bottom)) missing.add('bottom');
    }
    debugPrint(
      'AHVI_BOARD_INCOMPLETE missing=${missing.join(",")} '
      'roles=${roles.map((e) => e.name).join(",")}',
    );
  }
  return classic || dressed || knownRoleImages >= 3;
}

/// Shown instead of a broken board when required slots are missing. Keeps the
/// direction readable (title + why) rather than painting an incomplete collage.
class _IncompleteBoardFallback extends StatelessWidget {
  final String title;
  final String? whyItWorks;
  const _IncompleteBoardFallback({required this.title, this.whyItWorks});

  @override
  Widget build(BuildContext context) {
    final note = (whyItWorks ?? '').trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                note,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
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

/// Returns the first valid transparent-PNG URL for a board item, or null.
///
/// Priority:
///   1. board_image_url / transparent_image_url (explicit transparent fields)
///   2. cutout_url if cutout_status == ready
///   3. image_url if board_status == cutout_ready (backend already resolved it)
///
/// Never falls back to normalized/catalog product tile URLs.
String? _transparentUrlFor(
  Map<String, dynamic> item, {
  String? itemId,
  String? itemName,
  String? role,
}) {
  for (final key in const <String>[
    'board_image_url',
    'boardImageUrl',
    'transparent_image_url',
    'transparentImageUrl',
  ]) {
    final v = item[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  final cutoutStatus = (item['cutout_status'] ?? item['cutoutStatus'] ?? '')
      .toString()
      .toLowerCase()
      .trim();
  final cutoutUrl = (item['cutout_url'] ?? item['cutoutUrl'] ?? '')
      .toString()
      .trim();
  if (cutoutUrl.isNotEmpty && cutoutStatus == 'ready') return cutoutUrl;

  // board_status == "cutout_ready" means the backend's resolver already picked
  // a transparent PNG and placed it in image_url. Trust the backend signal.
  final boardStatus = (item['board_status'] ?? item['boardStatus'] ?? '')
      .toString()
      .toLowerCase()
      .trim();
  if (boardStatus == 'cutout_ready') {
    final imageUrl = (item['image_url'] ?? item['imageUrl'] ?? '')
        .toString()
        .trim();
    if (imageUrl.isNotEmpty) return imageUrl;
  }

  debugPrint(
    'AHVI_BOARD_ASSET_SKIPPED_NON_TRANSPARENT '
    'item_id=${itemId ?? ""} '
    'role=${role ?? ""} '
    'name=${itemName ?? ""} '
    'attempted_url_fields=[board_image_url,transparent_image_url,cutout_url,image_url(board_status=cutout_ready)] '
    'cutout_status=$cutoutStatus '
    'board_status=$boardStatus '
    'reason=no_transparent_png_available',
  );
  return null;
}
