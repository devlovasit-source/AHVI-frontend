import 'dart:convert';

import 'package:appwrite/models.dart' as appwrite_models;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:myapp/app_localizations.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/style_board/saved_board_images.dart';
import 'package:myapp/style_board/saved_board_thumb.dart';
import 'package:myapp/theme/theme_tokens.dart';

class SavedBoardCard extends StatelessWidget {
  final dynamic source;
  final Map<String, Map<String, dynamic>> wardrobeById;
  final VoidCallback? onTap;

  const SavedBoardCard({
    super.key,
    required this.source,
    required this.wardrobeById,
    this.onTap,
  });

  Map<String, dynamic> get _data {
    if (source is appwrite_models.Document) {
      return Map<String, dynamic>.from(
        (source as appwrite_models.Document).data,
      );
    }
    if (source is Map) {
      final data = (source as Map)['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(source as Map);
    }
    return const {};
  }

  List<Map<String, dynamic>> _itemsForBoard(Map<String, dynamic> data) {
    final ids = <String>[
      ...((data['itemIds'] as List?) ?? const []).map((id) => id.toString()),
      ...((data['item_ids'] as List?) ?? const []).map((id) => id.toString()),
    ].where((id) => id.trim().isNotEmpty).toList();
    final hydrated = ids
        .map((id) => wardrobeById[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (hydrated.isNotEmpty) return hydrated;

    final savedItems = _savedBoardItems(data);
    if (savedItems.isNotEmpty) return savedItems;

    final extractedImages = extractSavedBoardImages(data);
    if (extractedImages.length >= 2) {
      return [
        for (var i = 0; i < extractedImages.length; i++)
          {
            'id': 'saved-board-image-$i',
            'name': 'Item ${i + 1}',
            'imageUrl': extractedImages[i],
          },
      ];
    }
    return const [];
  }

  List<Map<String, dynamic>> _savedBoardItems(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    void addItems(Object? raw) {
      Object? items = raw;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          items = jsonDecode(raw);
        } catch (_) {
          items = null;
        }
      }
      if (items is! Iterable) return;
      for (final item in items) {
        if (item is Map) out.add(Map<String, dynamic>.from(item));
      }
    }

    Object? payload(Object? raw) {
      if (raw is Map) return raw;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          return decoded is Map ? decoded : null;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    addItems(data['outfitItems']);
    addItems(data['items']);
    final snakePayload = payload(data['board_payload']);
    if (snakePayload is Map) addItems(snakePayload['items']);
    final camelPayload = payload(data['boardPayload']);
    if (camelPayload is Map) addItems(camelPayload['items']);
    return out.where((item) {
      final url =
          (item['imageUrl'] ??
                  item['image_url'] ??
                  item['masked_url'] ??
                  item['maskedUrl'] ??
                  item['url'] ??
                  item['thumbnailUrl'])
              ?.toString()
              .trim() ??
          '';
      return url.isNotEmpty;
    }).toList();
  }

  void _openDetails(BuildContext context, Map<String, dynamic> data) {
    final boardId = _boardId();
    final title = (data['title'] ?? data['boardCategoryLabel'] ?? 'Saved look')
        .toString();
    final category = (data['boardCategoryLabel'] ?? data['occasion'] ?? 'Saved')
        .toString();
    final description = _firstText(data, const [
      'whyItWorks',
      'why_it_works',
      'explanation',
      'outfitDescription',
      'description',
    ], fallback: 'AHVI saved style board');
    final whyItWorks = _firstText(data, const [
      'whyItWorks',
      'why_it_works',
      'explanation',
      'outfitDescription',
    ]);
    final stylingTip = _firstText(data, const [
      'stylingTip',
      'styling_tip',
      'styleTip',
      'tip',
    ]);
    final items = _itemsForBoard(data);
    debugPrint('saved_board.open boardId=$boardId');
    debugPrint('saved_board.payload keys=${data.keys.toList()}');
    debugPrint('saved_board.items count=${items.length}');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final sheetTokens = sheetContext.themeTokens;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: sheetTokens.panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: sheetTokens.cardBorder),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 120),
                          decoration: BoxDecoration(
                            color: sheetTokens.cardBorder,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(Icons.close, color: sheetTokens.textPrimary),
                      ),
                    ],
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      color: sheetTokens.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category,
                    style: TextStyle(
                      color: sheetTokens.accent.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 340,
                      width: double.infinity,
                      child: SavedBoardThumb(
                        source: source,
                        wardrobeById: wardrobeById,
                        radius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (whyItWorks.isNotEmpty) ...[
                    _DetailSection(
                      title: 'Why it works',
                      body: whyItWorks,
                      tokens: sheetTokens,
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text(
                      description,
                      style: TextStyle(
                        color: sheetTokens.mutedText,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (stylingTip.isNotEmpty) ...[
                    _DetailSection(
                      title: 'Styling tip',
                      body: stylingTip,
                      tokens: sheetTokens,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Items in this look',
                    style: TextStyle(
                      color: sheetTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Text(
                      'No item details are attached to this saved board.',
                      style: TextStyle(color: sheetTokens.mutedText),
                    )
                  else
                    ...items.map((item) {
                      final name =
                          (item['name'] ?? item['title'] ?? 'Wardrobe item')
                              .toString();
                      final category =
                          (item['category'] ??
                                  item['sub_category'] ??
                                  item['subcategory'] ??
                                  item['type'] ??
                                  'Item')
                              .toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: sheetTokens.accent.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: sheetTokens.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              category,
                              style: TextStyle(
                                color: sheetTokens.mutedText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await SharePlus.instance.share(
                              ShareParams(
                                text: '$title\n\n$description',
                                subject: title,
                              ),
                            );
                          },
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: boardId.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await Provider.of<AppwriteService>(
                                      context,
                                      listen: false,
                                    ).deleteSavedBoard(boardId);
                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Saved look deleted'),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (sheetContext.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not delete saved look',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
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

  String _boardId() {
    if (source is appwrite_models.Document) {
      return (source as appwrite_models.Document).$id;
    }
    if (source is Map) {
      final map = source as Map;
      return (map[r'$id'] ?? map['id'] ?? '').toString();
    }
    return '';
  }

  String _firstText(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value is Map) {
        final nested = _firstText(Map<String, dynamic>.from(value), const [
          'summary',
          'headline',
          'why',
          'tip',
        ]);
        if (nested.isNotEmpty) return nested;
      }
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final data = _data;
    final category = (data['boardCategoryLabel'] ?? data['occasion'] ?? 'Saved')
        .toString();
    final title = (data['title'] ?? category).toString();
    final description =
        (data['outfitDescription'] ??
                data['description'] ??
                'AHVI saved style board')
            .toString();
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return GestureDetector(
      onTap: () {
        onTap?.call();
        _openDetails(context, data);
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: SavedBoardThumb(
                source: source,
                wardrobeById: wardrobeById,
                radius: BorderRadius.zero,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.accent.primary,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.mutedText,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SizedBox(
                width: double.infinity,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.accent.tertiary, t.accent.primary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      context.tr('daily_wear_try_on'),
                      style: TextStyle(
                        color: onAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
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

class _DetailSection extends StatelessWidget {
  final String title;
  final String body;
  final AppThemeTokens tokens;

  const _DetailSection({
    required this.title,
    required this.body,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: TextStyle(
              color: tokens.mutedText,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
