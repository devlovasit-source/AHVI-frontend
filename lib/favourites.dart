import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/style_board/saved_board_images.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';

// ── Data model ───────────────────────────────────────────────────────────────
class FavouriteLookItem {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String category;
  final String? imageUrl;
  final List<String> outfitImages;
  final String filter;
  final LookBadgeStyle badge;
  final LookBgStyle bg;
  bool isFavourite;

  FavouriteLookItem({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.category,
    this.imageUrl,
    this.outfitImages = const [],
    required this.filter,
    required this.badge,
    required this.bg,
    this.isFavourite = true,
  });
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

// ── Filter pill data ─────────────────────────────────────────────────────────
class FilterPillData {
  final String label;
  final String filter;
  const FilterPillData(this.label, this.filter);
}

/// Lightweight wrapper so wardrobe items look like Appwrite documents
/// to the rest of the screen without breaking existing $id access.
class _WardrobeSource {
  final String id;
  final Map<String, dynamic> data;
  const _WardrobeSource({required this.id, required this.data});
}

class _FavouriteBoardEntry {
  final dynamic source;
  final String filter;
  const _FavouriteBoardEntry({required this.source, required this.filter});
}

// ── Main Screen ──────────────────────────────────────────────────────────────
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  AppThemeTokens get _t => context.themeTokens;
  Color get _bg => _t.backgroundPrimary;
  Color get _bg2 => _t.backgroundSecondary;
  Color get _text => _t.textPrimary;

  bool _isLoading = true;
  String _activeFilter = 'all';
  String? _toastMessage;

  List<_FavouriteBoardEntry> _boards = [];
  List<FavouriteLookItem> _looks = [];
  List<FilterPillData> _filters = [];

  @override
  void initState() {
    super.initState();
    _fetchFavouriteLooks();
  }

  Future<void> _fetchFavouriteLooks() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final favDocs = await appwrite.getFavouriteSavedBoards();
      final wardrobe = await appwrite.getWardrobeItems();

      final Set<String> uniqueCategories = {};
      final List<_FavouriteBoardEntry> loadedBoards = [];
      final List<FavouriteLookItem> loadedLooks = [];

      // ── 1. Saved boards (existing logic) ─────────────────────────────────
      for (var doc in favDocs) {
        final outfitImages = extractSavedBoardImages(
          Map<String, dynamic>.from(doc.data),
        );
        final occasion =
            doc.data['boardCategoryLabel']?.toString() ??
            doc.data['occasion']?.toString() ??
            AppLocalizations.t(context, 'fav_default_occasion');

        uniqueCategories.add(occasion);
        loadedBoards.add(
          _FavouriteBoardEntry(source: doc, filter: occasion.toLowerCase()),
        );

        final styleIndex =
            occasion.hashCode % (LookBadgeStyle.values.length - 1);
        final dynamicBadge = LookBadgeStyle.values[styleIndex];
        final dynamicBg = LookBgStyle.values[styleIndex];

        loadedLooks.add(
          FavouriteLookItem(
            id: doc.$id,
            title: (doc.data['title'] ?? occasion).toString(),
            description:
                (doc.data['outfitDescription'] ??
                        AppLocalizations.t(
                          context,
                          'fav_look_for_occasion',
                        ).replaceAll('{occasion}', occasion))
                    .toString(),
            emoji: '❤️',
            category: occasion,
            filter: occasion.toLowerCase(),
            imageUrl: outfitImages.isNotEmpty ? outfitImages.first : null,
            outfitImages: outfitImages,
            badge: dynamicBadge,
            bg: dynamicBg,
            isFavourite: true,
          ),
        );
      }

