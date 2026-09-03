import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appwrite/models.dart' as appwrite_models;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:myapp/app_localizations.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/shareable_outfit_board.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/saved_board_images.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/style_board/saved_board_thumb.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';

class SavedBoardCard extends StatelessWidget {
  final dynamic source;
  final Map<String, Map<String, dynamic>> wardrobeById;
  final VoidCallback? onTap;
  final VoidCallback? onTryOn;

  const SavedBoardCard({
    super.key,
    required this.source,
    required this.wardrobeById,
    this.onTap,
    this.onTryOn,
  });

  Map<String, dynamic> get _data {
    if (source is appwrite_models.Document) {
      return expandSavedBoardData(
        Map<String, dynamic>.from((source as appwrite_models.Document).data),
      );
    }
    if (source is Map) {
      final data = (source as Map)['data'];
      if (data is Map) {
        return expandSavedBoardData(Map<String, dynamic>.from(data));
      }
      return expandSavedBoardData(Map<String, dynamic>.from(source as Map));
    }
    return const {};
  }

  List<Map<String, dynamic>> _itemsForBoard(Map<String, dynamic> data) {
    final savedItems = _savedBoardItems(data);
    if (savedItems.isNotEmpty) {
      return savedItems
          .map(
            (item) => resolveStyleBoardItemImage(
          item,
          wardrobeById,
          surface: 'style_board_saved',
        ),
      )
          .toList(growable: false);
    }

    final ids = <String>[
      ...((data['itemIds'] as List?) ?? const []).map((id) => id.toString()),
      ...((data['item_ids'] as List?) ?? const []).map((id) => id.toString()),
    ].where((id) => id.trim().isNotEmpty).toList();
    final hydrated = ids
        .map((id) => wardrobeById[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (hydrated.isNotEmpty) {
      return hydrated
          .map(
            (item) => resolveStyleBoardItemImage(
          item,
          wardrobeById,
          surface: 'style_board_saved',
        ),
      )
          .toList(growable: false);
    }

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
    return out
        .where(
          (item) =>
      resolveWardrobeImage(
        item,
        surface: 'style_board_saved',
        itemId: wardrobeItemStableId(item),
        emitDiagnostic: false,
      ).url !=
          null,
    )
        .toList();
  }

  void _openDetails(BuildContext context, Map<String, dynamic> data) {
    final shareBoundaryKey = GlobalKey();
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
    final parity = savedBoardReopenParity(data, renderedItems: items);
    debugPrint(
      'AHVI_BOARD_REOPEN_PARITY '
          'board_id=${parity['board_id']} '
          'item_count_match=${parity['item_count_match']} '
          'item_order_match=${parity['item_order_match']} '
          'source_policy_match=${parity['source_policy_match']} '
          'image_provenance_match=${parity['image_provenance_match']} '
          'bucket=${parity['bucket']} '
          'is_favourite=${parity['is_favourite']}',
    );
    debugPrint('saved_board.open boardId=$boardId');
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
                  RepaintBoundary(
                    key: shareBoundaryKey,
                    child: ClipRRect(
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
                  ),
                  const SizedBox(height: 14),
                  if (whyItWorks.isNotEmpty) ...[
                    _DetailSection(
                      title: 'Why it works',
                      body: whyItWorks,
                      tokens: sheetTokens,
                    ),
                    const SizedBox(height: 10),
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
                      isTip: true,
                    ),
                    const SizedBox(height: 14),
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
                          onPressed: () => _shareBoard(
                            sheetContext,
                            shareBoundaryKey,
                            title: title,
                            caption: '$title\n\n$description',
                            occasion: category,
                            whyText: whyItWorks.isNotEmpty
                                ? whyItWorks
                                : description,
                            items: items,
                          ),
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

  /// Captures the boundary at [boundaryKey] as a PNG and shares it as a real
  /// image file via the native share sheet. If the capture fails, the render
  /// object isn't ready yet, or native share is unavailable, falls back to a
  /// text-only share so Share never silently does nothing.
  Future<void> _shareBoard(
      BuildContext context,
      GlobalKey boundaryKey, {
        required String title,
        required String caption,
        required String occasion,
        required String whyText,
        required List<Map<String, dynamic>> items,
      }) async {
    debugPrint('AHVI_SAVED_BOARD_SHARE_TAP');
    try {
      // Prefer the same branded ShareableOutfitBoard template used by the
      // live Style This / AHVI Edit cards (title + occasion + "why it
      // works"), built off-screen so the plain thumbnail is never what gets
      // shared. Only fall back to the plain thumbnail RepaintBoundary if the
      // branded composition can't mount (e.g. no items with images).
      final bytes =
          await _captureShareComposition(
            context,
            title: title,
            occasion: occasion,
            whyText: whyText,
            items: items,
          ) ??
              await _captureBoundaryPng(boundaryKey);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('capture_returned_no_bytes');
      }
      debugPrint('AHVI_SAVED_BOARD_SHARE_CAPTURE_SUCCESS bytes=${bytes.length}');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/ahvi_saved_board_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: caption,
          subject: title,
        ),
      );
      if (result.status == ShareResultStatus.unavailable) {
        throw StateError('native_share_unavailable');
      }
      debugPrint('AHVI_SAVED_BOARD_SHARE_SHEET_OPENED');
    } catch (e) {
      debugPrint('AHVI_SAVED_BOARD_SHARE_FAILED error=$e');
      try {
        final result = await SharePlus.instance.share(
          ShareParams(text: caption, subject: title),
        );
        if (result.status == ShareResultStatus.unavailable) {
          throw StateError('native_share_unavailable');
        }
        debugPrint('AHVI_SAVED_BOARD_SHARE_TEXT_FALLBACK');
      } catch (e2) {
        debugPrint('AHVI_SAVED_BOARD_SHARE_FAILED error=$e2');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the share sheet.')),
          );
        }
      }
    }
  }

  /// Builds the same branded ShareableOutfitBoard used by the live Style
  /// This / AHVI Edit cards (see OutfitActionBar._captureShareComposition in
  /// ahvi_outfit_board_card.dart) off-screen and captures it, so Share from a
  /// saved look produces the identical title + occasion + "why it works"
  /// template rather than a bare outfit thumbnail. Returns null when it
  /// cannot mount (no overlay, or no items with a resolvable image), letting
  /// the caller fall back to the plain thumbnail RepaintBoundary capture.
  Future<Uint8List?> _captureShareComposition(
      BuildContext context, {
        required String title,
        required String occasion,
        required String whyText,
        required List<Map<String, dynamic>> items,
      }) async {
    if (!context.mounted) return null;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    // NOTE: items are already image-validated upstream by _itemsForBoard
    // (via resolveWardrobeImage(...).url != null / extractSavedBoardImages),
    // so we don't re-filter on StyleBoardItem.fromJson(item).displayImageUrl
    // here — a field-name mismatch between the resolved map's keys and what
    // StyleBoardItem.fromJson/.displayImageUrl expect would silently empty
    // this list, drop the whole branded composition, and fall back to the
    // plain thumbnail (which never shows title/occasion/"why this works").
    if (items.isEmpty) return null;
    final boardItems = items
        .map((item) => StyleBoardItem.fromJson(item))
        .toList(growable: false);
    debugPrint(
      'AHVI_SAVED_BOARD_SHARE_COMPOSITION_ITEMS '
          'input_items=${items.length} board_items=${boardItems.length} '
          'why_text_chars=${whyText.trim().length}',
    );
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
              title: title,
              occasion: occasion,
              items: boardItems,
              whyText: whyText,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Let it lay out + paint. Garment images are already in Flutter's
      // image cache from the visible thumbnail, so they resolve within a
      // few frames.
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

  Future<Uint8List?> _captureBoundaryPng(GlobalKey boundaryKey) async {
    // Give the boundary a couple of frames in case an image inside it is
    // still resolving when Share is tapped.
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 3.0);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + thumbnail: tapping anywhere here opens the saved-board
          // preview sheet. Kept as its own GestureDetector (rather than
          // wrapping the whole card) so it doesn't fight with the explicit
          // Try On / View Board buttons below for tap gestures.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onTap?.call();
                _openDetails(context, data);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
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
                          key: const ValueKey('saved-board-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AspectRatio(
                      key: const ValueKey('saved-board-canvas'),
                      aspectRatio: 1,
                      child: SavedBoardThumb(
                        source: source,
                        wardrobeById: wardrobeById,
                        radius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                if (onTryOn != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [t.accent.tertiary, t.accent.primary],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: onTryOn,
                            child: Center(
                              child: Text(
                                context.tr('daily_wear_try_on'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: OutlinedButton(
                      onPressed: () => _openDetails(context, data),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: t.textPrimary,
                        side: BorderSide(color: t.cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'View board',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Label + body treatment mirrors OutfitReasoningStrip (the canonical
// "Why it works" / "Styling tip" presentation on the live Style This card
// in ahvi_outfit_board_card.dart): uppercase caption label in the accent
// color, no boxed background, italic body for the tip variant.
class _DetailSection extends StatelessWidget {
  final String title;
  final String body;
  final AppThemeTokens tokens;
  final bool isTip;

  const _DetailSection({
    required this.title,
    required this.body,
    required this.tokens,
    this.isTip = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: tokens.accent.primary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: TextStyle(
            color: isTip ? tokens.mutedText : tokens.textPrimary,
            fontSize: 13,
            height: isTip ? 1.22 : 1.25,
            fontWeight: FontWeight.w500,
            fontStyle: isTip ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }
}
