import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/style_board/saved_board_card.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';

// ── Data model ───────────────────────────────────────────────────────────────
class LookItem {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String category;
  final String? imageUrl;
  final List<String> outfitImages;
  final LookBadgeStyle badge;
  final LookBgStyle bg;

  const LookItem({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.category,
    this.imageUrl,
    this.outfitImages = const [],
    required this.badge,
    required this.bg,
  });
}

enum LookBadgeStyle {
  streetwear,
  athleisure,
  boho,
  minimalist,
  vintage,
  monochrome,
  cottagecore,
  defaultBadge,
}

enum LookBgStyle {
  streetwear,
  athleisure,
  boho,
  minimalist,
  vintage,
  monochrome,
  cottagecore,
  defaultBg,
}

// ── Main Screen ──────────────────────────────────────────────────────────────
class OccasionBoard extends StatefulWidget {
  final String occasion;
  final String titleKey; // l10n key for the bold title word
  final String subtitleKey; // l10n key for the accent subtitle word
  final String? titleLabel; // raw string override (e.g. custom board name)
  final String? subtitleLabel; // raw string override
  final String emptyEmoji;

  const OccasionBoard({
    super.key,
    required this.occasion,
    this.titleKey = '',
    this.subtitleKey = '',
    this.titleLabel,
    this.subtitleLabel,
    this.emptyEmoji = '✨',
  });

  @override
  State<OccasionBoard> createState() => _OccasionBoardState();
}

class _OccasionBoardState extends State<OccasionBoard> {
  AppThemeTokens get _t => context.themeTokens;
  Color get _bg => _t.backgroundPrimary;
  Color get _bg2 => _t.backgroundSecondary;
  Color get _phoneShell => _t.phoneShell;
  Color get _text => _t.textPrimary;

  bool _isLoading = true;
  String? _toastMessage;
  List<dynamic> _boards = [];
  Map<String, Map<String, dynamic>> _wardrobeById = const {};

  @override
  void initState() {
    super.initState();
    _fetchLooks();
  }