      // ── 2. Liked wardrobe items ───────────────────────────────────────────
      // Wardrobe items where isLiked == true
      // FIX: getWardrobeItems() returns Map<String, dynamic> with 'id', '$id', 'category', etc.
      for (var item in wardrobe) {
        if (item is! Map<String, dynamic>) continue;

        // Extract ID - try both 'id' and '$id' keys
        final itemId = (item['id'] ?? item[r'$id'] ?? '').toString();
        if (itemId.isEmpty) continue;

        // Check if this wardrobe item is liked
        final bool isLiked =
            item['isLiked'] == true || item['isFavourite'] == true;
        if (!isLiked) continue;

        final category = (item['category'] ?? 'Wardrobe').toString();
        uniqueCategories.add(category);

        // Wrap in _WardrobeSource so _boardId logic works consistently
        final wardrobeSource = _WardrobeSource(id: itemId, data: item);
        loadedBoards.add(
          _FavouriteBoardEntry(
            source: wardrobeSource,
            filter: category.toLowerCase(),
          ),
        );

        final styleIndex =
            category.hashCode % (LookBadgeStyle.values.length - 1);
        final dynamicBadge = LookBadgeStyle.values[styleIndex.abs()];
        final dynamicBg = LookBgStyle.values[styleIndex.abs()];

        // Try multiple image URL keys
        final imageUrl =
            (item['image_url'] ??
                    item['imageUrl'] ??
                    item['masked_url'] ??
                    item['normalized_url'] ??
                    item['raw_url'])
                ?.toString();

        loadedLooks.add(
          FavouriteLookItem(
            id: itemId,
            title: (item['name'] ?? category).toString(),
            description: AppLocalizations.t(context, 'fav_liked_from_wardrobe'),
            emoji: '❤️',
            category: category,
            filter: category.toLowerCase(),
            imageUrl: imageUrl,
            outfitImages: imageUrl != null ? [imageUrl] : [],
            badge: dynamicBadge,
            bg: dynamicBg,
            isFavourite: true,
          ),
        );
      }

      // Build filter pills from unique categories
      _filters = [
        FilterPillData(AppLocalizations.t(context, 'fav_filter_all'), 'all'),
        ...uniqueCategories
            .map((c) => FilterPillData(c, c.toLowerCase()))
            .toList(),
      ];

      setState(() {
        _boards = loadedBoards;
        _looks = loadedLooks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _toastMessage = AppLocalizations.t(context, 'fav_error_loading');
    }
  }

  /// Extract ID from either _WardrobeSource or Appwrite Document
  String _boardId(dynamic source) {
    if (source is _WardrobeSource) {
      return source.id;
    }
    try {
      // Try Appwrite Document object
      return source?.$id?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Extract data map from either _WardrobeSource or Appwrite Document
  Map<String, dynamic> _boardData(dynamic source) {
    if (source is _WardrobeSource) {
      return source.data;
    }
    try {
      // Try Appwrite Document object
      return Map<String, dynamic>.from(source?.data ?? {});
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          context.tr('wardrobe_favourite'),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _looks.isEmpty
          ? _EmptyState()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // Filter pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: _filters
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterPill(
                              label: f.label,
                              isActive: _activeFilter == f.filter,
                              onTap: () {
                                setState(() => _activeFilter = f.filter);
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                // Looks grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _filteredLooks.length,
                  itemBuilder: (context, index) => _LookCard(
                    look: _filteredLooks[index],
                    userId:
                        Provider.of<AppwriteService>(
                          context,
                          listen: false,
                        ).currentUserId ??
                        '',
                    onDelete: () => _deleteLook(_filteredLooks[index]),
                    onFavouriteToggled: () => setState(() {}),
                  ),
                ),
              ],
            ),
    );
  }

  List<FavouriteLookItem> get _filteredLooks {
    if (_activeFilter == 'all') return _looks;
    return _looks.where((l) => l.filter == _activeFilter).toList();
  }

  Future<void> _deleteLook(FavouriteLookItem look) async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final boardEntry = _boards.firstWhere(
        (b) => _boardId(b.source) == look.id,
        orElse: () => _FavouriteBoardEntry(source: null, filter: ''),
      );

      if (boardEntry.source == null) return;

      if (boardEntry.source is _WardrobeSource) {
        // Wardrobe item: this is a "like" toggle, not a deletion — only
        // clear the isLiked flag. Never touch SavedBoardsStore here, it
        // has nothing to do with wardrobe favourites.
        final wardrobeSource = boardEntry.source as _WardrobeSource;
        await appwrite.updateWardrobeItem(wardrobeSource.id, {
          'isLiked': false,
        });
      } else {
        // Saved board: delete the authoritative Appwrite document first.
        await appwrite.deleteSavedBoard(look.id);
        // Best-effort local mirror cleanup so the chat "Saved" heart
        // doesn't keep showing saved for this board. A failure here must
        // not make the server delete look like it failed.
        try {
          await SavedBoardsStore.removeForServerBoard(
            expandSavedBoardData(_boardData(boardEntry.source)),
          );
        } catch (e) {
          debugPrint('AHVI_SAVED_BOARD_LOCAL_CLEANUP_FAILED err=$e');
        }
      }

      setState(() {
        _looks.removeWhere((l) => l.id == look.id);
        _boards.removeWhere((b) => _boardId(b.source) == look.id);
      });

      _toastMessage = AppLocalizations.t(context, 'fav_removed');
    } catch (e) {
      debugPrint('Error deleting favourite: $e');
      _toastMessage = AppLocalizations.t(context, 'fav_error_deleting');
    }
  }
}

