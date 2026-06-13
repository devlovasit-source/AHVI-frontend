import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/app_localizations.dart';

// ── Data model ───────────────────────────────────────────────────────────────
class LookItem {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String category;
  final String? imageUrl;
  final List<String> outfitImages; // Full outfit images list
  final String filter;
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
    required this.filter,
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

// ── Filter pill data ─────────────────────────────────────────────────────────
class FilterPillData {
  final String label;
  final String filter;
  const FilterPillData(this.label, this.filter);
}

// ── Main Screen ──────────────────────────────────────────────────────────────
class EverythingElseScreen extends StatefulWidget {
  const EverythingElseScreen({super.key});

  @override
  State<EverythingElseScreen> createState() => _EverythingElseScreenState();
}

class _EverythingElseScreenState extends State<EverythingElseScreen> {
  AppThemeTokens get _t => context.themeTokens;
  Color get _bg => _t.backgroundPrimary;
  Color get _bg2 => _t.backgroundSecondary;
  Color get _phoneShell => _t.phoneShell;
  Color get _text => _t.textPrimary;

  bool _isLoading = true;
  String _activeFilter = 'all';
  String? _toastMessage;

  List<LookItem> _looks = [];
  List<FilterPillData> _filters = [];

  final List<String> _excludedMainCategories = [
    'gym',
    'office',
    'party',
    'daily wear',
    'home',
  ];

  @override
  void initState() {
    super.initState();
    _fetchDynamicLooks();
  }