  Future<void> _fetchLooks() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final results = await Future.wait([
        appwrite.getSavedBoardsByOccasion(widget.occasion),
        appwrite.getWardrobeItems(),
      ]);
      final docs = results[0] as List;
      final wardrobe = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _boards = docs;
          _wardrobeById = _buildIdMap(wardrobe);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showToast(context.tr('error'));
    }
  }

  Map<String, dynamic> _boardData(dynamic board) {
    try {
      final data = board.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    if (board is Map && board['data'] is Map) {
      return Map<String, dynamic>.from(board['data'] as Map);
    }
    return const {};
  }

  Future<void> _deleteLook(String id) async {
    final board = _boards.cast<dynamic>().firstWhere(
      (candidate) => _boardId(candidate) == id,
      orElse: () => null,
    );
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.deleteSavedBoard(id);

      if (board != null) {
        try {
          await SavedBoardsStore.removeForServerBoard(
            expandSavedBoardData(_boardData(board)),
          );
        } catch (e) {
          debugPrint('AHVI_SAVED_BOARD_LOCAL_CLEANUP_FAILED err=$e');
        }
      }
      if (!mounted) return;
      setState(() => _boards.removeWhere((candidate) => _boardId(candidate) == id));
      _showToast(context.tr('wardrobe_remove'));
    } catch (e) {
      _showToast(context.tr('error'));
    }
  }

  void _showToast(String msg) {
    setState(() => _toastMessage = msg);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Map<String, Map<String, dynamic>> _buildIdMap(
      List<Map<String, dynamic>> items,
      ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in items) {
      for (final rawId in [
        item[r'$id'],
        item['id'],
        item['item_id'],
        item['itemId'],
        item['image_id'],
        item['imageId'],
      ]) {
        final id = (rawId ?? '').toString().trim();
        if (id.isNotEmpty) byId[id] = item;
      }
    }
    return byId;
  }

  String _boardId(dynamic board) {
    try {
      final value = board.$id;
      if (value != null) return value.toString();
    } catch (_) {}
    if (board is Map) {
      return (board[r'$id'] ?? board['id'] ?? '').toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final countText = _boards.isEmpty
        ? context.tr('wardrobe_empty_title')
        : '${_boards.length} ${context.tr('fitness_saved')}';

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.5, 1.0],
                colors: [_bg, _bg2, _bg],
              ),
            ),
          ),
          Column(
            children: [
              // ── HEADER ──
              _Header(
                countText: countText,
                titleKey: widget.titleKey,
                subtitleKey: widget.subtitleKey,
                titleLabel: widget.titleLabel,
                subtitleLabel: widget.subtitleLabel,
              ),

              // ── GRID SCROLL AREA ──
              Expanded(
                child: Container(
                  color: _bg,
                  child: _isLoading
                      ? Center(
                    child: CircularProgressIndicator(
                      color: _t.accent.primary,
                    ),
                  )
                      : _boards.isEmpty
                      ? RefreshIndicator(
                    onRefresh: _fetchLooks,
                    color: _t.accent.primary,
                    backgroundColor: _t.card,
                    child: ListView(
                      children: [
                        _EmptyState(
                          titleKey: widget.titleKey,
                          titleLabel: widget.titleLabel,
                          occasion: widget.occasion,
                          emoji: widget.emptyEmoji,
                        ),
                      ],
                    ),
                  )
                      : RefreshIndicator(
                    onRefresh: _fetchLooks,
                    color: _t.accent.primary,
                    backgroundColor: _t.card,
                    child: _LooksGrid(
                      boards: _boards,
                      wardrobeById: _wardrobeById,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // ── TOAST ──
          if (_toastMessage != null)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _phoneShell,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _toastMessage!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String countText;
  final String titleKey;
  final String subtitleKey;
  final String? titleLabel;
  final String? subtitleLabel;

  const _Header({
    required this.countText,
    required this.titleKey,
    required this.subtitleKey,
    this.titleLabel,
    this.subtitleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 48, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: [t.phoneShellInner, t.phoneShell, t.backgroundSecondary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.cardBorder),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                color: t.textPrimary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${titleLabel ?? context.tr(titleKey)} ',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: subtitleLabel ?? context.tr(subtitleKey),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    color: t.accent.primary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            countText,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: t.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Looks Grid ───────────────────────────────────────────────────────────────
class _LooksGrid extends StatelessWidget {
  final List<dynamic> boards;
  final Map<String, Map<String, dynamic>> wardrobeById;

  const _LooksGrid({required this.boards, required this.wardrobeById});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.56,
      ),
      itemCount: boards.length,
      itemBuilder: (context, index) =>
          SavedBoardCard(source: boards[index], wardrobeById: wardrobeById),
    );
  }
}

// ── Look Card ────────────────────────────────────────────────────────────────
class _LookCard extends StatefulWidget {
  final LookItem look;
  final bool featured;
  final void Function(String id) onDelete;
  final void Function(LookItem look) onShare;

  const _LookCard({
    required this.look,
    required this.featured,
    required this.onDelete,
    required this.onShare,
  });

  @override
  State<_LookCard> createState() => _LookCardState();
}

class _LookCardState extends State<_LookCard> {
  bool _hovered = false;

  AppThemeTokens get _t => context.themeTokens;

  LinearGradient _bgGradient(LookBgStyle bg) {
    switch (bg) {
      case LookBgStyle.streetwear:
        return LinearGradient(
          colors: [
            _t.accent.tertiary.withValues(alpha: 0.3),
            _t.accent.primary.withValues(alpha: 0.15),
          ],
        );
      case LookBgStyle.athleisure:
        return LinearGradient(
          colors: [
            _t.accent.secondary.withValues(alpha: 0.3),
            _t.accent.tertiary.withValues(alpha: 0.1),
          ],
        );
      default:
        return LinearGradient(colors: [_t.panel, _t.backgroundSecondary]);
    }
  }

  Color _badgeColor(LookBadgeStyle badge) {
    switch (badge) {
      case LookBadgeStyle.streetwear:
        return _t.accent.primary;
      case LookBadgeStyle.athleisure:
        return _t.accent.secondary;
      case LookBadgeStyle.boho:
        return _t.accent.tertiary;
      default:
        return _t.mutedText;
    }
  }

  Color _badgeBg(LookBadgeStyle badge) {
    switch (badge) {
      case LookBadgeStyle.streetwear:
        return _t.accent.primary.withValues(alpha: 0.12);
      case LookBadgeStyle.minimalist:
        return _t.accent.primary.withValues(alpha: 0.15);
      case LookBadgeStyle.vintage:
        return _t.accent.secondary.withValues(alpha: 0.16);
      case LookBadgeStyle.monochrome:
        return _t.panel;
      case LookBadgeStyle.cottagecore:
        return _t.accent.tertiary.withValues(alpha: 0.14);
      default:
        return _t.panel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final aspectRatio = widget.featured ? 2.0 : 1.0;
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? _t.accent.tertiary : _t.cardBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? _t.accent.tertiary.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.2),
                blurRadius: _hovered ? 28 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image / placeholder
              Stack(
                children: [
                  look.outfitImages.length >= 2
                      ? AspectRatio(
                    aspectRatio: aspectRatio,
                    child: _SavedLookImageGrid(images: look.outfitImages),
                  )
                      : look.imageUrl != null && look.imageUrl!.isNotEmpty
                      ? AspectRatio(
                    aspectRatio: aspectRatio,
                    child: Image.network(
                      look.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  )
                      : AspectRatio(
                    aspectRatio: aspectRatio,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _bgGradient(look.bg),
                      ),
                      child: Center(
                        child: Text(
                          look.emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  ),
                  // Delete button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: () => widget.onDelete(look.id),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _t.phoneShellInner.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(color: _t.cardBorder, width: 1),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: _t.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Card info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeBg(look.badge),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          look.category.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _badgeColor(look.badge),
                          ),
                        ),
                      ),
                      // Title
                      Text(
                        look.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _t.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Description
                      Text(
                        look.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: _t.mutedText,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Try On button
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_t.accent.tertiary, _t.accent.primary],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _t.accent.tertiary.withValues(alpha: 0.40),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: onAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.tr('daily_wear_try_on'),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedLookImageGrid extends StatelessWidget {
  final List<String> images;

  const _SavedLookImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final visible = images.take(5).toList();
    return Container(
      color: const Color(0xFFFFFCF5),
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(visible[index], fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String titleKey;
  final String? titleLabel;
  final String occasion;
  final String emoji;
  const _EmptyState({
    required this.titleKey,
    required this.emoji,
    this.titleLabel,
    this.occasion = '',
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              titleLabel?.trim().isNotEmpty == true
                  ? titleLabel!.trim()
                  : context.tr(titleKey),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              occasion.toLowerCase().startsWith('custom:')
                  ? 'This board is empty. Save looks from AHVI chat or wardrobe to add them here.'
                  : 'No looks saved here yet. Build one in AHVI chat and tap Save.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: t.mutedText,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