// ── Filter Pill ──────────────────────────────────────────────────────────────
class FilterPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const FilterPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? t.accent.primary : t.backgroundSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? t.accent.primary : t.panelBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : t.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Look Card ────────────────────────────────────────────────────────────────
class _LookCard extends StatefulWidget {
  final FavouriteLookItem look;
  final String userId;
  final VoidCallback onDelete;
  final VoidCallback onFavouriteToggled;

  const _LookCard({
    required this.look,
    required this.userId,
    required this.onDelete,
    required this.onFavouriteToggled,
  });

  @override
  State<_LookCard> createState() => _LookCardState();
}

class _LookCardState extends State<_LookCard> {
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.look.isFavourite;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;

    return GestureDetector(
      onLongPress: widget.onDelete,
      child: Container(
        decoration: BoxDecoration(
          gradient: _bgGradient(widget.look.bg),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background image
            if (widget.look.imageUrl != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.look.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            // Overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge and favourite button
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _badgeBg(widget.look.badge),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.look.category.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: _badgeColor(widget.look.badge),
                            ),
                          ),
                        ),
                        // ── Heart / favourite toggle ──────────────────────
                        Tooltip(
                          message: 'Saved favorite',
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: _isLiked ? Colors.red : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Title and description
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.look.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.look.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ],
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

  LinearGradient _bgGradient(LookBgStyle style) {
    return switch (style) {
      LookBgStyle.streetwear => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF1A1A1A), const Color(0xFF2D2D2D)],
      ),
      LookBgStyle.athleisure => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF6B9BD1), const Color(0xFFE8F4F8)],
      ),
      LookBgStyle.boho => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFD4A574), const Color(0xFFF5E6D3)],
      ),
      LookBgStyle.minimalist => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
      ),
      LookBgStyle.vintage => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFC4876A), const Color(0xFFFAE5D3)],
      ),
      LookBgStyle.monochrome => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF333333), const Color(0xFFCCCCCC)],
      ),
      LookBgStyle.cottagecore => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFC4A69D), const Color(0xFFFAE5D3)],
      ),
      LookBgStyle.defaultBg => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFE8E8E8), const Color(0xFFF8F8F8)],
      ),
    };
  }

  Color _badgeBg(LookBadgeStyle style) {
    return switch (style) {
      LookBadgeStyle.streetwear => const Color(0xFF1A1A1A),
      LookBadgeStyle.athleisure => const Color(0xFFE8F4F8),
      LookBadgeStyle.boho => const Color(0xFFFAEBD7),
      LookBadgeStyle.minimalist => const Color(0xFFF5F5F5),
      LookBadgeStyle.vintage => const Color(0xFFFAE5D3),
      LookBadgeStyle.monochrome => const Color(0xFFDDDDDD),
      LookBadgeStyle.cottagecore => const Color(0xFFFAE5D3),
      LookBadgeStyle.defaultBadge => const Color(0xFFE8E8E8),
    };
  }

  Color _badgeColor(LookBadgeStyle style) {
    return switch (style) {
      LookBadgeStyle.streetwear => const Color(0xFFFFFFFF),
      LookBadgeStyle.athleisure => const Color(0xFF4A7BA7),
      LookBadgeStyle.boho => const Color(0xFF8B6F47),
      LookBadgeStyle.minimalist => const Color(0xFF333333),
      LookBadgeStyle.vintage => const Color(0xFF8B5A3C),
      LookBadgeStyle.monochrome => const Color(0xFF333333),
      LookBadgeStyle.cottagecore => const Color(0xFF5D4E37),
      LookBadgeStyle.defaultBadge => const Color(0xFF666666),
    };
  }
}

// ── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('❤️', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              context.tr('wardrobe_favourite_empty'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('wardrobe_favourite_empty_desc'),
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