  Future<void> _fetchDynamicLooks() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final primaryDocs = await appwrite.getSavedBoardsByOccasion(
        'Everything Else',
      );
      final allDocs = await appwrite.getAllSavedBoards();
      final docs = [
        ...primaryDocs,
        ...allDocs.where((doc) {
          final data = doc.data;
          final boardCategory = (data['boardCategory'] ?? '').toString();
          final hasCategory =
              (data['boardCategory'] ?? data['boardCategoryLabel'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty;
          final occasion = (data['occasion'] ?? '').toString().toLowerCase();
          return boardCategory == 'custom' ||
              (!hasCategory && !_excludedMainCategories.contains(occasion));
        }),
      ];

      final Set<String> uniqueCategories = {};
      final List<LookItem> loadedLooks = [];

      for (var doc in docs) {
        final occasion =
            doc.data['boardCategoryLabel']?.toString() ??
            doc.data['occasion']?.toString() ??
            'Everything Else';
        if (_excludedMainCategories.contains(occasion.toLowerCase())) continue;

        uniqueCategories.add(occasion);

        final styleIndex =
            occasion.hashCode % (LookBadgeStyle.values.length - 1);
        final dynamicBadge = LookBadgeStyle.values[styleIndex];
        final dynamicBg = LookBgStyle.values[styleIndex];

        // Parse full outfit images (list of items or single imageUrl)
        final rawItems = doc.data['outfitItems'];
        final List<String> outfitImages = [];
        if (rawItems is List) {
          for (final item in rawItems) {
            final url = item is Map
                ? (item['imageUrl'] ?? item['url'] ?? '').toString()
                : item.toString();
            if (url.isNotEmpty) outfitImages.add(url);
          }
        }
        final singleUrl = doc.data['imageUrl']?.toString() ?? '';
        if (outfitImages.isEmpty && singleUrl.isNotEmpty) {
          outfitImages.add(singleUrl);
        }

        loadedLooks.add(
          LookItem(
            id: doc.$id,
            title: (doc.data['title'] ?? occasion).toString(),
            description:
                (doc.data['outfitDescription'] ??
                        'Style board generated for \$occasion')
                    .toString(),
            emoji: '✨',
            category: occasion,
            filter: occasion.toLowerCase(),
            imageUrl: outfitImages.isNotEmpty ? outfitImages.first : null,
            outfitImages: outfitImages,
            badge: dynamicBadge,
            bg: dynamicBg,
          ),
        );
      }

      // Build dynamic filter pills with localized "All" label
      final List<FilterPillData> dynamicFilters = [
        FilterPillData(context.tr('wardrobe_all'), 'all'),
      ];
      for (var cat in uniqueCategories) {
        dynamicFilters.add(FilterPillData(cat, cat.toLowerCase()));
      }

      if (mounted) {
        setState(() {
          _looks = loadedLooks;
          _filters = dynamicFilters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showToast(context.tr('error'));
    }
  }

  List<LookItem> get _filtered => _activeFilter == 'all'
      ? _looks
      : _looks.where((l) => l.filter == _activeFilter).toList();

  void _setFilter(String f) => setState(() => _activeFilter = f);

  Future<void> _deleteLook(String id) async {
    setState(() => _looks.removeWhere((l) => l.id == id));
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.deleteSavedBoard(id);
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final countText = _looks.isEmpty
        ? context.tr('wardrobe_empty_title')
        : '${filtered.length} ${context.tr('fitness_saved')}';

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
              _Header(countText: countText),
              // ── FILTER ROW ──
              _FilterRow(
                filters: _filters,
                activeFilter: _activeFilter,
                onFilter: _setFilter,
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
                      : _looks.isEmpty
                      ? _EmptyState()
                      : filtered.isEmpty
                      ? _NoResultsState()
                      : _LooksGrid(
                          looks: filtered,
                          onDelete: _deleteLook,
                          onShare: (look) =>
                              _showToast(context.tr('wardrobe_share')),
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
  const _Header({required this.countText});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        14,
        MediaQuery.of(context).padding.top + 12,
        14,
        16,
      ),
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
                  text: '${context.tr('boards_everything_else')} ',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
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

// ── Filter Row ───────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final List<FilterPillData> filters;
  final String activeFilter;
  final void Function(String) onFilter;

  const _FilterRow({
    required this.filters,
    required this.activeFilter,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final pill = filters[index];
          final isActive = pill.filter == activeFilter;
          return GestureDetector(
            onTap: () => onFilter(pill.filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? t.accent.primary : t.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? t.accent.primary : t.cardBorder,
                ),
              ),
              child: Center(
                child: Text(
                  pill.label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimary
                        : t.mutedText,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Looks Grid ───────────────────────────────────────────────────────────────
class _LooksGrid extends StatelessWidget {
  final List<LookItem> looks;
  final void Function(String id) onDelete;
  final void Function(LookItem look) onShare;

  const _LooksGrid({
    required this.looks,
    required this.onDelete,
    required this.onShare,
  });

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
      itemCount: looks.length,
      itemBuilder: (context, index) => _LookCard(
        look: looks[index],
        featured: index == 0,
        onDelete: onDelete,
        onShare: onShare,
      ),
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
      default:
        return _t.panel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    const aspectRatio = 1.2; // Uniform aspect ratio for all cards
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
              Stack(
                children: [
                  // Show full outfit: multiple items in a row, or fallback emoji
                  look.outfitImages.isNotEmpty
                      ? AspectRatio(
                          aspectRatio: aspectRatio,
                          child: look.outfitImages.length == 1
                              ? Image.network(
                                  look.outfitImages.first,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                )
                              : Row(
                                  children: look.outfitImages
                                      .take(3)
                                      .map(
                                        (url) => Expanded(
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            height: double.infinity,
                                          ),
                                        ),
                                      )
                                      .toList(),
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
                  // Share & Delete buttons (always visible)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => widget.onShare(look),
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
                                Icons.ios_share_rounded,
                                size: 14,
                                color: _t.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
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
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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

// ── Empty / No-results states ────────────────────────────────────────────────
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
            const Text('🌿', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              context.tr('wardrobe_empty_title'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('wardrobe_insight_empty'),
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

class _NoResultsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              context.tr('diet_no_filter'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('retry'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: t.mutedText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
