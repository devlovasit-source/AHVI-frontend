// ============================================================
// WARDROBE.DART - DUAL R2 UPLOAD + APPWRITE FETCH/SAVE
// ============================================================

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/sequential_upload_controller.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/connectivity_watcher.dart';
import 'package:myapp/services/offline_cache.dart';
import 'package:provider/provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:myapp/widgets/ahvi_item_detail_modal.dart';
import 'package:myapp/util/occasion_normalizer.dart';
import 'package:myapp/util/wardrobe_image_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:myapp/util/wardrobe_image_resolver.dart'
    show ResolvedWardrobeImage, resolveWardrobeImage;

// ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸Ãƒâ€¦Ã‚Â¡ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Backend & Providers

// ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸Ãƒâ€¦Ã‚Â¡ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Appwrite & Minio S3
import 'package:appwrite/appwrite.dart';

// ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸Ãƒâ€¦Ã‚Â¡ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Environment Variables
import 'package:myapp/config/env.dart';

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ COLORS ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬

Color _accent4(AppThemeTokens t) =>
    Color.lerp(t.accent.primary, t.accent.secondary, 0.55)!;

class _OfflineDimmer extends StatelessWidget {
  final Widget child;
  final double offlineOpacity;
  const _OfflineDimmer({required this.child, this.offlineOpacity = 0.4});

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityWatcher>().isOnline;
    return AnimatedOpacity(
      opacity: online ? 1.0 : offlineOpacity,
      duration: const Duration(milliseconds: 180),
      child: child,
    );
  }
}

Color _accent5(AppThemeTokens t) =>
    Color.lerp(t.accent.secondary, t.accent.tertiary, 0.55)!;

Color _bagsChip(AppThemeTokens t) =>
    Color.lerp(t.accent.primary, t.accent.secondary, 0.35)!;
Color _jewelryChip(AppThemeTokens t) =>
    Color.lerp(t.accent.secondary, t.accent.tertiary, 0.35)!;
Color _makeupChip(AppThemeTokens t) =>
    Color.lerp(t.accent.primary, t.accent.tertiary, 0.35)!;
Color _skincareChip(AppThemeTokens t) =>
    Color.lerp(t.accent.tertiary, t.accent.secondary, 0.55)!;

Uint8List _decodeBase64ToBytes(String value) => base64Decode(value);
const Color kTransparent = Colors.transparent;
const int wardrobeMaxItems = 6;
const String wardrobeMaxItemsMessage = 'You can upload a maximum of 6 items.';

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ PUBLIC HELPER ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
void showAddToWardrobeModal(
  BuildContext context, {
  void Function(Map<String, dynamic> item)? onSaved,
}) {
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black54,
    builder: (_) => _AddItemModal(onSave: (item) => onSaved?.call(item)),
  );
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ DATA MODEL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class WardrobeItem {
  final String id;
  String name;
  String cat;
  List<String> occasions;
  String notes;
  int worn;
  bool liked;
  Uint8List? imageBytes;

  // Dual URLs to match your Database
  String? imageUrl; // Raw image URL
  String? maskedUrl; // Processed PNG URL
  String? normalizedUrl; // Premium catalog PNG / centered transparent PNG

  /// Raw backend document/data map so the image resolver can read every
  /// canonical URL field (catalog/board/cutout/rmbg/...) without new typed
  /// fields per variant.
  Map<String, dynamic> raw;

  WardrobeItem({
    required this.id,
    required this.name,
    required this.cat,
    required this.occasions,
    this.notes = '',
    this.worn = 0,
    this.liked = false,
    this.imageBytes,
    this.imageUrl,
    this.maskedUrl,
    this.normalizedUrl,
    this.raw = const <String, dynamic>{},
  });

  ResolvedWardrobeImage resolveImage({String surface = 'wardrobe'}) =>
      resolveWardrobeImage(
        raw,
        normalizedUrl: normalizedUrl,
        imageUrl: imageUrl,
        maskedUrl: maskedUrl,
        surface: surface,
        itemId: id,
      );

  String? get displayUrl => resolveImage().url;
}

/// Pure decision helpers for the async-catalog post-save refresh, split out so
/// the state machine is unit-testable without a live Appwrite or widget.
class WardrobeCatalogRefresh {
  const WardrobeCatalogRefresh._();

  /// A catalog is "resolved" (stop refreshing) once its doc reports a terminal
  /// catalog_status. Empty/absent or 'catalog_pending' means still processing.
  static bool isResolved(Map<String, dynamic> raw) {
    final s = (raw['catalog_status'] ?? raw['catalogStatus'] ?? '')
        .toString()
        .trim();
    return s.isNotEmpty && s != 'catalog_pending';
  }

  /// Subset of [ids] whose matching item in [items] has a terminal
  /// catalog_status (catalog_generated / catalog_ready / catalog_failed).
  static Set<String> resolvedIds(List<WardrobeItem> items, Set<String> ids) {
    final byId = {for (final w in items) w.id: w};
    return ids.where((id) {
      final w = byId[id];
      return w != null && isResolved(w.raw);
    }).toSet();
  }
}

String _cleanUiText(Object? value, {String fallback = ''}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return fallback;
  final looksCorrupt =
      raw.contains('\\u00c3') ||
      raw.contains('\\u00c2') ||
      raw.contains('\\u00e2\\u20ac') ||
      raw.contains('\\ufffd');
  if (!looksCorrupt) return raw;
  final cleaned = raw
      .replaceAll(RegExp(r'[^\x20-\x7E]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isNotEmpty ? cleaned : fallback;
}

Map<String, dynamic> _cachedImageMetadata(Map<String, dynamic> raw) {
  const keys = <String>[
    'board_image_url',
    'boardImageUrl',
    'transparent_image_url',
    'transparentImageUrl',
    'cutout_url',
    'cutoutUrl',
    'rmbg_url',
    'rmbgUrl',
    'catalog_image_url',
    'catalogImageUrl',
    'board_status',
    'boardStatus',
    'cutout_status',
    'cutoutStatus',
    'image_status',
    'imageStatus',
    'validation_status',
    'validationStatus',
    'source',
  ];
  return <String, dynamic>{
    for (final key in keys)
      if (raw[key] != null) key: raw[key],
  };
}

List<String> _categoryTokens(Object? value) {
  final raw = _cleanUiText(value).toLowerCase();
  if (raw.isEmpty) return const [];
  return raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
}

bool _hasAnyCategoryToken(List<String> tokens, List<String> words) {
  return words.any(tokens.contains);
}

String _cleanCategory(Object? value, {String fallback = 'Tops'}) {
  final raw = _cleanUiText(value, fallback: fallback);
  const allowed = {
    'All',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Footwear',
    'Dresses',
    'Accessories',
    'Bags',
    'Jewelry',
    'Makeup',
    'Skincare',
    'Needs Review',
  };

  if (allowed.contains(raw)) {
    return raw;
  }

  final tokens = _categoryTokens(raw);

  // Tops first: "Short-Sleeved Shirt" must be Tops.
  if (_hasAnyCategoryToken(tokens, [
    'shirt',
    'shirts',
    'tee',
    'tshirt',
    'tshirts',
    'top',
    'tops',
    'blouse',
    'blouses',
    'hoodie',
    'hoodies',
    'sweater',
    'sweaters',
    'kurta',
    'kurtas',
    'polo',
    'polos',
  ])) {
    return 'Tops';
  }

  // Only "shorts", never "short".
  if (_hasAnyCategoryToken(tokens, [
    'pants',
    'pant',
    'trousers',
    'trouser',
    'jeans',
    'jean',
    'shorts',
    'skirt',
    'skirts',
    'legging',
    'leggings',
    'chino',
    'chinos',
  ])) {
    return 'Bottoms';
  }

  if (_hasAnyCategoryToken(tokens, [
    'shoe',
    'shoes',
    'boot',
    'boots',
    'sneaker',
    'sneakers',
    'heel',
    'heels',
    'sandal',
    'sandals',
    'loafer',
    'loafers',
    'slipper',
    'slippers',
  ])) {
    return 'Footwear';
  }

  if (_hasAnyCategoryToken(tokens, ['watch', 'watches'])) {
    return 'Accessories';
  }

  if (_hasAnyCategoryToken(tokens, [
    'bag',
    'bags',
    'purse',
    'tote',
    'clutch',
    'backpack',
  ])) {
    return 'Bags';
  }

  if (_hasAnyCategoryToken(tokens, [
    'jewelry',
    'jewellery',
    'jewel',
    'ring',
    'rings',
    'necklace',
    'bracelet',
    'earring',
    'earrings',
  ])) {
    return 'Jewelry';
  }

  if (_hasAnyCategoryToken(tokens, [
    'belt',
    'belts',
    'scarf',
    'scarves',
    'accessory',
    'accessories',
    'hat',
    'cap',
    'sunglass',
    'sunglasses',
  ])) {
    return 'Accessories';
  }

  if (_hasAnyCategoryToken(tokens, [
    'jacket',
    'coat',
    'blazer',
    'outerwear',
    'cardigan',
    'overshirt',
  ])) {
    return 'Outerwear';
  }

  if (_hasAnyCategoryToken(tokens, [
    'dress',
    'dresses',
    'gown',
    'jumpsuit',
    'saree',
    'lehenga',
    'sherwani',
  ])) {
    return 'Dresses';
  }

  return fallback;
}

Future<void> shareGarmentImage({
  required String name,
  required String category,
  Uint8List? imageBytes,
  String? imageUrl,
  List<String>? occasions,
  String? notes,
}) async {
  final occasionText = (occasions != null && occasions.isNotEmpty)
      ? '\nOccasions: ${_cleanStringList(occasions).join(', ')}'
      : '';

  final notesText = (notes != null && _cleanUiText(notes).isNotEmpty)
      ? '\nNotes: ${_cleanUiText(notes)}'
      : '';

  final shareText =
      '${_cleanUiText(name, fallback: 'Garment Item')}\n'
      'Category: ${_cleanCategory(category)}'
      '$occasionText'
      '$notesText';

  try {
    Uint8List? bytes = imageBytes;
    if ((bytes == null || bytes.isEmpty) &&
        imageUrl != null &&
        imageUrl.isNotEmpty) {
      final resp = await http.get(Uri.parse(imageUrl));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        bytes = resp.bodyBytes;
      }
    }

    if (bytes != null && bytes.isNotEmpty) {
      final tempDir = await getTemporaryDirectory();
      final safeName = name
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          .toLowerCase();
      final file = File(
        '${tempDir.path}/garment_${safeName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: shareText,
        subject: name,
      );
      return;
    }
  } catch (e) {
    debugPrint('AHVI_GARMENT_SHARE_ERROR: $e');
  }

  await Share.share(shareText, subject: name);
}

List<String> _cleanStringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => _cleanUiText(item))
      .where((item) => item.isNotEmpty)
      .toList();
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ WARDROBE SCREEN ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _activeCat = 'All';
  int _activeTab = 0;
  String _searchQuery = '';
  final List<WardrobeItem> _wardrobe = [];
  final Set<String> _wearLoggingIds = {};

  String? _currentUserId;
  bool _loadedCache = false;
  // One-shot guard: avoids stacking silent refreshes after save.
  bool _silentWardrobeRefreshScheduled = false;

  // WARDROBE_ASYNC_CATALOG: the backend saves an uploaded item with its cutout
  // and patches normalized_url + catalog_status -> catalog_generated ~40s later
  // in a background task. These drive ONE delayed refetch (+ one bounded retry)
  // so the finished catalog image replaces the cutout on the same card without a
  // manual reopen. Cleared in dispose() so the refresh stops on back-nav.
  bool _catalogRefreshScheduled = false;
  final Set<String> _pendingCatalogIds = {};

  bool _isLoading =
      true; // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Loader state for initial fetch

  AppThemeTokens get t => context.themeTokens;
  final FocusNode _keyboardFocusNode = FocusNode();

  // P0.21: external screens (Home, DailyWear, chat prompt bar) that add a
  // wardrobe item via showAddToWardrobeModal cannot reach this screen's
  // private state directly, so they signal completion through the existing
  // shared AppwriteService.invalidateWardrobeCache() notifier instead. This
  // screen listens for that and reconciles by calling the existing
  // _fetchWardrobeItems() — debounced so a multi-item sequential batch
  // (each successful item bumps the generation once) coalesces into one
  // fetch instead of one per item.
  int _lastSeenWardrobeGeneration = 0;
  Timer? _wardrobeInvalidationDebounce;

  void _onAppwriteServiceChanged() {
    final current = AppwriteService().wardrobeGeneration;
    if (current == _lastSeenWardrobeGeneration) return;
    _lastSeenWardrobeGeneration = current;
    _wardrobeInvalidationDebounce?.cancel();
    _wardrobeInvalidationDebounce = Timer(
      const Duration(milliseconds: 400),
      () {
        if (mounted) _fetchWardrobeItems();
      },
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint('AHVI_WARDROBE_NAV route_entry scope=wardrobe');
    _loadCachedWardrobe();
    _fetchWardrobeItems();
    _lastSeenWardrobeGeneration = AppwriteService().wardrobeGeneration;
    AppwriteService().addListener(_onAppwriteServiceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Detect user-switch (Abhinav -> Kavya on same device) and purge stale
    // wardrobe state before re-fetching for the new user.
    // FIX: listen: false prevents didChangeDependencies from firing on every
    // AppwriteService notification (was triggering redundant _fetchWardrobeItems
    // calls during back-swipe transitions and overwhelming the main thread).
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final cachedUser = appwrite.cachedUserProfileData;
    final newUid =
        (cachedUser != null
                ? (cachedUser['userId'] ?? cachedUser['\$id'] ?? '')
                : '')
            .toString()
            .trim();
    if (newUid.isEmpty) return;
    if (_currentUserId != null && _currentUserId != newUid) {
      // Different authed user than last build. Hard reset.
      setState(() {
        _wardrobe.clear();
        _loadedCache = false;
        _isLoading = true;
        _currentUserId = newUid;
      });
      // Async kick-off; ignored (errors handled inside).
      _loadCachedWardrobe(userId: newUid);
      _fetchWardrobeItems();
    }
  }

  // Legacy global key — kept only for one-shot cleanup. Never read; deleted
  // on first cache touch so old installs do not leak previous-user data into
  // the next signed-in user's view.
  static const String _wardrobeCacheGlobalKeyLegacy =
      'ahvi_wardrobe_cache_global';

  String _wardrobeCacheUserKey(String userId) => 'ahvi_wardrobe_cache_$userId';

  Map<String, dynamic> _itemToCacheJson(WardrobeItem item) => {
    'id': item.id,
    'name': _cleanUiText(item.name, fallback: 'Item'),
    'cat': _cleanCategory(item.cat),
    'occasions': _cleanStringList(item.occasions),
    'notes': _cleanUiText(item.notes),
    'worn': item.worn,
    'liked': item.liked,
    'imageUrl': item.imageUrl,
    'maskedUrl': item.maskedUrl,
    'normalizedUrl': item.normalizedUrl,
    'imageMetadata': _cachedImageMetadata(item.raw),
  };

  WardrobeItem? _itemFromCacheJson(Map<String, dynamic> data) {
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return WardrobeItem(
      id: id,
      name: _cleanUiText(data['name'], fallback: 'Item'),
      cat: _cleanCategory(data['cat'] ?? data['category']),
      occasions: _cleanStringList(data['occasions']),
      notes: _cleanUiText(data['notes']),
      worn: data['worn'] is int
          ? data['worn'] as int
          : int.tryParse(data['worn']?.toString() ?? '') ?? 0,
      liked: data['liked'] == true,
      imageUrl: data['imageUrl']?.toString() ?? data['image_url']?.toString(),
      maskedUrl:
          data['maskedUrl']?.toString() ?? data['masked_url']?.toString(),
      normalizedUrl:
          data['normalizedUrl']?.toString() ??
          data['normalized_url']?.toString(),
      raw: data['imageMetadata'] is Map
          ? Map<String, dynamic>.from(data['imageMetadata'] as Map)
          : const <String, dynamic>{},
    );
  }

  Future<bool> _loadCachedWardrobe({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // SECURITY: only ever read the user-scoped key. Never fall back to a
      // global cache — that bleeds the previous user's wardrobe to the next
      // user on the same device. Anonymous load = empty list.
      if (userId == null || userId.isEmpty) {
        // Eagerly nuke the legacy global key so it cannot be revived.
        await prefs.remove(_wardrobeCacheGlobalKeyLegacy);
        return false;
      }
      // One-shot cleanup of the legacy global key on every read.
      if (prefs.containsKey(_wardrobeCacheGlobalKeyLegacy)) {
        await prefs.remove(_wardrobeCacheGlobalKeyLegacy);
      }
      final raw = prefs.getString(_wardrobeCacheUserKey(userId));
      if (raw == null || raw.isEmpty) return false;
      // FIX: Run jsonDecode in a background isolate so the main thread is
      // never blocked (large wardrobe cache can be several hundred KB).
      final decoded = await compute(jsonDecode, raw);
      if (decoded is! List) return false;
      final cached = decoded
          .whereType<Map>()
          .map((row) => _itemFromCacheJson(Map<String, dynamic>.from(row)))
          .whereType<WardrobeItem>()
          .toList();
      if (cached.isEmpty) return false;
      if (!mounted) return false;
      setState(() {
        _wardrobe
          ..clear()
          ..addAll(cached);
        _loadedCache = true;
        _isLoading = false;
      });
      return true;
    } catch (e) {
      debugPrint('Failed to load cached wardrobe: $e');
      return false;
    }
  }

  Future<void> _saveWardrobeCache({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = userId ?? _currentUserId;
      if (uid == null || uid.isEmpty) {
        // No authed user -> do not persist. Anonymous writes leak across
        // accounts on the same device.
        return;
      }
      // FIX: Run jsonEncode in a background isolate so the main thread is
      // never blocked (was causing ANR / back-swipe freeze with 100 items).
      final items = _wardrobe.map(_itemToCacheJson).toList();
      final raw = await compute(jsonEncode, items);
      await prefs.setString(_wardrobeCacheUserKey(uid), raw);
      // Belt-and-suspenders: drop the legacy global key on every save.
      if (prefs.containsKey(_wardrobeCacheGlobalKeyLegacy)) {
        await prefs.remove(_wardrobeCacheGlobalKeyLegacy);
      }
    } catch (e) {
      debugPrint('Failed to save cached wardrobe: $e');
    }
  }

  Future<void> _updateOutfitDocument(
    String id,
    Map<String, dynamic> data,
  ) async {
    final client = Client()
        .setEndpoint(Env.appwriteEndpoint)
        .setProject(Env.appwriteProjectId);
    final databases = Databases(client);
    await databases.updateDocument(
      databaseId: Env.appwriteDatabaseId,
      collectionId: Env.outfitsCollection,
      documentId: id,
      data: data,
    );
  }

  Future<bool> _markWoreToday(WardrobeItem item) async {
    if (!_wearLoggingIds.add(item.id)) return false;
    final previousWorn = item.worn;
    setState(() => item.worn++);
    await _saveWardrobeCache();
    try {
      await _updateOutfitDocument(item.id, {'worn': item.worn});
    } catch (e) {
      debugPrint('Failed to persist wear count: $e');
      item.worn = previousWorn;
      if (mounted) setState(() {});
      await _saveWardrobeCache();
      if (mounted) _showToast('Wear was not logged. Please try again.');
      return false;
    } finally {
      _wearLoggingIds.remove(item.id);
    }
    return true;
  }

  // ÃƒÆ’Ã‚Â°Ãƒâ€¦Ã‚Â¸Ãƒâ€¦Ã‚Â¡ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Fetch from Appwrite
  Future<void> _fetchWardrobeItems() async {
    try {
      final client = Client()
          .setEndpoint(Env.appwriteEndpoint)
          .setProject(Env.appwriteProjectId);
      final databases = Databases(client);
      final account = Account(client);

      final user = await account.get();
      _currentUserId = user.$id;
      if (!_loadedCache) {
        await _loadCachedWardrobe(userId: user.$id);
      }

      var response = await databases.listDocuments(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.outfitsCollection,
        queries: [
          Query.equal('userId', user.$id),
          Query.orderDesc('\$createdAt'),
          Query.limit(100),
        ],
      );
      final fetchedItems = response.documents.map((doc) {
        return WardrobeItem(
          id: doc.$id,
          name: _cleanUiText(doc.data['name'], fallback: 'Item'),
          cat: _cleanCategory(doc.data['category']),
          occasions: _cleanStringList(doc.data['occasions']),
          notes: _cleanUiText(doc.data['notes']),
          worn: doc.data['worn'] ?? 0,
          liked: doc.data['liked'] ?? false,
          imageUrl: doc.data['image_url'],
          maskedUrl: doc.data['masked_url'],
          normalizedUrl: doc.data['normalized_url']?.toString(),
          raw: Map<String, dynamic>.from(doc.data),
        );
      }).toList();

      if (mounted) {
        if (fetchedItems.isNotEmpty || !_loadedCache) {
          setState(() {
            _wardrobe.clear();
            _wardrobe.addAll(fetchedItems);
            _loadedCache = fetchedItems.isNotEmpty;
            _isLoading = false;
          });
          await _saveWardrobeCache(userId: user.$id);
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch wardrobe: $e");
      if (!_loadedCache) {
        await _loadCachedWardrobe();
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Kick off the async-catalog refresh once. Ids accumulate in
  // _pendingCatalogIds across saves, so a second save before the timer fires
  // just adds to the same batch instead of stacking timers.
  void _scheduleCatalogRefresh() {
    if (_catalogRefreshScheduled) return;
    _catalogRefreshScheduled = true;
    Future.delayed(const Duration(seconds: 40), () => _runCatalogRefresh(1));
  }

  // One refetch per attempt; at most two attempts (40s, then +20s). No
  // Timer.periodic. The image swap comes from _fetchWardrobeItems re-pulling the
  // patched normalized_url; catalog_status only decides whether a retry is
  // worthwhile. Stops on: dispose (mounted/flag false), item removed, terminal
  // catalog_status, or the second attempt.
  Future<void> _runCatalogRefresh(int attempt) async {
    if (!mounted || !_catalogRefreshScheduled) {
      _catalogRefreshScheduled = false;
      return;
    }
    // Drop ids the user has since deleted.
    _pendingCatalogIds.removeWhere((id) => !_wardrobe.any((w) => w.id == id));
    if (_pendingCatalogIds.isEmpty) {
      _catalogRefreshScheduled = false;
      return;
    }
    _evictCatalogImages(_pendingCatalogIds);
    try {
      await _fetchWardrobeItems().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('AHVI_ASYNC_CATALOG refresh failed (non-critical): $e');
    }
    if (!mounted) {
      _catalogRefreshScheduled = false;
      return;
    }
    _pendingCatalogIds
      ..removeAll(
        WardrobeCatalogRefresh.resolvedIds(_wardrobe, _pendingCatalogIds),
      )
      ..removeWhere((id) => !_wardrobe.any((w) => w.id == id));
    if (_pendingCatalogIds.isNotEmpty && attempt < 2) {
      Future.delayed(const Duration(seconds: 20), () => _runCatalogRefresh(2));
    } else {
      _catalogRefreshScheduled = false;
      _pendingCatalogIds.clear();
    }
  }

  // Evict the old cutout/raw images so the freshly-fetched catalog URL is not
  // served from Flutter's cache under a reused URL.
  void _evictCatalogImages(Set<String> ids) {
    for (final id in ids) {
      final match = _wardrobe.where((w) => w.id == id);
      if (match.isEmpty) continue;
      final w = match.first;
      for (final url in <String?>{
        w.normalizedUrl,
        w.maskedUrl,
        w.imageUrl,
        w.displayUrl,
      }) {
        if (url != null && url.isNotEmpty) {
          imageCache.evict(NetworkImage(url));
        }
      }
    }
  }

  @override
  void dispose() {
    debugPrint('AHVI_WARDROBE_NAV dispose_started scope=wardrobe');
    // ✅ FIX: Clear image cache to prevent memory buildup on back-nav
    imageCache.clear();
    imageCache.clearLiveImages();

    // ✅ CRITICAL FIX: Cancel pending refresh timer on back-swipe
    // This prevents setState() from firing after the screen is disposed,
    // which was causing the back-swipe freeze
    _silentWardrobeRefreshScheduled = false;
    // Stop any pending async-catalog refetch/retry after back-nav.
    _catalogRefreshScheduled = false;
    _wardrobeInvalidationDebounce?.cancel();
    AppwriteService().removeListener(_onAppwriteServiceChanged);

    _keyboardFocusNode.dispose();
    super.dispose();
    debugPrint('AHVI_WARDROBE_NAV dispose_completed scope=wardrobe');
  }

  void _setCat(String cat) {
    HapticFeedback.selectionClick();
    setState(() => _activeCat = cat);
  }

  void _setTab(int index) {
    HapticFeedback.selectionClick();
    setState(() => _activeTab = index);
  }

  void _openAddModal() {
    final connectivity = Provider.of<ConnectivityWatcher>(
      context,
      listen: false,
    );
    if (!connectivity.isOnline) {
      _showToast('Need internet to add new items');
      return;
    }
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: t.backgroundPrimary.withValues(alpha: 0.7),
      builder: (_) => _AddItemModal(onSave: _handleItemSaved),
    );
  }

  // Post-save handler for the Wardrobe screen's own "+" FAB
  // (_openAddModal). External screens (Home, DailyWear, chat prompt bar)
  // can't call this directly — they signal via AppwriteService's shared
  // invalidation notifier instead (see _onAppwriteServiceChanged above).
  Future<void> _handleItemSaved(Map<String, dynamic> item) async {
    // Optimistic local insert + cache, so the UI feels instant.
    final localItem = WardrobeItem(
      id: item['id'] as String,
      name: _cleanUiText(item['name'], fallback: 'Item'),
      cat: _cleanCategory(item['cat']),
      occasions: _cleanStringList(item['occasions']),
      notes: _cleanUiText(item['notes']),
      imageBytes: item['imageBytes'] as Uint8List?,
      imageUrl: item['imageUrl'] as String?,
      maskedUrl: item['maskedUrl'] as String?,
      normalizedUrl: item['normalizedUrl'] as String?,
      worn: item['worn'] as int? ?? 0,
      liked: item['liked'] as bool? ?? false,
      raw: Map<String, dynamic>.from(item),
    );
    if (mounted) {
      setState(() => _wardrobe.insert(0, localItem));
    }
    await _saveWardrobeCache();

    final alreadySavedRemotely = item['remoteSaved'] == true;
    if (alreadySavedRemotely) {
      if ((item['catalogStatus'] ?? '').toString() == 'catalog_pending') {
        // Deferred catalog (WARDROBE_ASYNC_CATALOG): the card currently
        // shows the cutout; schedule a bounded refetch to swap in the
        // catalog PNG when the background task lands.
        _pendingCatalogIds.add(localItem.id);
        _scheduleCatalogRefresh();
      } else {
        // Recovered from 3308946: the reviewed-item upload-batch save
        // path only returns ADDED_TO_WARDROBE after the canonical row
        // (including normalized_url) is already fully persisted
        // server-side — nothing is pending, so reconcile the
        // optimistic placeholder (still showing the preview-time
        // image) with the real backend row right away instead of
        // leaving it stale until the user manually pulls to refresh.
        // Same canonical fetch _runCatalogRefresh already uses;
        // fire-and-forget so the success toast/modal close isn't
        // blocked on it.
        _fetchWardrobeItems();
      }
      if (mounted) {
        _showToast(AppLocalizations.t(context, 'wardrobe_item_saved'));
      }
      return;
    }

    // Persist to Appwrite. Required schema fields:
    //   userId, name, category, status, image_url, masked_url,
    //   image_id, qdrant_point_id (all required strings).
    // Manual-add items skip server-side Qdrant indexing for now;
    // we reuse the document id as a placeholder so writes succeed.
    try {
      final client = Client()
          .setEndpoint(Env.appwriteEndpoint)
          .setProject(Env.appwriteProjectId);

      final databases = Databases(client);
      final account = Account(client);
      final user = await account.get();

      final imageUrl = (item['imageUrl'] as String?) ?? '';
      final maskedUrl = (item['maskedUrl'] as String?) ?? imageUrl;

      final doc = await databases.createDocument(
        databaseId: Env.appwriteDatabaseId,
        collectionId: Env.outfitsCollection,
        documentId: ID.unique(),
        data: {
          'image_url': imageUrl,
          'category': localItem.cat,
          'userId': user.$id,
          'status': 'active',

          'masked_url': maskedUrl,
          'image_id': localItem.id,
          'masked_id': '${localItem.id}_masked',

          'name': localItem.name,
          'sub_category': localItem.cat,

          'color_code': '#000000',
          'occasions': localItem.occasions,
          'pattern': 'plain',

          'worn': localItem.worn,
          'liked': localItem.liked,
          'qdrant_point_id': localItem.id,
        },
        permissions: [
          Permission.read(Role.user(user.$id)),
          Permission.update(Role.user(user.$id)),
          Permission.delete(Role.user(user.$id)),
        ],
      );

      if (mounted) {
        final savedItem = WardrobeItem(
          id: doc.$id,
          name: _cleanUiText(doc.data['name'], fallback: localItem.name),
          cat: _cleanCategory(doc.data['category']),
          occasions: _cleanStringList(doc.data['occasions']),
          notes: _cleanUiText(doc.data['notes']),
          imageBytes: localItem.imageBytes,
          imageUrl: doc.data['image_url']?.toString(),
          maskedUrl: doc.data['masked_url']?.toString(),
          normalizedUrl: doc.data['normalized_url']?.toString(),
          worn: doc.data['worn'] ?? 0,
          liked: doc.data['liked'] == true,
          raw: Map<String, dynamic>.from(doc.data),
        );

        setState(() {
          // FIXED: Remove the locally-added placeholder and replace with server version
          // The local item has a client UUID, but the server returns doc.$id
          _wardrobe.removeWhere((w) => w.id == localItem.id);
          // Insert the real server item at the top
          _wardrobe.insert(0, savedItem);
        });

        // FIXED: Always trigger a silent refresh after 3 seconds to ensure
        // all images are loaded and any async processing (background removal, etc)
        // is complete. This happens regardless of whether masked URL is used.
        final willSilentRefresh = !_silentWardrobeRefreshScheduled;
        debugPrint(
          'AHVI_WARDROBE_SAVE itemId=${savedItem.id} '
          'scheduleRefresh=$willSilentRefresh',
        );
        if (willSilentRefresh) {
          _silentWardrobeRefreshScheduled = true;
          Future.delayed(const Duration(seconds: 3), () async {
            // ✅ CRITICAL FIX: Check both mounted AND the flag is still set
            // This prevents setState() from firing after back-swipe disposes the screen
            if (!mounted || !_silentWardrobeRefreshScheduled) {
              _silentWardrobeRefreshScheduled = false;
              return;
            }
            try {
              debugPrint('AHVI: Silent wardrobe refresh triggered...');
              await _fetchWardrobeItems().timeout(const Duration(seconds: 8));
            } catch (e) {
              debugPrint('Silent refresh failed (non-critical): $e');
            } finally {
              _silentWardrobeRefreshScheduled = false;
            }
          });
        }

        await _saveWardrobeCache(userId: user.$id);
        if (mounted) {
          Provider.of<AppwriteService>(
            context,
            listen: false,
          ).invalidateWardrobeCache();
        }
        _showToast(AppLocalizations.t(context, 'wardrobe_item_saved'));
      }
    } on AppwriteException catch (e, st) {
      debugPrint('❌ Wardrobe AppwriteException');
      debugPrint('code: ${e.code}');
      debugPrint('type: ${e.type}');
      debugPrint('message: ${e.message}');
      debugPrint('$st');

      if (mounted) {
        setState(() => _wardrobe.removeWhere((w) => w.id == localItem.id));
        await _saveWardrobeCache();
        _showToast('Save failed: ${e.message}');
      }
    } catch (e, st) {
      debugPrint('❌ Wardrobe unknown save failed: $e');
      debugPrint('$st');

      if (mounted) {
        setState(() => _wardrobe.removeWhere((w) => w.id == localItem.id));
        await _saveWardrobeCache();
        _showToast('Save failed. Check logs.');
      }
    }
  }

  List<WardrobeItem> get _filtered {
    final q = _searchQuery.toLowerCase();
    return _wardrobe.where((item) {
      final matchCat = _activeCat == 'All' || item.cat == _activeCat;
      final matchQ =
          q.isEmpty ||
          item.name.toLowerCase().contains(q) ||
          item.cat.toLowerCase().contains(q);
      return matchCat && matchQ;
    }).toList();
  }

  void _openItemDetail(String id) {
    final item = _wardrobe.firstWhere((i) => i.id == id);
    // V2 premium detail modal (Works Well With / Best For / Style This).
    // Callbacks reuse the existing wardrobe handlers; _ItemDetailPanel is kept
    // (unused) as a fallback and is not deleted.
    debugPrint('AHVI_WARDROBE_NAV modal_opened type=item_detail');
    showItemDetailModal(
      context,
      item: item,
      allItems: _wardrobe,
      onWore: _markWoreToday,
      onLike: () {
        setState(() => item.liked = !item.liked);
        _saveWardrobeCache();
        _updateOutfitDocument(item.id, {
          'liked': item.liked,
        }).catchError((_) {});
        _showToast(
          item.liked
              ? 'Added "${item.name}" to favourites'
              : 'Removed from favourites',
        );
      },
      onEdit: () => _showEditSavedItem(item),
      onShare: () => _shareItem(item),
      onRemove: () => _showDeleteConfirm(id),
    ).whenComplete(() {
      debugPrint('AHVI_WARDROBE_NAV modal_dismissal type=item_detail');
    });
  }

  void _showToast(String msg) {
    final t = context.themeTokens;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            color: t.textPrimary,
          ),
        ),
        backgroundColor: t.backgroundSecondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _shareItem(WardrobeItem item) async {
    await shareGarmentImage(
      name: item.name,
      category: item.cat,
      imageBytes: item.imageBytes,
      imageUrl: item.displayUrl,
      occasions: item.occasions,
      notes: item.notes,
    );
  }

  Future<void> _showEditSavedItem(WardrobeItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final notesCtrl = TextEditingController(text: item.notes);
    final occCtrl = TextEditingController(text: item.occasions.join(', '));
    var selectedCat = item.cat.isNotEmpty ? item.cat : 'Tops';
    const cats = [
      'Tops',
      'Bottoms',
      'Outerwear',
      'Footwear',
      'Dresses',
      'Bags',
      'Jewelry',
      'Skincare',
      'Makeup',
      'Innerwear',
      'Accessories',
    ];
    // Migrate legacy 'Indian Wear' / 'Traditional' to Dresses so the
    // existing items still match a visible option.
    if (selectedCat == 'Indian Wear' || selectedCat == 'Traditional') {
      selectedCat = 'Dresses';
    }
    if (!cats.contains(selectedCat)) selectedCat = 'Accessories';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.t(context, 'wardrobe_edit_labels')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.t(
                      context,
                      'wardrobe_input_name',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCat,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.t(
                      context,
                      'wardrobe_input_category',
                    ),
                  ),
                  items: cats
                      .map(
                        (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCat = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.t(
                      context,
                      'wardrobe_input_notes',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: occCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.t(
                      context,
                      'wardrobe_input_occasions',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.t(context, 'wardrobe_btn_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.t(context, 'wardrobe_btn_save')),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final nextName = nameCtrl.text.trim().isEmpty
        ? item.name
        : nameCtrl.text.trim();
    final nextNotes = notesCtrl.text.trim();
    final nextOccasions = occCtrl.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final nextPrivateWear = isPrivateWearText(
      '$nextName $selectedCat ${nextOccasions.join(' ')}',
    );
    if (nextPrivateWear) {
      selectedCat = 'Innerwear';
      nextOccasions
        ..clear()
        ..addAll(['Home', 'Private', 'Lounge']);
    }

    try {
      final backend = Provider.of<BackendService>(context, listen: false);
      debugPrint(
        'AHVI_LABEL_UPDATE item=${item.id} category=$selectedCat '
        'name="$nextName" occasions=${nextOccasions.join(',')}',
      );
      final result = await backend.updateWardrobeLabels(
        itemId: item.id,
        name: nextName,
        category: selectedCat,
        tags: nextOccasions,
      );
      if (result == null) {
        _showToast(AppLocalizations.t(context, 'wardrobe_backend_update_fail'));
        return;
      }
      if (result['success'] != true) {
        final reason =
            (result['detail'] ?? result['error'] ?? result['message'] ?? '')
                .toString();
        debugPrint('AHVI_LABEL_UPDATE_FAIL reason="$reason" raw=$result');
        _showToast(
          reason.isNotEmpty
              ? 'Update failed: $reason'
              : 'Could not update labels. Try again.',
        );
        return;
      }
      setState(() {
        item.name = nextName;
        item.cat = selectedCat;
        item.notes = nextNotes;
        item.occasions = nextOccasions;
      });
      await _saveWardrobeCache();
      await _fetchWardrobeItems();
      _showToast(AppLocalizations.t(context, 'wardrobe_labels_updated'));
    } catch (e, st) {
      debugPrint('AHVI_LABEL_UPDATE_EXCEPTION err=$e');
      debugPrint('AHVI_LABEL_UPDATE_EXCEPTION stack=$st');
      _showToast('Could not update labels: $e');
    }
  }

  Map<String, dynamic> _wardrobeItemDeletePayload(WardrobeItem item) {
    return {
      'id': item.id,
      'item_id': item.id,
      'document_id': item.id,
      'name': item.name,
      'category': item.cat,
      'image_url': item.maskedUrl ?? item.imageUrl,
      'imageUrl': item.maskedUrl ?? item.imageUrl,
      'masked_url': item.maskedUrl ?? item.imageUrl,
      'maskedUrl': item.maskedUrl ?? item.imageUrl,
    };
  }

  Future<bool> _deleteWardrobeItemPersistently(WardrobeItem item) async {
    final result = await BackendService().deleteWardrobeItems([
      _wardrobeItemDeletePayload(item),
    ], deleteR2: true);

    if (result == null) return false;

    final success = result['success'] == true;
    final deletedCount = int.tryParse('${result['deleted_count'] ?? 0}') ?? 0;
    final errorCount = int.tryParse('${result['error_count'] ?? 0}') ?? 0;

    return success || (deletedCount > 0 && errorCount == 0);
  }

  void _showDeleteConfirm(String id) {
    final connectivity = Provider.of<ConnectivityWatcher>(
      context,
      listen: false,
    );
    if (!connectivity.isOnline) {
      _showToast('Need internet to delete items');
      return;
    }
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final item = _wardrobe.firstWhere((i) => i.id == id);

    showDialog(
      context: context,
      barrierColor: t.backgroundPrimary.withValues(alpha: 0.7),
      builder: (_) => AlertDialog(
        backgroundColor: t.backgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppLocalizations.t(context, 'wardrobe_remove_confirm'),
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        content: Text(
          'Remove "${item.name}" from your wardrobe? This will delete it from cloud storage too.',
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            color: t.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              AppLocalizations.t(context, 'cancel'),
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                color: t.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final appwriteService = Provider.of<AppwriteService>(
                context,
                listen: false,
              );
              final offlineCache = Provider.of<OfflineCache>(
                context,
                listen: false,
              );
              Navigator.of(context).pop();

              try {
                final deleted = await _deleteWardrobeItemPersistently(item);

                if (!deleted) {
                  if (!mounted) return;
                  _showToast(
                    'Could not remove "${item.name}" from cloud. Please try again.',
                  );
                  return;
                }

                if (!mounted) return;
                setState(() => _wardrobe.removeWhere((i) => i.id == id));
                await _saveWardrobeCache();
                appwriteService.invalidateWardrobeCache();
                await offlineCache.removeWardrobeItem(
                  item.id,
                  deleteImages: true,
                );
                _showToast('"${item.name}" removed');
              } catch (e) {
                if (!mounted) return;
                _showToast(
                  'Could not remove "${item.name}". Please try again.',
                );
              }
            },
            child: Text(
              AppLocalizations.t(context, 'wardrobe_remove'),
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                color: accent4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAskAhviFab() {
    return _AskAhviFab(
      onTap: () => showAhviStylistChatSheet(context, moduleContext: 'wardrobe'),
    );
  }

  void _openLensSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WardrobeLensSheet(t: t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus:
          false, // Prevents stealing focus globally in IndexedStack, which breaks back swipes
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: t.backgroundPrimary,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 96),
          child: _buildAskAhviFab(),
        ),
        body: Column(
          children: [
            _AppHeader(
              title: _activeTab == 0
                  ? AppLocalizations.t(context, 'wardrobe_title')
                  : AppLocalizations.t(context, 'wardrobe_insights'),
              activeTab: _activeTab,
              onTabTap: _setTab,
              onAddTap: _openAddModal,
              onSearch: (q) => setState(() => _searchQuery = q),
            ),
            if (_activeTab == 0)
              _FilterBar(activeCat: _activeCat, onCatTap: _setCat),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: t.accent.primary),
                    )
                  : _activeTab == 0
                  ? _WardrobePanel(
                      items: _filtered,
                      allEmpty: _wardrobe.isEmpty,
                      onAddTap: _openAddModal,
                      wardrobe: _wardrobe,
                      onDelete: (id) => _showDeleteConfirm(id),
                      onToggleLike: (id) {
                        HapticFeedback.selectionClick();
                        final i = _wardrobe.firstWhere((e) => e.id == id);
                        setState(() => i.liked = !i.liked);
                        _saveWardrobeCache();
                        _updateOutfitDocument(i.id, {
                          'liked': i.liked,
                        }).catchError((_) {});
                        _showToast(
                          i.liked
                              ? 'Added "${i.name}" to favourites'
                              : 'Removed from favourites',
                        );
                      },
                      onWore: (id) {
                        final i = _wardrobe.firstWhere((e) => e.id == id);
                        _markWoreToday(i);
                      },
                      onShare: (id) {
                        final i = _wardrobe.firstWhere((e) => e.id == id);
                        _shareItem(i);
                      },
                      onTapCard: _openItemDetail,
                      onRefresh: () async {
                        await _fetchWardrobeItems();
                      },
                    )
                  : _StatsPanel(wardrobe: _wardrobe),
            ),
          ],
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ ITEM DETAIL PANEL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _ItemDetailPanel extends StatefulWidget {
  final WardrobeItem item;
  final VoidCallback onWore;
  final VoidCallback onToggleLike;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  const _ItemDetailPanel({
    required this.item,
    required this.onWore,
    required this.onToggleLike,
    required this.onDelete,
    required this.onEdit,
    required this.onShare,
  });

  @override
  State<_ItemDetailPanel> createState() => _ItemDetailPanelState();
}

class _ItemDetailPanelState extends State<_ItemDetailPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _slideCtrl,
            curve: const Cubic(0.2, 0.8, 0.3, 1.0),
          ),
        );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: const Cubic(0.2, 0.8, 0.3, 1.0),
      ),
    );
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  static String _catEmoji(String cat) =>
      const {
        'Tops': 'TOP',
        'Bottoms': 'BOT',
        'Outerwear': 'OUT',
        'Footwear': 'SHO',
        'Dresses': 'DRS',
        'Accessories': 'ACC',
        'Bags': 'BAG',
        'Jewelry': 'JWL',
        'Makeup': 'MKP',
        'Skincare': 'SKN',
      }[cat] ??
      'ITM';

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final item = widget.item;
    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        backgroundColor: kTransparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: SlideTransition(
          position: _slideAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              decoration: BoxDecoration(
                color: t.backgroundSecondary,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: t.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: t.backgroundPrimary.withValues(alpha: 0.5),
                    blurRadius: 80,
                    offset: const Offset(0, 40),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Close row ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: t.panel,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.cardBorder),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: t.mutedText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Title ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ),
                  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Meta row ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: t.accent.secondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.cat,
                            style: TextStyle(
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontSize: 12,
                              color: t.accent.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.worn == 0
                              ? AppLocalizations.t(
                                  context,
                                  'wardrobe_never_worn',
                                )
                              : 'Worn ${item.worn}',
                          style: TextStyle(
                            fontFamily: GoogleFonts.inter().fontFamily,
                            fontSize: 13,
                            color: t.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Body ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  height: 180,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        t.accent.primary.withValues(
                                          alpha: 0.15,
                                        ),
                                        t.accent.secondary.withValues(
                                          alpha: 0.12,
                                        ),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    image: item.displayUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                              item.displayUrl!,
                                            ),
                                            fit: BoxFit.contain,
                                          )
                                        : (item.imageBytes != null
                                              ? DecorationImage(
                                                  image: MemoryImage(
                                                    item.imageBytes!,
                                                  ),
                                                  fit: BoxFit.contain,
                                                )
                                              : null),
                                  ),
                                  child:
                                      (item.displayUrl == null &&
                                          item.imageBytes == null)
                                      ? Center(
                                          child: Text(
                                            _catEmoji(item.cat),
                                            style: const TextStyle(
                                              fontSize: 56,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: t.panel,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _DetailInfoRow(
                                        label: AppLocalizations.t(
                                          context,
                                          'wardrobe_category',
                                        ),
                                        value: item.cat,
                                      ),
                                      const SizedBox(height: 10),
                                      _DetailInfoRow(
                                        label: AppLocalizations.t(
                                          context,
                                          'wardrobe_times_worn',
                                        ),
                                        value: '${item.worn}',
                                      ),
                                      if (item.notes.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        _DetailInfoRow(
                                          label: AppLocalizations.t(
                                            context,
                                            'wardrobe_notes',
                                          ),
                                          value: item.notes,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.occasions.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: item.occasions
                                  .map(
                                    (o) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.panel,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: t.cardBorder),
                                      ),
                                      child: Text(
                                        o,
                                        style: TextStyle(
                                          fontFamily:
                                              GoogleFonts.inter().fontFamily,
                                          fontSize: 12,
                                          color: t.mutedText,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                  ),
                  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Action buttons ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.cardBorder)),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HoverTintButton(
                          label: AppLocalizations.t(
                            context,
                            'wardrobe_wore_today',
                          ),
                          bgColor: t.accent.tertiary.withValues(alpha: 0.12),
                          hoverBgColor: t.accent.tertiary.withValues(
                            alpha: 0.22,
                          ),
                          fgColor: t.accent.tertiary,
                          onTap: widget.onWore,
                        ),
                        StatefulBuilder(
                          builder: (ctx, setSt) => _HoverTintButton(
                            label: item.liked
                                ? AppLocalizations.t(context, 'wardrobe_liked')
                                : AppLocalizations.t(context, 'wardrobe_like'),
                            bgColor: item.liked
                                ? accent4.withValues(alpha: 0.12)
                                : t.panel,
                            hoverBgColor: item.liked
                                ? accent4.withValues(alpha: 0.22)
                                : t.panelBorder,
                            fgColor: item.liked ? accent4 : t.mutedText,
                            onTap: () {
                              widget.onToggleLike();
                              setSt(() {});
                            },
                          ),
                        ),
                        _HoverTintButton(
                          label: 'Edit',
                          bgColor: t.panel,
                          hoverBgColor: t.panelBorder,
                          fgColor: t.textPrimary,
                          onTap: widget.onEdit,
                        ),
                        _HoverTintButton(
                          label: AppLocalizations.t(context, 'wardrobe_share'),
                          bgColor: t.panel,
                          hoverBgColor: t.panelBorder,
                          fgColor: t.textPrimary,
                          onTap: widget.onShare,
                        ),
                        _OfflineDimmer(
                          child: _HoverTintButton(
                            label: AppLocalizations.t(
                              context,
                              'wardrobe_remove',
                            ),
                            bgColor: accent4.withValues(alpha: 0.08),
                            hoverBgColor: accent4.withValues(alpha: 0.18),
                            fgColor: accent4,
                            onTap: widget.onDelete,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverTintButton extends StatefulWidget {
  final String label;
  final Color bgColor;
  final Color hoverBgColor;
  final Color fgColor;
  final VoidCallback onTap;

  const _HoverTintButton({
    required this.label,
    required this.bgColor,
    required this.hoverBgColor,
    required this.fgColor,
    required this.onTap,
  });

  @override
  State<_HoverTintButton> createState() => _HoverTintButtonState();
}

class _HoverTintButtonState extends State<_HoverTintButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBgColor : widget.bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: widget.fgColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: t.mutedText,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 14,
            color: t.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ DETECTED ITEM MODEL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _DetectedItem {
  final String id;
  String name;
  String category;
  String subCategory;
  String? color;
  String? colorCode;
  String? pattern;
  List<String> occasions;
  final String? labelSource;
  final bool requiresManualEntry;
  final double confidence;
  final String? rawUrl;
  final String? maskedUrl;
  final String? maskedImageBase64;
  final int? sourceImageIndex;
  final Map<String, dynamic> raw;
  final String validationStatus;
  final String? rejectionReason;
  final bool selectedByDefault;
  final double? cropQualityScore;
  final String? detectionMode;
  final String? regenProvider;
  final String? inputType;
  bool selected;
  // Set post-construction via the inline notes field (_ItemEditCtrls), not
  // a constructor argument — no detection response carries a starting note.
  String notes = '';

  _DetectedItem({
    required this.id,
    required this.name,
    required this.category,
    this.subCategory = '',
    this.color,
    this.colorCode,
    this.pattern,
    this.occasions = const [],
    this.labelSource,
    this.requiresManualEntry = false,
    this.confidence = 0,
    this.rawUrl,
    this.maskedUrl,
    this.maskedImageBase64,
    this.sourceImageIndex,
    this.raw = const {},
    String validationStatus = 'ok',
    this.rejectionReason,
    bool? selectedByDefault,
    this.cropQualityScore,
    this.detectionMode,
    this.regenProvider,
    this.inputType,
    bool? selected,
  }) : validationStatus = validationStatus.trim().toLowerCase().isEmpty
           ? 'ok'
           : validationStatus.trim().toLowerCase(),
       selectedByDefault =
           (selectedByDefault ??
               validationStatus.trim().toLowerCase() == 'ok') &&
           !_duplicateSignal(raw),
       selected =
           selected ??
           ((selectedByDefault ??
                   validationStatus.trim().toLowerCase() == 'ok') &&
               !_duplicateSignal(raw));

  bool get isApproved => validationStatus == 'ok';
  bool get isNeedsReview => validationStatus == 'needs_review';
  bool get isRejected => validationStatus == 'rejected';
  bool get isSaveable => isApproved;
  Map<String, dynamic>? get _duplicateInfo => raw['duplicate'] is Map
      ? Map<String, dynamic>.from(raw['duplicate'] as Map)
      : null;
  bool get isDuplicate => _duplicateSignal(raw);
  String? get duplicateReason => _duplicateInfo?['reason']?.toString();
  String? get matchedItemId => _duplicateInfo?['matched_item_id']?.toString();
  double? get duplicateConfidence {
    final confidence = _duplicateInfo?['confidence'];
    return confidence is num ? confidence.toDouble() : null;
  }

  String? get statusLabel {
    if (isDuplicate) return 'Possible duplicate';
    if (isNeedsReview) return 'Needs review';
    if (isRejected) return 'Rejected';
    return null;
  }

  Uint8List? get maskedImageBytes {
    final encoded = maskedImageBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded.split(',').last);
    } catch (_) {
      return null;
    }
  }

  /// Best inline preview: masked b64 crop, else raw b64 crop from the
  /// backend payload (Gemini multi fast path sends both).
  Uint8List? get previewBytes {
    final masked = maskedImageBytes;
    if (masked != null) return masked;
    final encodedRaw = raw['raw_image_base64']?.toString();
    if (encodedRaw == null || encodedRaw.isEmpty) return null;
    try {
      return base64Decode(encodedRaw.split(',').last);
    } catch (_) {
      return null;
    }
  }

  /// Masked URL first, raw URL as fallback.
  String? get displayUrl {
    final masked = maskedUrl;
    if (masked != null && masked.isNotEmpty) return masked;
    final rawU = rawUrl;
    if (rawU != null && rawU.isNotEmpty) return rawU;
    return null;
  }

  Map<String, dynamic> toBackendPayload() {
    final payload = Map<String, dynamic>.from(raw);
    payload.addAll({
      'item_id': id,
      'name': name,
      'category': category,
      'sub_category': subCategory.isNotEmpty ? subCategory : category,
      'color_name': color,
      'color_code': colorCode,
      'pattern': pattern,
      'occasions': occasions,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      'label_source': labelSource,
      'requires_manual_entry': requiresManualEntry,
      'confidence': confidence,
      'raw_url': rawUrl,
      'masked_url': maskedUrl,
      'masked_image_base64': maskedImageBase64,
      'validation_status': validationStatus,
      'rejection_reason': rejectionReason,
      'selected_by_default': selectedByDefault,
      'crop_quality_score': cropQualityScore,
      'detection_mode': detectionMode,
      'regen_provider': regenProvider,
      'input_type': inputType,
      if (sourceImageIndex != null) 'source_image_index': sourceImageIndex,
    });
    // When the server cached the crop during analyze (image_cache_token present
    // in `raw`), drop the heavy base64 from the save upload — the backend
    // restores the bytes from the token. This collapses a ~MB upload to a few
    // bytes (the big driver of slow saves on weak networks).
    final hasCacheToken =
        (raw['image_cache_token']?.toString().trim().isNotEmpty ?? false);
    if (hasCacheToken) {
      payload.remove('raw_image_base64');
      payload.remove('rawImageBase64');
      payload.remove('masked_image_base64');
      payload.remove('maskedImageBase64');
    }
    return payload;
  }

  static String mapCategory(Object? raw, [Object? subCategory, Object? name]) {
    final s = [raw, subCategory, name]
        .where((v) => v != null)
        .map((v) => v.toString().toLowerCase().trim())
        .where((v) => v.isNotEmpty)
        .join(' ');

    if (s.contains('top') ||
        s.contains('shirt') ||
        s.contains('blouse') ||
        s.contains('tee') ||
        s.contains('t-shirt') ||
        s.contains('tshirt') ||
        s.contains('sweater') ||
        s.contains('hoodie') ||
        s.contains('kurta')) {
      return 'Tops';
    }

    if (s.contains('pant') ||
        s.contains('trouser') ||
        s.contains('jean') ||
        s.contains('short') ||
        s.contains('skirt') ||
        s.contains('legging') ||
        s.contains('leggings') ||
        s.contains('jogger') ||
        s.contains('chino')) {
      return 'Bottoms';
    }

    if (s.contains('jacket') ||
        s.contains('coat') ||
        s.contains('blazer') ||
        s.contains('outer') ||
        s.contains('cardigan')) {
      return 'Outerwear';
    }

    if (s.contains('shoe') ||
        s.contains('shoes') ||
        s.contains('boot') ||
        s.contains('boots') ||
        s.contains('sneaker') ||
        s.contains('sneakers') ||
        s.contains('sandal') ||
        s.contains('sandals') ||
        s.contains('heel') ||
        s.contains('heels') ||
        s.contains('loafer') ||
        s.contains('loafers') ||
        s.contains('slipper') ||
        s.contains('slippers') ||
        s.contains('birkenstock') ||
        s.contains('footwear') ||
        s.contains('oxford')) {
      return 'Footwear';
    }

    if (s.contains('dress') ||
        s.contains('gown') ||
        s.contains('jumpsuit') ||
        s.contains('sari') ||
        s.contains('saree') ||
        s.contains('lehenga')) {
      return 'Dresses';
    }

    if (s.contains('jewelry') ||
        s.contains('jewellery') ||
        s.contains('necklace') ||
        s.contains('chain') ||
        s.contains('pendant') ||
        s.contains('ring') ||
        s.contains('bracelet') ||
        s.contains('bangle') ||
        s.contains('earring') ||
        s.contains('earrings') ||
        s.contains('hoop') ||
        s.contains('hoops')) {
      return 'Jewelry';
    }

    if (s.contains('bag') ||
        s.contains('purse') ||
        s.contains('clutch') ||
        s.contains('backpack')) {
      return 'Bags';
    }

    if (s.contains('watch') ||
        s.contains('belt') ||
        s.contains('cap') ||
        s.contains('hat') ||
        s.contains('sunglasses') ||
        s.contains('scarf') ||
        s.contains('accessory') ||
        s.contains('accessories')) {
      return 'Accessories';
    }

    if (s.contains('makeup') || s.contains('lipstick')) return 'Makeup';
    if (s.contains('skincare') || s.contains('moisturizer')) return 'Skincare';

    return 'Needs Review';
  }

  static String catEmoji(String cat) =>
      const {
        'Tops': 'TOP',
        'Bottoms': 'BOT',
        'Outerwear': 'OUT',
        'Footwear': 'SHO',
        'Dresses': 'DRS',
        'Accessories': 'ACC',
        'Bags': 'BAG',
        'Jewelry': 'JWL',
        'Makeup': 'MKP',
        'Skincare': 'SKN',
        'Needs Review': 'REV',
      }[cat] ??
      'ITM';
}

bool _duplicateSignal(Map<String, dynamic> raw) {
  final duplicate = raw['duplicate'];
  return duplicate is Map &&
      duplicate['checked'] == true &&
      duplicate['is_duplicate'] == true;
}

/// Whether `value` (name/category/subcategory joined) reads as a private-wear
/// garment. Exposed (non-underscore) and [visibleForTesting] purely so
/// regression tests can prove the backend payload normalization it drives —
/// it is not meant as general public API.
@visibleForTesting
bool isPrivateWearText(String value) {
  final clean = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  const aliases = [
    'boxer',
    'boxer shorts',
    'briefs',
    'brief',
    'underwear',
    'undergarment',
    'innerwear',
    'trunks',
    'sports trunk',
    'compression shorts',
    'compression short',
    'base layer',
    'thermal inner',
    'lingerie',
    'sleep shorts',
    'pajama',
    'pyjama',
    'lounge shorts',
  ];
  return aliases.any((alias) => clean.contains(alias));
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ MODAL STEP ENUM ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _DetectedTaxonomy {
  final String name;
  final String category;
  final String subCategory;
  final bool requiresManualEntry;

  const _DetectedTaxonomy({
    required this.name,
    required this.category,
    required this.subCategory,
    required this.requiresManualEntry,
  });
}

String _taxonomyText(Map<String, dynamic> data) {
  return [
    data['name'],
    data['category'],
    data['sub_category'],
    data['subcategory'],
    data['label'],
    data['garment_type'],
    data['type'],
  ].where((v) => v != null).map((v) => v.toString()).join(' ').toLowerCase();
}

bool _hasAnyText(String text, List<String> words) {
  return words.any((word) => text.contains(word));
}

_DetectedTaxonomy _normalizeDetectedTaxonomy(Map<String, dynamic> data) {
  final text = _taxonomyText(data);
  final rawName = _cleanUiText(data['name'], fallback: 'Review item');
  final confidence = data['confidence'] is num
      ? (data['confidence'] as num).toDouble()
      : 0.0;

  String category = _DetectedItem.mapCategory(text);
  var subCategory = _cleanUiText(data['sub_category']);

  if (_hasAnyText(text, ['sari', 'saree'])) {
    category = 'Dresses';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Saree';
  } else if (_hasAnyText(text, [
    'one-piece',
    'one piece',
    'mini dress',
    'gown',
    'dress',
  ])) {
    category = 'Dresses';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Dress';
  } else if (_hasAnyText(text, ['bag', 'purse', 'tote', 'clutch'])) {
    category = 'Bags';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Bag';
  } else if (_hasAnyText(text, [
    'jewelry',
    'jewellery',
    'ring',
    'bracelet',
    'necklace',
    'earring',
  ])) {
    category = 'Jewelry';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Jewelry';
  } else if (_hasAnyText(text, ['watch'])) {
    category = 'Accessories';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Watch';
  } else if (_hasAnyText(text, ['belt'])) {
    category = 'Accessories';
    subCategory = subCategory.isNotEmpty ? subCategory : 'Belt';
  }

  final lowerName = rawName.toLowerCase();
  final genericUnknown = _hasAnyText(text, [
    'unknown',
    'uncategorized',
    'generic item',
    'item accessories',
  ]);
  final weakAccessory =
      category == 'Accessories' &&
      !_hasAnyText(text, [
        'watch',
        'belt',
        'scarf',
        'hat',
        'cap',
        'sunglass',
        'accessory',
      ]);
  final needsReview =
      genericUnknown ||
      category == 'Needs Review' ||
      (confidence > 0 && confidence < 0.35 && weakAccessory);

  if (needsReview) {
    return _DetectedTaxonomy(
      name: lowerName == 'unknown' || lowerName == 'item'
          ? 'Review item'
          : rawName,
      category: 'Needs Review',
      subCategory: '',
      requiresManualEntry: true,
    );
  }

  return _DetectedTaxonomy(
    name: rawName,
    category: category,
    subCategory: subCategory,
    requiresManualEntry: data['requires_manual_entry'] == true,
  );
}

enum _ModalStep {
  camera,
  detecting,
  reviewing,
  saving,
  success,
  results,
  error,
}

/// Per-item inline-edit controllers for the unified review page. One set is
/// created per detected item (keyed by item id) so multiple items can be
/// edited inline on the same scrollable page without a separate edit step.
class _ItemEditCtrls {
  final TextEditingController name;
  final TextEditingController subCategory;
  final TextEditingController color;
  final TextEditingController pattern;
  final TextEditingController notes;

  _ItemEditCtrls(_DetectedItem item)
    : name = TextEditingController(text: item.name),
      subCategory = TextEditingController(text: item.subCategory),
      color = TextEditingController(text: item.color ?? ''),
      pattern = TextEditingController(text: item.pattern ?? ''),
      notes = TextEditingController(text: item.notes);

  // `onPrivacyFieldChanged` rebuilds the review card so private-wear status
  // (derived from name + subCategory) never goes stale on screen — the other
  // fields don't feed that classification, so they skip the rebuild.
  void bindTo(_DetectedItem item, {VoidCallback? onPrivacyFieldChanged}) {
    name.addListener(() {
      item.name = name.text;
      onPrivacyFieldChanged?.call();
    });
    subCategory.addListener(() {
      item.subCategory = subCategory.text;
      onPrivacyFieldChanged?.call();
    });
    color.addListener(() => item.color = color.text);
    pattern.addListener(() => item.pattern = pattern.text);
    notes.addListener(() => item.notes = notes.text);
  }

  void dispose() {
    name.dispose();
    subCategory.dispose();
    color.dispose();
    pattern.dispose();
    notes.dispose();
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ ADD ITEM MODAL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Camera embedded inside ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _AddOccasionDialog extends StatefulWidget {
  final int maxLength;

  const _AddOccasionDialog({required this.maxLength});

  @override
  State<_AddOccasionDialog> createState() => _AddOccasionDialogState();
}

class _AddOccasionDialogState extends State<_AddOccasionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a tag'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: widget.maxLength,
        maxLines: 1,
        decoration: const InputDecoration(hintText: 'e.g. Beach, Gym'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _AddItemModal extends StatefulWidget {
  final void Function(Map<String, dynamic> item) onSave;
  const _AddItemModal({required this.onSave});

  @override
  State<_AddItemModal> createState() => _AddItemModalState();
}

class _AddItemModalState extends State<_AddItemModal>
    with TickerProviderStateMixin {
  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Modal entry animations ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Camera ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  CameraController? _camCtrl;
  List<CameraDescription> _cameras = [];
  bool _camReady = false;
  bool _isFront = false;
  FlashMode _flash = FlashMode.off;

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Flow state ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  _ModalStep _step = _ModalStep.camera;
  Uint8List? _capturedBytes;
  List<Uint8List> _galleryImages = []; // gallery multi-pick
  bool _isGalleryPick = false;
  List<_DetectedItem> _detected = [];
  String? _detectError;
  bool _isSavingWardrobe = false;
  // Timing: when the detection preview was shown, to measure review-gap.
  DateTime? _previewShownAt;
  // Sanitized, user-safe failure message for the error/retry screen. Never a
  // raw exception/HTTP/JSON/Appwrite string.
  String? _saveError;
  OverlayEntry? _maxItemsOverlay;
  Timer? _maxItemsOverlayTimer;
  Timer? _pickerInputShieldTimer;
  bool _pickerInputShielded = false;

  String? _uploadBatchRequestId;
  SequentialUploadController? _uploadController;
  int _uploadCompletedCount = 0;
  int _uploadTotalCount = 0;
  Map<String, UploadItemResult> _uploadResults = {};
  final Set<String> _addAnywayInFlight = {};
  List<_DetectedItem> _lastSaveAttemptItems = [];

  // Truthful outcome of the last save call, captured from the backend's own
  // saved_count/rows — the success screen must never infer this from the
  // (pre-save) selected-items list, or a partial save would read as a full
  // success.
  int _savedCount = 0;
  int _savedRequestedCount = 0;
  String? _savedSingleName;
  String? _savedSingleColor;
  String? _savedSinglePattern;

  // Inline per-item edit controllers for the unified review page, keyed by
  // detected-item id. Built lazily so edits made before a save failure are
  // preserved verbatim across Retry.
  final Map<String, _ItemEditCtrls> _itemCtrls = {};

  void _showMaxItemsWarning() {
    if (!mounted) return;
    _maxItemsOverlayTimer?.cancel();
    _maxItemsOverlay?.remove();
    _maxItemsOverlay = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: 0,
        left: 16,
        right: 16,
        child: SafeArea(
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: overlayContext.themeTokens.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: overlayContext.themeTokens.cardBorder,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: overlayContext.themeTokens.textPrimary.withValues(
                        alpha: 0.12,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: overlayContext.themeTokens.accent.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        wardrobeMaxItemsMessage,
                        style: TextStyle(
                          color: overlayContext.themeTokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_maxItemsOverlay!);
    _maxItemsOverlayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _maxItemsOverlay?.remove();
      _maxItemsOverlay = null;
      _maxItemsOverlayTimer = null;
    });
  }

  void _removeMaxItemsWarning() {
    _maxItemsOverlayTimer?.cancel();
    _maxItemsOverlayTimer = null;
    _maxItemsOverlay?.remove();
    _maxItemsOverlay = null;
  }

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Edit form ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  static const _cats = [
    'Tops',
    'Bottoms',
    'Outerwear',
    'Footwear',
    'Dresses',
    'Bags',
    'Jewelry',
    'Makeup',
    'Skincare',
    'Innerwear',
    'Accessories',
    'Needs Review',
  ];
  static const _occs = [
    'Everyday',
    'Casual',
    'Work',
    'Dinner',
    'Travel',
    'Sport',
    'Party',
    'Festive',
    'Wedding',
  ];

  // Swipe navigation between review cards (one item per page).
  final PageController _reviewPageCtrl = PageController();
  int _reviewPageIndex = 0;

  _ItemEditCtrls _ctrlsFor(_DetectedItem item) {
    final existing = _itemCtrls[item.id];
    if (existing != null) return existing;
    final created = _ItemEditCtrls(item)
      ..bindTo(
        item,
        onPrivacyFieldChanged: () {
          if (mounted) setState(() {});
        },
      );
    _itemCtrls[item.id] = created;
    return created;
  }

  void _disposeItemCtrls() {
    for (final c in _itemCtrls.values) {
      c.dispose();
    }
    _itemCtrls.clear();
  }

  AppThemeTokens get t => context.themeTokens;

  @override
  void initState() {
    super.initState();
    _initSlideAnim();
    _initCamera();
  }

  void _initSlideAnim() {
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _slideCtrl,
            curve: const Cubic(0.22, 1, 0.36, 1),
          ),
        );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: const Cubic(0.22, 1, 0.36, 1)),
    );
    _slideCtrl.forward();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final cam = _isFront && _cameras.length > 1 ? _cameras[1] : _cameras[0];
      _camCtrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _camCtrl!.initialize();
      await _camCtrl!.setFlashMode(_flash);
      if (mounted) setState(() => _camReady = true);
    } catch (_) {}
  }

  Future<void> _flipCamera() async {
    setState(() {
      _camReady = false;
      _isFront = !_isFront;
    });
    await _camCtrl?.dispose();
    await _initCamera();
  }

  void _shieldInputAfterPickerDismissal() {
    _pickerInputShieldTimer?.cancel();
    if (!mounted) return;
    setState(() => _pickerInputShielded = true);
    _pickerInputShieldTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _pickerInputShielded = false);
      _pickerInputShieldTimer = null;
    });
  }

  Future<void> _toggleFlash() async {
    setState(
      () => _flash = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off,
    );
    await _camCtrl?.setFlashMode(_flash);
  }

  Future<void> _captureAndDetect() async {
    if (!_camReady) return;
    HapticFeedback.mediumImpact();
    try {
      final xfile = await _camCtrl!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();

      // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Camera no longer needed ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â dispose immediately to save battery
      // Null the controller and flip _camReady OFF *before* awaiting dispose,
      // so no frame can build CameraPreview on a disposed controller (that
      // caused a one-frame red "Disposed CameraController" error flash).
      final _ctrlToDispose = _camCtrl;
      _camCtrl = null;
      if (mounted) setState(() => _camReady = false);
      // Dispose AFTER this frame paints — by then CameraPreview is removed from
      // the tree, so it won't rebuild on the dispose notification (which threw
      // "Disposed CameraController" -> a one-frame red flash on teardown).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ctrlToDispose?.dispose();
      });

      setState(() {
        _capturedBytes = bytes;
        _step = _ModalStep.detecting;
        _detectError = null;
      });
      await _runDetection(bytes);
    } catch (_) {
      setState(() => _step = _ModalStep.camera);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        limit: wardrobeMaxItems,
      );
      if (files.isEmpty) {
        _shieldInputAfterPickerDismissal();
        return;
      }
      if (!mounted) return;

      // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Gallery picked ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â camera no longer needed, dispose to save battery
      // Null the controller and flip _camReady OFF *before* awaiting dispose,
      // so no frame can build CameraPreview on a disposed controller (that
      // caused a one-frame red "Disposed CameraController" error flash).
      final _ctrlToDispose = _camCtrl;
      _camCtrl = null;
      if (mounted) setState(() => _camReady = false);
      // Dispose AFTER this frame paints — by then CameraPreview is removed from
      // the tree, so it won't rebuild on the dispose notification (which threw
      // "Disposed CameraController" -> a one-frame red flash on teardown).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ctrlToDispose?.dispose();
      });

      // Warn if user had more than 6 selected (some platforms ignore limit)
      final capped = files.take(wardrobeMaxItems).toList();
      if (files.length > wardrobeMaxItems) _showMaxItemsWarning();

      final bytesList = await Future.wait(capped.map((f) => f.readAsBytes()));
      if (!mounted) return;

      if (bytesList.length == 1) {
        // Single image ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ existing AI detection flow
        setState(() {
          _capturedBytes = bytesList.first;
          _galleryImages = [];
          _isGalleryPick = false;
          _step = _ModalStep.detecting;
          _detectError = null;
        });
        await _runDetection(bytesList.first);
      } else {
        // Multiple images ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ parallel AI detection on all images
        setState(() {
          _capturedBytes = bytesList.first;
          _galleryImages = bytesList;
          _isGalleryPick = true;
          _step = _ModalStep.detecting;
          _detectError = null;
          _detected = [];
        });
        await _runDetectionMulti(bytesList);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detectError = 'Could not load images. Please try again.';
        _step = _ModalStep.reviewing;
        _detected = [];
      });
    }
  }

  // Single image -> returns detected items from the backend visual intelligence route.
  Future<List<_DetectedItem>> _detectOneImage(Uint8List bytes) async {
    final data = await Provider.of<BackendService>(
      context,
      listen: false,
    ).analyzeImage(bytes);
    return _detectedItemsFromAnalyzeResponse(data);
  }

  List<_DetectedItem> _detectedItemsFromAnalyzeResponse(
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      throw Exception('Backend returned no scan response');
    }
    if (data['success'] == false) {
      throw Exception(data['error']?.toString() ?? 'Backend scan failed');
    }
    final raw = data['items'];
    if (raw is! List) throw Exception('No detected items');

    final items = raw.whereType<Map>().map((r) {
      final data = Map<String, dynamic>.from(r);
      final taxonomy = _normalizeDetectedTaxonomy(data);
      final validationStatus = _captureString(
        data,
        'validation_status',
        'validationStatus',
      );
      final safeValidationStatus = validationStatus.isEmpty
          ? 'ok'
          : validationStatus.toLowerCase();
      final selectedByDefault =
          _captureBool(data, 'selected_by_default', 'selectedByDefault') ??
          safeValidationStatus == 'ok';
      final occasions = data['occasions'] is List
          ? List<String>.from(
              (data['occasions'] as List).map((v) => v.toString()),
            )
          : <String>[];
      return _DetectedItem(
        id:
            data['item_id']?.toString() ??
            data['id']?.toString() ??
            UniqueKey().toString(),
        name: taxonomy.name,
        category: taxonomy.category,
        subCategory: taxonomy.subCategory,
        color: data['color_name']?.toString() ?? data['color']?.toString(),
        colorCode: data['color_code']?.toString(),
        pattern: data['pattern']?.toString(),
        occasions: occasions,
        labelSource: data['label_source']?.toString(),
        requiresManualEntry: taxonomy.requiresManualEntry,
        confidence: (data['confidence'] is num)
            ? (data['confidence'] as num).toDouble()
            : 0,
        rawUrl: data['raw_url']?.toString(),
        maskedUrl: data['masked_url']?.toString(),
        maskedImageBase64: data['masked_image_base64']?.toString(),
        sourceImageIndex: data['source_image_index'] is num
            ? (data['source_image_index'] as num).toInt()
            : (data['batch_index'] is num
                  ? (data['batch_index'] as num).toInt()
                  : null),
        raw: data,
        validationStatus: safeValidationStatus,
        rejectionReason:
            _captureString(
              data,
              'rejection_reason',
              'rejectionReason',
            ).isNotEmpty
            ? _captureString(data, 'rejection_reason', 'rejectionReason')
            : null,
        selectedByDefault: selectedByDefault,
        cropQualityScore: _captureDouble(
          data,
          'crop_quality_score',
          'cropQualityScore',
        ),
        detectionMode:
            _captureString(data, 'detection_mode', 'detectionMode').isNotEmpty
            ? _captureString(data, 'detection_mode', 'detectionMode')
            : null,
        regenProvider:
            _captureString(data, 'regen_provider', 'regenProvider').isNotEmpty
            ? _captureString(data, 'regen_provider', 'regenProvider')
            : null,
        inputType: _captureString(data, 'input_type', 'inputType').isNotEmpty
            ? _captureString(data, 'input_type', 'inputType')
            : null,
        selected: selectedByDefault && safeValidationStatus == 'ok',
      );
    }).toList();
    final okCount = items.where((i) => i.validationStatus == 'ok').length;
    final reviewCount = items
        .where((i) => i.validationStatus == 'needs_review')
        .length;
    final rejectedCount = items
        .where((i) => i.validationStatus == 'rejected')
        .length;
    final selectedApprovedCount = items
        .where((i) => i.selected && i.isSaveable)
        .length;
    debugPrint(
      'wardrobe_capture.validation total=${items.length} ok=$okCount '
      'needs_review=$reviewCount rejected=$rejectedCount '
      'selected_approved=$selectedApprovedCount',
    );
    return items;
  }

  // Single image flow (camera / single gallery pick)
  Future<void> _runDetection(Uint8List bytes) async {
    try {
      final items = await _detectOneImage(bytes);
      if (mounted) {
        setState(() {
          _detected = items;
          _step = _ModalStep.reviewing;
          _detectError = items.isEmpty
              ? 'No items detected in this photo.'
              : null;
        });
        _previewShownAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('Wardrobe single detection failed: $e');
      if (!mounted) return;

      final fallbackId = DateTime.now().millisecondsSinceEpoch.toString();
      setState(() {
        _detected = [
          _DetectedItem(
            id: fallbackId,
            name: 'Review item',
            category: 'Uncategorized',
            subCategory: '',
            occasions: const [],
            labelSource: 'manual_review',
            requiresManualEntry: true,
            confidence: 0.0,
            validationStatus: 'needs_review',
            rejectionReason: 'manual_review',
            selectedByDefault: false,
            raw: {
              'item_id': fallbackId,
              'id': fallbackId,
              'name': 'Review item',
              'category': 'Uncategorized',
              'sub_category': '',
              'requires_manual_entry': true,
              'validation_status': 'needs_review',
              'rejection_reason': 'manual_review',
              'selected_by_default': false,
              'confidence': 0.0,
            },
            selected: false,
          ),
        ];
        _detectError =
            'AI needs a quick review. Edit labels if needed, then save.';
        _step = _ModalStep.reviewing;
      });
    }
  }

  // Multi-image flow ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â all images scanned in parallel, results merged
  Future<void> _runDetectionMulti(List<Uint8List> bytesList) async {
    try {
      List<_DetectedItem> allItems = [];
      try {
        final data = await Provider.of<BackendService>(
          context,
          listen: false,
        ).analyzeImagesBatch(bytesList);
        allItems = _detectedItemsFromAnalyzeResponse(data);
      } catch (e) {
        debugPrint('Batch detection fallback: $e');
      }

      if (allItems.isEmpty) {
        final results = await Future.wait(
          bytesList.map(
            (bytes) => _detectOneImage(bytes).catchError((error) {
              debugPrint('Single image fallback failed: $error');
              return <_DetectedItem>[];
            }),
          ),
        );
        var counter = 1;
        allItems = [
          for (final list in results)
            for (final item in list)
              _DetectedItem(
                id: (counter++).toString(),
                name: item.name,
                category: item.category,
                subCategory: item.subCategory,
                color: item.color,
                colorCode: item.colorCode,
                pattern: item.pattern,
                occasions: List<String>.from(item.occasions),
                labelSource: item.labelSource,
                requiresManualEntry: item.requiresManualEntry,
                confidence: item.confidence,
                rawUrl: item.rawUrl,
                maskedUrl: item.maskedUrl,
                maskedImageBase64: item.maskedImageBase64,
                sourceImageIndex: item.sourceImageIndex,
                raw: item.raw,
                selected: true,
              ),
        ];
      }

      if (mounted) {
        setState(() {
          _detected = allItems;
          _step = _ModalStep.reviewing;
          if (allItems.isEmpty) {
            _detectError = 'No items detected in any of the images.';
          }
        });
      }
    } catch (e) {
      debugPrint('Wardrobe multi detection failed: $e');
      if (mounted) {
        setState(() {
          _detectError = 'Detection failed: ${_shortScanError(e)}';
          _step = _ModalStep.reviewing;
          _detected = [];
        });
      }
    }
  }

  String _shortScanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.length <= 160) return text;
    return '${text.substring(0, 160)}...';
  }

  void _retake() {
    _disposeItemCtrls();
    _resetUploadSession();
    setState(() {
      _step = _ModalStep.camera;
      _capturedBytes = null;
      _galleryImages = [];
      _isGalleryPick = false;
      _detected = [];
      _detectError = null;
    });
    // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Restart camera fresh for retake
    _initCamera();
  }

  /// Re-runs AI detection on the already-captured image(s) without going
  /// back to camera. Used by the "Try Again" button on the error banner
  /// and the "Retake Photo" button on the empty-results state.
  Future<void> _tryAgain() async {
    if (_capturedBytes == null && _galleryImages.isEmpty) {
      // No image in memory ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â fall back to full retake
      _retake();
      return;
    }
    _disposeItemCtrls();
    _resetUploadSession();
    setState(() {
      _step = _ModalStep.detecting;
      _detectError = null;
      _detected = [];
    });
    if (_isGalleryPick && _galleryImages.length > 1) {
      await _runDetectionMulti(_galleryImages);
    } else {
      await _runDetection(_capturedBytes!);
    }
  }

  Map<String, dynamic> _reviewedItemPayload(_DetectedItem item) {
    final payload = item.toBackendPayload();
    payload['occasions'] = preserveOccasionValues(item.occasions);
    payload['category'] = item.category;
    payload['sub_category'] = item.subCategory.isNotEmpty
        ? item.subCategory
        : item.category;
    payload['name'] = item.name;
    if (item.notes.trim().isNotEmpty) payload['notes'] = item.notes.trim();

    final hasCacheToken =
        (payload['image_cache_token']?.toString().trim().isNotEmpty ?? false);
    final maskedEvidence = payload['masked_image_base64']?.toString().trim();
    final alternateMaskedEvidence = payload['maskedImageBase64']
        ?.toString()
        .trim();
    final rawEvidence = payload['raw_image_base64']?.toString().trim();
    final alternateRawEvidence = payload['rawImageBase64']?.toString().trim();

    payload.remove('maskedImageBase64');
    payload.remove('rawImageBase64');
    if (hasCacheToken) {
      payload.remove('raw_image_base64');
      payload.remove('masked_image_base64');
    } else if ((maskedEvidence?.isNotEmpty ?? false) ||
        (alternateMaskedEvidence?.isNotEmpty ?? false)) {
      payload['masked_image_base64'] = (maskedEvidence?.isNotEmpty ?? false)
          ? maskedEvidence
          : alternateMaskedEvidence;
      payload.remove('raw_image_base64');
    } else {
      payload.remove('masked_image_base64');
      final selectedRaw = (rawEvidence?.isNotEmpty ?? false)
          ? rawEvidence
          : alternateRawEvidence;
      if (selectedRaw?.isNotEmpty ?? false) {
        payload['raw_image_base64'] = selectedRaw;
      } else {
        payload.remove('raw_image_base64');
      }
    }
    return payload;
  }

  Map<String, dynamic> _uploadMetadata(_DetectedItem item) {
    return {
      'name': item.name,
      'category': item.category,
      'sub_category': item.subCategory.isNotEmpty
          ? item.subCategory
          : item.category,
      'color_name': item.color,
      'color_code': item.colorCode,
      'pattern': item.pattern,
      'occasions': preserveOccasionValues(item.occasions),
      if (item.notes.trim().isNotEmpty) 'notes': item.notes.trim(),
    };
  }

  Future<void> _emitSavedUploadItem(
    _DetectedItem item,
    UploadItemResult result,
  ) async {
    final wardrobeItemId = result.wardrobeItemId;
    if (wardrobeItemId == null || wardrobeItemId.trim().isEmpty) {
      debugPrint(
        'Sequential upload returned ADDED_TO_WARDROBE without wardrobe_item_id '
        'for ${item.id}',
      );
      return;
    }
    String? responseUrl(List<String> keys) {
      for (final key in keys) {
        final value = result.raw[key]?.toString().trim();
        if (value != null && value.isNotEmpty && value != 'null') return value;
      }
      return null;
    }

    // Prefer the URLs returned for the saved wardrobe row. The detection URLs
    // are only fallbacks; they can describe the source image rather than the
    // processed asset persisted by the upload endpoint.
    final imageUrl =
        responseUrl(const ['image_url', 'imageUrl', 'raw_url', 'rawUrl']) ??
        item.rawUrl ??
        item.maskedUrl;
    final maskedUrl =
        responseUrl(const [
          'masked_url',
          'maskedUrl',
          'cutout_url',
          'cutoutUrl',
        ]) ??
        item.maskedUrl ??
        imageUrl;
    final normalizedUrl =
        responseUrl(const [
          'normalized_url',
          'normalizedUrl',
          'display_image_url',
          'displayImageUrl',
          'catalog_image_url',
          'catalogImageUrl',
        ]) ??
        item.raw['normalized_url']?.toString() ??
        item.raw['normalizedUrl']?.toString();
    final remoteUrl = maskedUrl ?? imageUrl;
    Uint8List? displayBytes = item.maskedImageBytes;
    if (displayBytes == null && (remoteUrl == null || remoteUrl.isEmpty)) {
      final index = item.sourceImageIndex;
      displayBytes =
          _isGalleryPick &&
              index != null &&
              index >= 0 &&
              index < _galleryImages.length
          ? _galleryImages[index]
          : _capturedBytes;
    }
    widget.onSave({
      'id': wardrobeItemId,
      'name': _cleanUiText(item.name, fallback: 'Item'),
      'cat': item.category,
      'occasions': preserveOccasionValues(item.occasions),
      'notes': [
        item.color,
        item.pattern,
      ].where((v) => v != null && v.isNotEmpty && v != 'null').join(', '),
      'imageBytes': displayBytes,
      'imageUrl': imageUrl,
      'maskedUrl': maskedUrl,
      'normalizedUrl': normalizedUrl,
      'worn': 0,
      'liked': false,
      'remoteSaved': true,
      'catalogStatus': (item.raw['catalogStatus'] ?? item.raw['catalog_status'])
          ?.toString(),
    });
  }

  Future<void> _confirmAndSave() async {
    if (_isSavingWardrobe) return;
    final selected = _detected
        .where(
          (i) =>
              i.selected &&
              i.isSaveable &&
              _uploadResults[i.id]?.isAdded != true,
        )
        .toList();
    if (selected.isEmpty) {
      _toast(AppLocalizations.t(context, 'wardrobe_no_items_to_add'));
      return;
    }
    if (selected.length > wardrobeMaxItems) {
      _showMaxItemsWarning();
      return;
    }
    for (final item in selected) {
      if (isPrivateWearText(
        '${item.name} ${item.category} ${item.subCategory}',
      )) {
        item.category = 'Innerwear';
        item.subCategory = 'Private Wear';
        item.occasions = const ['Home', 'Private', 'Lounge'];
      }
    }
    setState(() {
      _isSavingWardrobe = true;
      _step = _ModalStep.saving;
      _saveError = null;
      if (_lastSaveAttemptItems.isEmpty) {
        _lastSaveAttemptItems = List<_DetectedItem>.from(selected);
      }
    });
    HapticFeedback.lightImpact();

    final backendService = Provider.of<BackendService>(context, listen: false);
    final units = <UploadBatchUnit>[];
    for (final item in selected) {
      final reviewed = _reviewedItemPayload(item);
      final index = item.sourceImageIndex;
      final imageBytes =
          item.previewBytes ??
          (_isGalleryPick &&
                  index != null &&
                  index >= 0 &&
                  index < _galleryImages.length
              ? _galleryImages[index]
              : _capturedBytes);
      if (imageBytes == null || imageBytes.isEmpty) continue;
      units.add(
        UploadBatchUnit(
          clientUploadItemId: item.id,
          imageBytes: imageBytes,
          metadata: _uploadMetadata(item),
          reviewedItem: reviewed,
        ),
      );
    }
    if (units.isEmpty) {
      setState(() {
        _isSavingWardrobe = false;
        _step = _ModalStep.error;
        _saveError =
            "Something went wrong while saving. Your changes haven't been lost.";
      });
      return;
    }

    _uploadTotalCount = units.length;
    _uploadCompletedCount = 0;
    _uploadBatchRequestId ??=
        'wardrobe-${DateTime.now().microsecondsSinceEpoch}';
    _uploadController ??= SequentialUploadController(
      createOrResumeBatch: backendService.createOrResumeUploadBatch,
      processItem: backendService.processUploadBatchItem,
      getBatchStatus: backendService.getUploadBatchStatus,
    );
    final results = await _uploadController!.run(
      units,
      clientBatchRequestId: _uploadBatchRequestId!,
      onProgress: (completed, total, result) {
        if (!mounted) return;
        setState(() {
          _uploadCompletedCount = completed;
          _uploadTotalCount = total;
          _uploadResults[result.clientUploadItemId] = result;
        });
      },
    );
    if (!mounted) return;
    final itemById = {for (final item in selected) item.id: item};
    for (final result in results.where((result) => result.isAdded)) {
      final item = itemById[result.clientUploadItemId];
      if (item != null) await _emitSavedUploadItem(item, result);
    }
    // Each item response is the authority for what this client actually
    // persisted. The batch counter can lag or be stale during partial saves;
    // using it here can show an error after successful items were emitted.
    final addedCount = results.where((result) => result.isAdded).length;
    final savedItems = _lastSaveAttemptItems
        .where((item) => _uploadResults[item.id]?.isAdded == true)
        .toList();
    final hasReviewable = results.any(
      (result) =>
          result.outcome == UploadItemOutcome.duplicate ||
          result.outcome == UploadItemOutcome.needsReview,
    );
    final hasFailures = results.any((result) => !result.isAdded);
    HapticFeedback.mediumImpact();
    setState(() {
      _isSavingWardrobe = false;
      _savedCount = addedCount;
      _savedRequestedCount = _lastSaveAttemptItems.length;
      _savedSingleName = savedItems.length == 1 ? savedItems.first.name : null;
      _savedSingleColor = savedItems.length == 1
          ? savedItems.first.color
          : null;
      _savedSinglePattern = savedItems.length == 1
          ? savedItems.first.pattern
          : null;
      _step = addedCount > 0 && !hasFailures
          ? _ModalStep.success
          : hasReviewable || addedCount > 0
          ? _ModalStep.results
          : _ModalStep.error;
      _saveError = addedCount == 0 && !hasReviewable
          ? "Something went wrong while saving. Your changes haven't been lost."
          : null;
    });
    if (_step == _ModalStep.success) {
      _toast(
        'Saved $addedCount item${addedCount == 1 ? '' : 's'} to wardrobe.',
      );
    }
  }

  /// Retry after a failed save: re-enters the single _confirmAndSave() path
  /// with the same detected/edited items, no re-analysis. The reentry guard
  /// in _confirmAndSave already limits this to exactly one save call.
  void _retrySave() {
    if (_isSavingWardrobe) return;
    _confirmAndSave();
  }

  Future<void> _retryOutstandingFromResults() async {
    if (_isSavingWardrobe) return;
    await _confirmAndSave();
  }

  Future<void> _addAnyway(_DetectedItem item) async {
    if (_addAnywayInFlight.contains(item.id)) return;
    final controller = _uploadController;
    if (controller == null) return;
    setState(() => _addAnywayInFlight.add(item.id));
    try {
      final result = await controller.addAnyway(
        item.id,
        metadata: _uploadMetadata(item),
        reviewedItem: _reviewedItemPayload(item),
      );
      if (!mounted) return;
      setState(() => _uploadResults[item.id] = result);
      if (result.isAdded) {
        await _emitSavedUploadItem(item, result);
        if (!mounted) return;
        final addedCount = _uploadResults.values
            .where((entry) => entry.isAdded)
            .length;
        final savedItems = _lastSaveAttemptItems
            .where((entry) => _uploadResults[entry.id]?.isAdded == true)
            .toList();
        setState(() {
          _savedCount = addedCount;
          _savedRequestedCount = _lastSaveAttemptItems.length;
          _savedSingleName = savedItems.length == 1
              ? savedItems.first.name
              : null;
          _savedSingleColor = savedItems.length == 1
              ? savedItems.first.color
              : null;
          _savedSinglePattern = savedItems.length == 1
              ? savedItems.first.pattern
              : null;
          _step = _uploadResults.values.any((entry) => !entry.isAdded)
              ? _ModalStep.results
              : _ModalStep.success;
        });
      }
    } finally {
      if (mounted) setState(() => _addAnywayInFlight.remove(item.id));
    }
  }

  void _resetUploadSession() {
    _uploadBatchRequestId = null;
    _uploadController = null;
    _uploadCompletedCount = 0;
    _uploadTotalCount = 0;
    _uploadResults = {};
    _addAnywayInFlight.clear();
    _lastSaveAttemptItems = [];
  }

  /// Resets the flow back to source selection for another capture, without
  /// closing the surrounding dialog/route.
  void _startAnotherItem() {
    _disposeItemCtrls();
    _resetUploadSession();
    setState(() {
      _step = _ModalStep.camera;
      _capturedBytes = null;
      _galleryImages = [];
      _isGalleryPick = false;
      _detected = [];
      _detectError = null;
      _saveError = null;
    });
    _initCamera();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            color: t.textPrimary,
          ),
        ),
        backgroundColor: t.backgroundSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _removeMaxItemsWarning();
    _pickerInputShieldTimer?.cancel();
    _slideCtrl.dispose();
    _camCtrl?.dispose();
    _reviewPageCtrl.dispose();
    _disposeItemCtrls();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFullScreen =
        _step == _ModalStep.camera || _step == _ModalStep.detecting;

    // Hardware back / route-pop is disabled while a save is in flight, so a
    // stray back gesture can't dismiss the sheet mid-save and strand the
    // guard or the underlying wardrobe UI in a half-saved state.
    return PopScope(
      canPop: !_isSavingWardrobe,
      child: AbsorbPointer(
        absorbing: _pickerInputShielded,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: isFullScreen
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: isFullScreen
                // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Full-screen camera / detecting ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                ? AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle.light,
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: Material(
                        color: Colors.black,
                        child: SafeArea(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildBody(),
                              // Close button top-right
                              Positioned(
                                top: 12,
                                right: 16,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.45),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.20),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Card modal for results / editing ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
                : SlideTransition(
                    position: _slideAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.92,
                        ),
                        decoration: BoxDecoration(
                          color: t.backgroundSecondary.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: t.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: t.backgroundPrimary.withValues(alpha: 0.5),
                              blurRadius: 80,
                              offset: const Offset(0, 40),
                            ),
                            BoxShadow(
                              color: t.accent.primary.withValues(alpha: 0.15),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildHeader(),
                              Flexible(child: _buildBody()),
                              _buildFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final multi = _detected.length > 1;
    final titles = {
      _ModalStep.camera: 'Scan outfit',
      _ModalStep.detecting: 'Detecting...',
      _ModalStep.reviewing: multi ? 'Review items' : 'Review item',
      _ModalStep.saving: 'Saving to wardrobe...',
      _ModalStep.success: 'Added to wardrobe',
      _ModalStep.results: 'Upload results',
      _ModalStep.error: "Couldn't add this item",
    };
    final subtitles = {
      _ModalStep.camera: 'Point camera at your outfit',
      _ModalStep.detecting: 'AI is analysing your photo',
      _ModalStep.reviewing: multi
          ? '${_detected.length} items'
          : 'Edit details directly on this page',
      _ModalStep.saving: 'Please wait a moment',
      _ModalStep.success: '',
      _ModalStep.results: 'Review duplicates and retry outstanding items',
      _ModalStep.error: '',
    };
    // Back arrow only makes sense on the review step; saving/success/results/error
    // have their own in-body navigation (Retry/Cancel, View/Add another).
    final showBack = _step == _ModalStep.reviewing;
    final showClose = _step != _ModalStep.saving;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.cardBorder.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          if (showBack)
            GestureDetector(
              onTap: _isSavingWardrobe ? null : _retake,
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 13,
                  color: t.mutedText,
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_step]!,
                  style: TextStyle(
                    fontFamily: GoogleFonts.inter().fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitles[_step]!.isNotEmpty)
                  Text(
                    subtitles[_step]!,
                    style: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: 11,
                      color: t.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          if (showClose)
            Semantics(
              button: true,
              label: 'Close',
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: t.panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.cardBorder),
                  ),
                  child: Icon(Icons.close, size: 14, color: t.mutedText),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: switch (_step) {
        _ModalStep.camera => _buildCameraBody(),
        _ModalStep.detecting => _buildDetectingBody(),
        _ModalStep.reviewing => _buildReviewBody(),
        _ModalStep.saving => _buildSavingBody(),
        _ModalStep.success => _buildSuccessBody(),
        _ModalStep.results => _buildUploadResultsBody(),
        _ModalStep.error => _buildErrorBody(),
      },
    );
  }

  Widget _buildUploadResultsBody() {
    final itemsById = {for (final item in _lastSaveAttemptItems) item.id: item};
    final results = _uploadResults.values.toList();
    final added = results.where((result) => result.isAdded).length;
    return SingleChildScrollView(
      key: const ValueKey('wardrobe-upload-results'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.fact_check_rounded, size: 34, color: t.accent.primary),
          const SizedBox(height: 14),
          Text(
            'Upload review',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$added of ${_lastSaveAttemptItems.length} items are in your wardrobe.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 12,
              color: t.mutedText,
            ),
          ),
          const SizedBox(height: 20),
          ...results.map((result) {
            final item = itemsById[result.clientUploadItemId];
            if (item == null) return const SizedBox.shrink();
            final duplicate = result.isDuplicate;
            final waiting = result.outcome == UploadItemOutcome.needsReview;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                children: [
                  _uploadResultThumb(item),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: GoogleFonts.inter().fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        Text(
                          duplicate
                              ? 'Possible duplicate${result.matchedItemId == null ? '' : ' of an existing item'}'
                              : waiting
                              ? 'Needs review before it can be added'
                              : result.reason ?? 'Upload failed',
                          style: TextStyle(
                            fontFamily: GoogleFonts.inter().fontFamily,
                            fontSize: 11,
                            color: duplicate
                                ? Colors.orangeAccent
                                : t.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result.canAddAnyway)
                    TextButton(
                      onPressed: _addAnywayInFlight.contains(item.id)
                          ? null
                          : () => _addAnyway(item),
                      child: const Text('Add Anyway'),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          if (results.any((result) => !result.isAdded))
            OutlinedButton(
              key: const ValueKey('wardrobe-retry-outstanding-cta'),
              onPressed: _retryOutstandingFromResults,
              child: const Text('Retry outstanding'),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _startAnotherItem,
            child: const Text('Add another item'),
          ),
        ],
      ),
    );
  }

  Widget _uploadResultThumb(_DetectedItem item) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: t.backgroundPrimary,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.previewBytes != null
          ? Image.memory(item.previewBytes!, fit: BoxFit.cover)
          : Center(
              child: Text(
                _DetectedItem.catEmoji(item.category),
                style: const TextStyle(fontSize: 16),
              ),
            ),
    );
  }

  Widget _buildSuccessBody() {
    // Truthful counts from the actual backend save result — never inferred
    // from the (pre-save) selected-items list, so a partial save can never
    // read as "all items saved".
    final savedCount = _savedCount;
    final requestedCount = _savedRequestedCount;
    final isPartial = savedCount < requestedCount;
    final single = savedCount == 1
        ? (
            name: _savedSingleName ?? '',
            color: _savedSingleColor,
            pattern: _savedSinglePattern,
          )
        : null;
    return Container(
      key: const ValueKey('wardrobe-success'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.accent.primary, t.accent.tertiary],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: t.accent.primary.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(Icons.check_rounded, color: t.textPrimary, size: 38),
          ),
          const SizedBox(height: 18),
          Text(
            !isPartial && savedCount == 1
                ? 'Added to your wardrobe!'
                : isPartial
                ? 'Added $savedCount of $requestedCount items'
                : 'Added $savedCount items to your wardrobe!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          if (isPartial) ...[
            const SizedBox(height: 8),
            Text(
              '${requestedCount - savedCount} item${requestedCount - savedCount == 1 ? '' : 's'} '
              "could not be saved. What did save is safely in your wardrobe.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 12,
                color: t.mutedText,
              ),
            ),
          ],
          if (single != null) ...[
            const SizedBox(height: 10),
            Text(
              single.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            if ([
              single.color,
              single.pattern,
            ].where((s) => (s ?? '').trim().isNotEmpty).isNotEmpty)
              Text(
                [
                  single.color,
                  single.pattern,
                ].where((s) => (s ?? '').trim().isNotEmpty).join(' • '),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 12,
                  color: t.mutedText,
                ),
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Saved with AI labels and ready for outfit styling.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 13,
                height: 1.4,
                color: t.mutedText,
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: 'View in wardrobe',
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.accent.primary, t.accent.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'View in wardrobe',
                    style: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: 'Add another item',
              child: GestureDetector(
                onTap: _startAnotherItem,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: t.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.cardBorder, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Add another item',
                    style: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.mutedText,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: t.mutedText),
              const SizedBox(width: 6),
              Text(
                'Your data is private and secure',
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 10,
                  color: t.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavingBody() {
    return Container(
      key: const ValueKey('wardrobe-saving'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 32, color: t.accent.primary),
          const SizedBox(height: 20),
          Text(
            'Saving to wardrobe...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _uploadTotalCount > 1
                ? 'Processing ${_uploadCompletedCount + 1} of $_uploadTotalCount'
                : 'Please wait a moment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 12,
              color: t.mutedText,
            ),
          ),
          const SizedBox(height: 28),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 28),
          ..._savingStages.asMap().entries.map(
            // Only the first (in-flight) stage gets a checkmark — we only
            // know a save was *initiated*, not that any stage completed.
            // The rest stay as pending markers so the checklist never claims
            // a success we haven't observed.
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.key == 0 ? Icons.check_circle : Icons.circle_outlined,
                    size: 15,
                    color: entry.key == 0
                        ? t.accent.primary.withValues(alpha: 0.75)
                        : t.mutedText.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: 13,
                      color: entry.key == 0 ? t.textPrimary : t.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: t.mutedText),
              const SizedBox(width: 6),
              Text(
                'Your data is private and secure',
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 10,
                  color: t.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBody() {
    final failed = _detected.where((i) => i.selected && i.isSaveable).toList();
    final single = failed.length == 1 ? failed.first : null;
    return Container(
      key: const ValueKey('wardrobe-error'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.accent.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.priority_high_rounded,
                color: t.accent.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Couldn't add this item",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _saveError ??
                  "Something went wrong while saving. Your changes haven't been lost.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 13,
                height: 1.4,
                color: t.mutedText,
              ),
            ),
            if (single != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: t.backgroundSecondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: single.previewBytes != null
                          ? Image.memory(
                              single.previewBytes!,
                              fit: BoxFit.contain,
                            )
                          : Center(
                              child: Text(
                                _DetectedItem.catEmoji(single.category),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            single.name,
                            style: TextStyle(
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: t.textPrimary,
                            ),
                          ),
                          Text(
                            [single.color, single.pattern]
                                .where((s) => (s ?? '').trim().isNotEmpty)
                                .join(' • '),
                            style: TextStyle(
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontSize: 11,
                              color: t.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Retry',
                child: GestureDetector(
                  key: const ValueKey('wardrobe-retry-cta'),
                  onTap: _isSavingWardrobe ? null : _retrySave,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.accent.primary, t.accent.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontFamily: GoogleFonts.inter().fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (single != null &&
                _uploadResults[single.id]?.canAddAnyway == true) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey('wardrobe-add-anyway-cta'),
                  onPressed: _addAnywayInFlight.contains(single.id)
                      ? null
                      : () => _addAnyway(single),
                  child: const Text('Add Anyway'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Cancel',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: t.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.cardBorder, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: GoogleFonts.inter().fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.mutedText,
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

  // Broad, honest save stages — no fake completion of stages we don't know
  // succeeded. All shown at once (indeterminate spinner above carries the
  // "in progress" signal) rather than claiming per-stage completion we can't
  // observe from a single awaited backend call.
  static const _savingStages = [
    'Saving item',
    'Processing image',
    'Securing your wardrobe',
    'Finalizing',
  ];

  Widget _buildCameraBody() {
    return Stack(
      key: const ValueKey('camera'),
      fit: StackFit.expand,
      children: [
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Live camera or loading ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        _camReady && _camCtrl != null
            ? CameraPreview(_camCtrl!)
            : Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: t.accent.primary,
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.t(context, 'wardrobe_starting_camera'),
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Corner frame guides ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        if (_camReady)
          Positioned.fill(
            child: CustomPaint(painter: _FramePainter(t.accent.primary)),
          ),
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Top controls: flip (left) + flash (right) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        Positioned(
          top: 14,
          left: 14,
          right: 66,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _flipCamera,
                child: _CamControlBtn(icon: Icons.flip_camera_ios_outlined),
              ),
              GestureDetector(
                onTap: _toggleFlash,
                child: _CamControlBtn(
                  icon: _flash == FlashMode.off
                      ? Icons.flash_off
                      : Icons.flash_on,
                  iconColor: _flash == FlashMode.off
                      ? Colors.white60
                      : Colors.amber,
                ),
              ),
            ],
          ),
        ),
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Bottom bar: gallery | shutter ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gallery pill
                GestureDetector(
                  onTap: _pickGallery,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          AppLocalizations.t(context, 'wardrobe_gallery'),
                          style: TextStyle(
                            fontFamily: GoogleFonts.inter().fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: _captureAndDetect,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [t.accent.primary, t.accent.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.primary.withValues(alpha: 0.55),
                              blurRadius: 26,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: t.textPrimary,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 102),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetectingBody() {
    final isMulti = _isGalleryPick && _galleryImages.length > 1;
    return Stack(
      key: const ValueKey('detecting'),
      fit: StackFit.expand,
      children: [
        // Captured photo background
        if (_capturedBytes != null)
          Image.memory(_capturedBytes!, fit: BoxFit.cover),
        // Dark overlay
        Container(color: Colors.black.withOpacity(0.60)),
        // Scan animation + text
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ScanPulse(color: t.accent.primary),
              const SizedBox(height: 24),
              Text(
                isMulti
                    ? 'Scanning ${_galleryImages.length} images...'
                    : 'Scanning outfit...',
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isMulti
                    ? 'AHVI is understanding all images in parallel'
                    : 'AHVI is understanding your pieces',
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 13,
                  color: Colors.white54,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 28),
              _DetectChecklist(accent: t.accent.primary),
            ],
          ),
        ),
      ],
    );
  }

  // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ STEP 3: Results ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Essemble style ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
  // Unified review + edit page (Screen 3). Single scrollable page for both
  // the single-item and 2-6 item multi-garment case — no separate Edit page,
  // no per-item modal. Fields write straight back into the _DetectedItem via
  // the per-item controllers bound in _ctrlsFor().
  Widget _buildReviewBody() {
    final multi = _detected.length > 1;
    final saveableCount = _detected.where((i) => i.isSaveable).length;
    final allSelected =
        saveableCount > 0 &&
        _detected.where((i) => i.isSaveable).every((i) => i.selected);
    final pageIndex = multi
        ? _reviewPageIndex.clamp(0, _detected.length - 1)
        : 0;

    final errorBanner = _detectError == null
        ? null
        : Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.accent.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.accent.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: t.accent.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _detectError!,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 12,
                          color: t.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _tryAgain,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.accent.primary, t.accent.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      AppLocalizations.t(context, 'wardrobe_try_again'),
                      style: TextStyle(
                        fontFamily: GoogleFonts.inter().fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

    final countRow = Row(
      children: [
        Text(
          multi ? '${pageIndex + 1} of ${_detected.length}' : '1 of 1',
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.mutedText,
          ),
        ),
        const Spacer(),
        if (multi && saveableCount > 0)
          GestureDetector(
            onTap: _isSavingWardrobe
                ? null
                : () => _toggleSelectAll(!allSelected),
            child: Text(
              allSelected
                  ? AppLocalizations.t(context, 'wardrobe_deselect_all')
                  : AppLocalizations.t(context, 'wardrobe_select_all'),
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.accent.primary,
              ),
            ),
          ),
      ],
    );

    if (!multi) {
      return SingleChildScrollView(
        key: const ValueKey('review'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?errorBanner,
            countRow,
            const SizedBox(height: 10),
            if (_detected.isNotEmpty)
              _buildItemCard(_detected.first, large: true),
          ],
        ),
      );
    }

    // Multiple detected items: swipe between one item card per page instead
    // of stacking every card in a single vertical scroll.
    return Column(
      key: const ValueKey('review'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?errorBanner, countRow],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: PageView.builder(
            controller: _reviewPageCtrl,
            itemCount: _detected.length,
            onPageChanged: (i) => setState(() => _reviewPageIndex = i),
            itemBuilder: (context, i) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildItemCard(_detected[i], large: false),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_detected.length, (i) {
              final active = i == pageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: active ? t.accent.primary : t.cardBorder,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  void _toggleSelectAll(bool select) {
    final tooMany =
        select &&
        _detected.where((i) => i.isSaveable).length > wardrobeMaxItems;
    setState(() {
      var count = 0;
      for (final i in _detected) {
        if (!i.isSaveable) {
          i.selected = false;
          continue;
        }
        i.selected = select && count < wardrobeMaxItems;
        if (i.selected) count++;
      }
    });
    if (tooMany) _showMaxItemsWarning();
  }

  static const _maxCustomOccasions = 6;
  static const _maxOccasionTagLength = 24;

  List<String> _displayOccasions(_DetectedItem item) {
    final labels = <String>[..._occs];
    final seen = _occs.map(canonicalOccasionKey).toSet();
    for (final raw in item.occasions) {
      final key = canonicalOccasionKey(raw);
      if (key.isEmpty || !seen.add(key)) continue;
      final label = humanizeOccasion(raw);
      if (label.isNotEmpty) labels.add(label);
    }
    return labels;
  }

  int _customOccasionCount(_DetectedItem item) {
    final seen = <String>{};
    return item.occasions.where((raw) {
      final key = canonicalOccasionKey(raw);
      return key.isNotEmpty && !isPresetOccasion(raw) && seen.add(key);
    }).length;
  }

  Future<void> _showAddOccasionDialog(_DetectedItem item) async {
    if (_customOccasionCount(item) >= _maxCustomOccasions) {
      _toast('You can add up to $_maxCustomOccasions custom tags per item.');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _AddOccasionDialog(maxLength: _maxOccasionTagLength),
    );
    final tag = result?.trim() ?? '';
    if (tag.isEmpty || !mounted) return;
    if (item.occasions.any((raw) => occasionMatches(raw, tag))) return;
    if (isPresetOccasion(tag)) {
      setState(() => item.occasions = toggleOccasion(item.occasions, tag));
      return;
    }
    if (_customOccasionCount(item) >= _maxCustomOccasions) return;
    setState(() => item.occasions = [...item.occasions, tag]);
  }

  Widget _buildItemCard(_DetectedItem item, {required bool large}) {
    if (!item.isSaveable) {
      return _buildUnapprovedCard(item);
    }
    final ctrls = _ctrlsFor(item);
    final privateWear = isPrivateWearText(
      '${ctrls.name.text} ${item.category} ${ctrls.subCategory.text}',
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.selected
              ? t.accent.primary.withValues(alpha: 0.5)
              : t.cardBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: double.infinity,
                  height: large ? 240 : 140,
                  child: Container(
                    color: t.backgroundSecondary,
                    child: item.previewBytes != null
                        ? Image.memory(
                            item.previewBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : (item.displayUrl != null
                              ? Image.network(
                                  item.displayUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Text(
                                      _DetectedItem.catEmoji(item.category),
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _DetectedItem.catEmoji(item.category),
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                )),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Semantics(
                  button: true,
                  label: item.selected
                      ? 'Included in this upload'
                      : 'Excluded from this upload',
                  child: GestureDetector(
                    key: ValueKey('wardrobe-select-${item.id}'),
                    onTap: _isSavingWardrobe
                        ? null
                        : () {
                            final selCount = _detected
                                .where((d) => d.selected && d.isSaveable)
                                .length;
                            if (!item.selected &&
                                selCount >= wardrobeMaxItems) {
                              _showMaxItemsWarning();
                              return;
                            }
                            setState(() => item.selected = !item.selected);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: item.selected
                            ? LinearGradient(
                                colors: [t.accent.primary, t.accent.tertiary],
                              )
                            : null,
                        color: item.selected
                            ? null
                            : Colors.black.withOpacity(0.45),
                        border: Border.all(
                          color: item.selected
                              ? t.accent.primary
                              : Colors.white70,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        item.selected ? Icons.check : Icons.close,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ctrls.name.text.isEmpty ? item.category : ctrls.name.text,
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if ([
            item.color,
            item.pattern,
          ].where((s) => (s ?? '').trim().isNotEmpty).isNotEmpty)
            Text(
              [
                item.color,
                item.pattern,
              ].where((s) => (s ?? '').trim().isNotEmpty).join(' • '),
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 12,
                color: t.mutedText,
              ),
            ),
          if (item.isDuplicate) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'Possible duplicate${item.matchedItemId == null ? '' : ' of an existing wardrobe item'}${item.duplicateConfidence == null ? '' : ' (${(item.duplicateConfidence! * 100).round()}% match)'}. You can review it, then choose Add Anyway if it is a different item.',
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 11,
                  height: 1.35,
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _ModalField(
            label: AppLocalizations.t(context, 'wardrobe_item_name'),
            child: _StyledInput(
              controller: ctrls.name,
              hint: 'e.g. White linen shirt',
            ),
          ),
          const SizedBox(height: 12),
          _ModalField(
            label: AppLocalizations.t(context, 'wardrobe_category_required'),
            child: _CategoryDropdown(
              value: item.category,
              categories: _cats,
              onChanged: (v) =>
                  setState(() => item.category = v ?? item.category),
            ),
          ),
          const SizedBox(height: 12),
          _ModalField(
            label: 'Sub-category',
            child: _StyledInput(
              controller: ctrls.subCategory,
              hint: 'e.g. Shirt, Saree, Sneakers',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ModalField(
                  label: 'Color',
                  child: _StyledInput(
                    controller: ctrls.color,
                    hint: 'e.g. blue',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModalField(
                  label: 'Pattern',
                  child: _StyledInput(
                    controller: ctrls.pattern,
                    hint: 'plain, checked',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (privateWear) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.accent.secondary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: t.accent.secondary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                "This item is marked as private wear and won't be used in public outfit boards.",
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _ModalField(
            label: 'Best for',
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                ..._displayOccasions(item).map((occ) {
                  final active = item.occasions.any(
                    (o) => occasionMatches(o, occ),
                  );
                  final disabled =
                      privateWear &&
                      {
                        'Work',
                        'Dinner',
                        'Travel',
                        'Party',
                        'Festive',
                        'Wedding',
                      }.contains(occ);
                  return GestureDetector(
                    onTap: disabled
                        ? null
                        : () => setState(() {
                            item.occasions = toggleOccasion(
                              item.occasions,
                              occ,
                            );
                          }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: active
                            ? LinearGradient(
                                colors: [t.accent.primary, t.accent.tertiary],
                              )
                            : null,
                        color: active
                            ? null
                            : t.backgroundSecondary.withValues(
                                alpha: disabled ? 0.45 : 1,
                              ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? t.accent.primary : t.cardBorder,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        occ,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: disabled
                              ? t.mutedText.withValues(alpha: 0.45)
                              : (active ? t.textPrimary : t.mutedText),
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  key: const ValueKey('wardrobe-add-occasion'),
                  onTap: () => _showAddOccasionDialog(item),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.backgroundSecondary,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.cardBorder, width: 1.5),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: t.accent.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ModalField(
            label: AppLocalizations.t(context, 'wardrobe_notes_optional'),
            child: _StyledInput(
              controller: ctrls.notes,
              hint: 'Colour, material, where you got it...',
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnapprovedCard(_DetectedItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.panel.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: item.previewBytes != null
                ? Image.memory(item.previewBytes!, fit: BoxFit.contain)
                : Center(
                    child: Text(
                      _DetectedItem.catEmoji(item.category),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontFamily: GoogleFonts.inter().fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.statusLabel ?? 'Not approved',
                  style: TextStyle(
                    fontFamily: GoogleFonts.inter().fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: t.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    // The saving/success/error screens carry their own primary actions
    // in-body (Screens 4-6) — the footer must not offer a second Save/Retry
    // control while any of those states are active.
    if (_step == _ModalStep.saving ||
        _step == _ModalStep.success ||
        _step == _ModalStep.results ||
        _step == _ModalStep.error) {
      return const SizedBox.shrink();
    }

    final int selCount = _detected
        .where((i) => i.selected && i.isSaveable)
        .length;

    // Camera step — only Cancel, no manual option.
    if (_step == _ModalStep.camera) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.cardBorder)),
          color: t.backgroundSecondary.withValues(alpha: 0.97),
        ),
        child: SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.cardBorder, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                AppLocalizations.t(context, 'cancel'),
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 14,
                  color: t.mutedText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Detecting — no footer controls; the scanning screen owns its own UI.
    if (_step == _ModalStep.detecting) {
      return const SizedBox.shrink();
    }

    // Reviewing with nothing approved/selected — hide primary button.
    if (_step == _ModalStep.reviewing && selCount == 0) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.cardBorder)),
          color: t.backgroundSecondary.withValues(alpha: 0.97),
        ),
        child: SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.cardBorder, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                AppLocalizations.t(context, 'cancel'),
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 14,
                  color: t.mutedText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Single active final "Add to wardrobe" entry point for the whole
    // capture session — this is the ONLY call site of _confirmAndSave().
    final String primaryLabel = selCount == 1
        ? 'Add to wardrobe'
        : 'Add $selCount items to wardrobe';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.cardBorder)),
        color: t.backgroundSecondary.withValues(alpha: 0.97),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.cardBorder, width: 1.5),
              ),
              child: Text(
                AppLocalizations.t(context, 'cancel'),
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 14,
                  color: t.mutedText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              label: primaryLabel,
              child: GestureDetector(
                key: const ValueKey('wardrobe-confirm-cta'),
                onTap: _confirmAndSave,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.accent.primary, t.accent.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    primaryLabel,
                    style: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
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

String _captureString(Map<String, dynamic> data, String snake, String camel) {
  return (data[snake] ?? data[camel] ?? '').toString().trim();
}

bool? _captureBool(Map<String, dynamic> data, String snake, String camel) {
  final value = data.containsKey(snake) ? data[snake] : data[camel];
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) return null;
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

double? _captureDouble(Map<String, dynamic> data, String snake, String camel) {
  final value = data.containsKey(snake) ? data[snake] : data[camel];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ CAMERA CONTROL BUTTON ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _CamControlBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  const _CamControlBtn({required this.icon, this.iconColor = Colors.white70});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Icon(icon, color: iconColor, size: 18),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ SCAN PULSE WIDGET ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
// Staggered "AHVI is understanding" checklist shown during detection.
// Pure presentation — completes on timers; detection finishing dismisses
// the whole step regardless of checklist progress.
class _DetectChecklist extends StatefulWidget {
  final Color accent;
  const _DetectChecklist({required this.accent});

  @override
  State<_DetectChecklist> createState() => _DetectChecklistState();
}

class _DetectChecklistState extends State<_DetectChecklist> {
  static const List<String> _checks = [
    'Item type detected',
    'Color identified',
    'Style profile analyzed',
    'Occasion suitability assessed',
  ];
  late final List<bool> _done = List.filled(_checks.length, false);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _checks.length; i++) {
      Future.delayed(Duration(milliseconds: 500 + (i * 650)), () {
        if (mounted) setState(() => _done[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_checks.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                opacity: _done[i] ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _done[i]
                        ? widget.accent
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 12.5,
                  color: _done[i] ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
                child: Text(_checks[i]),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _ScanPulse extends StatefulWidget {
  final Color color;
  const _ScanPulse({required this.color});
  @override
  State<_ScanPulse> createState() => _ScanPulseState();
}

class _ScanPulseState extends State<_ScanPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Transform.scale(
        scale: _anim.value,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [widget.color, widget.color.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * _anim.value),
                blurRadius: 22,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome, size: 26, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ CAMERA FRAME GUIDE PAINTER ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _FramePainter extends CustomPainter {
  final Color color;
  const _FramePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withOpacity(0.55)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const c = 20.0, m = 16.0;
    final l = m, r = size.width - m, t = m, b = size.height - m;
    canvas.drawLine(Offset(l, t + c), Offset(l, t), p);
    canvas.drawLine(Offset(l, t), Offset(l + c, t), p);
    canvas.drawLine(Offset(r - c, t), Offset(r, t), p);
    canvas.drawLine(Offset(r, t), Offset(r, t + c), p);
    canvas.drawLine(Offset(l, b - c), Offset(l, b), p);
    canvas.drawLine(Offset(l, b), Offset(l + c, b), p);
    canvas.drawLine(Offset(r - c, b), Offset(r, b), p);
    canvas.drawLine(Offset(r, b), Offset(r, b - c), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ SMALL PILL TAG ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _ModalField extends StatelessWidget {
  final String label;
  final Widget child;
  const _ModalField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: t.mutedText,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _UploadSourceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _UploadSourceButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.cardBorder, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: t.mutedText),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.mutedText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyledInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _StyledInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.cardBorder, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(
          fontFamily: GoogleFonts.inter().fontFamily,
          fontSize: 14,
          color: t.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: t.mutedText),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final String value;
  final List<String> categories;
  final ValueChanged<String?> onChanged;
  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.cardBorder, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? null : value,
          hint: Text(
            AppLocalizations.t(context, 'wardrobe_select_hint'),
            style: TextStyle(
              color: t.mutedText,
              fontFamily: GoogleFonts.inter().fontFamily,
            ),
          ),
          isExpanded: true,
          dropdownColor: t.backgroundSecondary,
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 14,
            color: t.textPrimary,
          ),
          items: categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ APP HEADER ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _AppHeader extends StatelessWidget {
  final String title;
  final int activeTab;
  final ValueChanged<int> onTabTap;
  final VoidCallback onAddTap;
  final ValueChanged<String> onSearch;

  const _AppHeader({
    required this.title,
    required this.activeTab,
    required this.onTabTap,
    required this.onAddTap,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ AHVI logo ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â shared AhviHeader, pixel-perfect on all screens ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        const AhviHeader(showBorder: false, frosted: true),
        // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Title row: "My Wardrobe" + Add item button ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
        Container(
          decoration: BoxDecoration(
            color: t.backgroundPrimary.withValues(alpha: 0.92),
            border: Border(bottom: BorderSide(color: t.cardBorder, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _OfflineDimmer(
                      child: _HoverScaleButton(
                        scaleFactor: 1.02,
                        duration: const Duration(milliseconds: 200),
                        onTap: onAddTap,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [t.accent.primary, t.accent.tertiary],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, color: t.textPrimary, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  AppLocalizations.t(
                                    context,
                                    'wardrobe_add_item',
                                  ),
                                  style: TextStyle(
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: t.mutedText, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: onSearch,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 15,
                          color: t.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: AppLocalizations.t(
                            context,
                            'wardrobe_search_hint',
                          ),
                          hintStyle: TextStyle(color: t.mutedText),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ HOVER SCALE BUTTON ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _HoverScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;
  final Duration duration;
  const _HoverScaleButton({
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.97,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  State<_HoverScaleButton> createState() => _HoverScaleButtonState();
}

class _HoverScaleButtonState extends State<_HoverScaleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? widget.scaleFactor : 1.0,
          duration: widget.duration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ FILTER BAR ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _FilterBar extends StatelessWidget {
  final String activeCat;
  final ValueChanged<String> onCatTap;
  const _FilterBar({required this.activeCat, required this.onCatTap});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final accent5 = _accent5(t);
    final bags = _bagsChip(t);
    final jewelry = _jewelryChip(t);
    final makeup = _makeupChip(t);
    final skincare = _skincareChip(t);

    final chips = [
      _ChipData(
        label: AppLocalizations.t(context, 'wardrobe_all'),
        icon: Icons.grid_view_rounded,
        activeGradient: LinearGradient(
          colors: [t.accent.primary, t.accent.secondary],
        ),
        activeBorder: t.accent.primary,
        activeShadow: t.accent.primary.withValues(alpha: 0.35),
        inactiveBg: t.panel,
        inactiveBorder: t.cardBorder,
        inactiveText: t.mutedText,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_tops'),
        icon: Icons.checkroom_outlined,
        activeBg: t.accent.primary.withValues(alpha: 0.28),
        activeBorder: t.accent.primary,
        activeShadow: t.accent.primary.withValues(alpha: 0.25),
        inactiveBg: t.accent.primary.withValues(alpha: 0.12),
        inactiveBorder: t.accent.primary.withValues(alpha: 0.30),
        inactiveText: t.accent.primary,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_bottoms'),
        icon: Icons.format_align_justify,
        activeBg: t.accent.secondary.withValues(alpha: 0.28),
        activeBorder: t.accent.secondary,
        activeShadow: t.accent.secondary.withValues(alpha: 0.25),
        inactiveBg: t.accent.secondary.withValues(alpha: 0.12),
        inactiveBorder: t.accent.secondary.withValues(alpha: 0.30),
        inactiveText: t.accent.secondary,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_outerwear'),
        icon: Icons.umbrella_outlined,
        activeBg: t.accent.tertiary.withValues(alpha: 0.22),
        activeBorder: t.accent.tertiary,
        activeShadow: t.accent.tertiary.withValues(alpha: 0.20),
        inactiveBg: t.accent.tertiary.withValues(alpha: 0.10),
        inactiveBorder: t.accent.tertiary.withValues(alpha: 0.30),
        inactiveText: t.accent.tertiary,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_footwear'),
        icon: Icons.directions_walk,
        activeBg: accent5.withValues(alpha: 0.22),
        activeBorder: accent5,
        activeShadow: accent5.withValues(alpha: 0.20),
        inactiveBg: accent5.withValues(alpha: 0.10),
        inactiveBorder: accent5.withValues(alpha: 0.30),
        inactiveText: accent5,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_dresses'),
        icon: Icons.dry_cleaning_outlined,
        activeBg: accent4.withValues(alpha: 0.22),
        activeBorder: accent4,
        activeShadow: accent4.withValues(alpha: 0.20),
        inactiveBg: accent4.withValues(alpha: 0.10),
        inactiveBorder: accent4.withValues(alpha: 0.30),
        inactiveText: accent4,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_accessories'),
        icon: Icons.watch_outlined,
        activeBg: t.accent.secondary.withValues(alpha: 0.24),
        activeBorder: t.accent.secondary,
        activeShadow: t.accent.secondary.withValues(alpha: 0.20),
        inactiveBg: t.accent.secondary.withValues(alpha: 0.10),
        inactiveBorder: t.accent.secondary.withValues(alpha: 0.28),
        inactiveText: t.accent.secondary,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_bags'),
        icon: Icons.shopping_bag_outlined,
        activeBg: bags.withValues(alpha: 0.22),
        activeBorder: bags,
        activeShadow: bags.withValues(alpha: 0.25),
        inactiveBg: bags.withValues(alpha: 0.12),
        inactiveBorder: bags.withValues(alpha: 0.30),
        inactiveText: bags,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_jewelry'),
        icon: Icons.diamond_outlined,
        activeBg: jewelry.withValues(alpha: 0.22),
        activeBorder: jewelry,
        activeShadow: jewelry.withValues(alpha: 0.25),
        inactiveBg: jewelry.withValues(alpha: 0.12),
        inactiveBorder: jewelry.withValues(alpha: 0.30),
        inactiveText: jewelry,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_makeup'),
        icon: Icons.face_retouching_natural,
        activeBg: makeup.withValues(alpha: 0.22),
        activeBorder: makeup,
        activeShadow: makeup.withValues(alpha: 0.25),
        inactiveBg: makeup.withValues(alpha: 0.12),
        inactiveBorder: makeup.withValues(alpha: 0.30),
        inactiveText: makeup,
        activeText: t.textPrimary,
      ),
      _ChipData(
        label: AppLocalizations.t(context, 'cat_skincare'),
        icon: Icons.spa_outlined,
        activeBg: skincare.withValues(alpha: 0.22),
        activeBorder: skincare,
        activeShadow: skincare.withValues(alpha: 0.25),
        inactiveBg: skincare.withValues(alpha: 0.12),
        inactiveBorder: skincare.withValues(alpha: 0.30),
        inactiveText: skincare,
        activeText: t.textPrimary,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: List.generate(chips.length, (i) {
          final chip = chips[i];
          final isActive = activeCat == chip.label;
          return Padding(
            padding: EdgeInsets.only(right: i < chips.length - 1 ? 8 : 0),
            child: _FilterChip(
              chip: chip,
              isActive: isActive,
              onTap: () => onCatTap(chip.label),
            ),
          );
        }),
      ),
    );
  }
}

class _ChipData {
  final String label;
  final IconData icon;
  final LinearGradient? activeGradient;
  final Color? activeBg;
  final Color activeBorder;
  final Color activeShadow;
  final Color inactiveBg;
  final Color inactiveBorder;
  final Color inactiveText;
  final Color activeText;

  const _ChipData({
    required this.label,
    required this.icon,
    this.activeGradient,
    this.activeBg,
    required this.activeBorder,
    required this.activeShadow,
    required this.inactiveBg,
    required this.inactiveBorder,
    required this.inactiveText,
    required this.activeText,
  });
}

class _FilterChip extends StatefulWidget {
  final _ChipData chip;
  final bool isActive;
  final VoidCallback onTap;
  const _FilterChip({
    required this.chip,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _hovered && !widget.isActive
              ? Matrix4.translationValues(0.0, -1.0, 0.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            gradient: widget.isActive ? widget.chip.activeGradient : null,
            color: widget.isActive
                ? (widget.chip.activeGradient == null
                      ? widget.chip.activeBg
                      : null)
                : (_hovered
                      ? widget.chip.inactiveBg.withValues(alpha: 0.28)
                      : widget.chip.inactiveBg),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isActive
                  ? widget.chip.activeBorder
                  : widget.chip.inactiveBorder,
              width: 1.5,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: widget.chip.activeShadow,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : (_hovered
                      ? [
                          BoxShadow(
                            color: t.backgroundPrimary.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.chip.icon,
                size: 14,
                color: widget.isActive
                    ? widget.chip.activeText
                    : widget.chip.inactiveText,
              ),
              const SizedBox(width: 6),
              Text(
                widget.chip.label,
                style: TextStyle(
                  fontFamily: GoogleFonts.inter().fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: widget.isActive
                      ? widget.chip.activeText
                      : widget.chip.inactiveText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ WARDROBE PANEL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _WardrobePanel extends StatelessWidget {
  final List<WardrobeItem> items;
  final bool allEmpty;
  final VoidCallback onAddTap;
  final List<WardrobeItem> wardrobe;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onToggleLike;
  final ValueChanged<String> onWore;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onTapCard;
  final Future<void> Function() onRefresh;

  const _WardrobePanel({
    required this.items,
    required this.allEmpty,
    required this.onAddTap,
    required this.wardrobe,
    required this.onDelete,
    required this.onToggleLike,
    required this.onWore,
    required this.onShare,
    required this.onTapCard,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Single lazy CustomScrollView (was SingleChildScrollView + Column +
    // shrinkWrap GridView, which thrashed layout during pull-to-refresh).
    // AlwaysScrollable so the RefreshIndicator can pull-trigger even when
    // content is shorter than the viewport (e.g. empty wardrobe state).
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            sliver: SliverToBoxAdapter(
              child: _InlineInsightCard(wardrobe: wardrobe),
            ),
          ),
          if (allEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              sliver: SliverToBoxAdapter(
                child: _EmptyState(onAddTap: onAddTap),
              ),
            )
          else if (items.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 100),
              sliver: SliverToBoxAdapter(child: _EmptySearch()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              sliver: _ItemGrid(
                items: items,
                onDelete: onDelete,
                onToggleLike: onToggleLike,
                onWore: onWore,
                onShare: onShare,
                onTapCard: onTapCard,
              ),
            ),
        ],
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ INLINE AI INSIGHT CARD ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _InlineInsightCard extends StatefulWidget {
  final List<WardrobeItem> wardrobe;
  const _InlineInsightCard({required this.wardrobe});

  @override
  State<_InlineInsightCard> createState() => _InlineInsightCardState();
}

class _InlineInsightCardState extends State<_InlineInsightCard>
    with TickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late AnimationController _dotCtrl;
  late Animation<double> _glowAnim;
  late Animation<double> _dotAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _dotAnim = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut));
  }

  // FIX: Pause repeating animations while the route is not fully active
  // (e.g. during back-swipe transitions). Firing AnimatedBuilders every frame
  // while the Navigator gesture is running was contributing to frame skips.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route?.isCurrent == false) {
      _glowCtrl.stop();
      _dotCtrl.stop();
    } else {
      if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
      if (!_dotCtrl.isAnimating) _dotCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  String _computeInsightText() {
    final total = widget.wardrobe.length;
    if (total == 0) {
      return 'Add items to your wardrobe to unlock smart style insights.';
    }
    final wornItems = widget.wardrobe.where((i) => i.worn > 0).toList();
    final unwornCount = total - wornItems.length;
    final liked = widget.wardrobe.where((i) => i.liked).toList();
    final sorted = [...widget.wardrobe]
      ..sort((a, b) => b.worn.compareTo(a.worn));
    final mostWorn = sorted.isNotEmpty ? sorted.first : null;

    if (liked.isNotEmpty && mostWorn != null && mostWorn.worn > 0) {
      final likedStr = '${liked.length} piece${liked.length != 1 ? 's' : ''}';
      final wearStr = '${mostWorn.worn} wear${mostWorn.worn != 1 ? 's' : ''}';
      final rotateStr = unwornCount > 0
          ? ' - rotate your $unwornCount unworn piece${unwornCount != 1 ? 's' : ''}'
          : '';
      return 'You love $likedStr. Your ${_cleanUiText(mostWorn.name, fallback: 'item')} leads with $wearStr$rotateStr.';
    } else if (mostWorn != null && mostWorn.worn > 0) {
      final wearStr = '${mostWorn.worn} wear${mostWorn.worn != 1 ? 's' : ''}';
      if (unwornCount > 0) {
        return 'Your ${_cleanUiText(mostWorn.name, fallback: 'item')} leads with $wearStr. $unwornCount piece${unwornCount != 1 ? 's' : ''} still unworn - time to rotate.';
      }
      return 'Your ${_cleanUiText(mostWorn.name, fallback: 'item')} leads with $wearStr. Every piece has been worn.';
    } else if (liked.isNotEmpty) {
      return "You've liked ${liked.length} favourite${liked.length != 1 ? 's' : ''}. Start logging wears to get deeper insights.";
    }
    return 'You have $total piece${total != 1 ? 's' : ''}. Like favourites and log wears to unlock insights.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent2 = t.accent.secondary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent2.withValues(alpha: 0.15), width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent2.withValues(alpha: 0.10),
            t.accent.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, _) {
              final glowT = _glowAnim.value;
              return Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent2.withValues(alpha: 0.25),
                      t.accent.primary.withValues(alpha: 0.18),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: accent2.withValues(alpha: 0.35),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent2.withValues(alpha: 0.20 + glowT * 0.18),
                      blurRadius: 10 + glowT * 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(Icons.auto_awesome, size: 16, color: accent2),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _dotAnim,
                      builder: (_, _) => Opacity(
                        opacity: _dotAnim.value,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accent2,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.t(context, 'wardrobe_ai_insight'),
                      style: TextStyle(
                        fontFamily: GoogleFonts.inter().fontFamily,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: accent2,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _computeInsightText(),
                  style: TextStyle(
                    fontFamily: GoogleFonts.inter().fontFamily,
                    fontSize: 12.5,
                    color: t.mutedText,
                    height: 1.5,
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

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ ITEM GRID ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _ItemGrid extends StatelessWidget {
  final List<WardrobeItem> items;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onToggleLike;
  final ValueChanged<String> onWore;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onTapCard;

  const _ItemGrid({
    required this.items,
    required this.onDelete,
    required this.onToggleLike,
    required this.onWore,
    required this.onShare,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    // Lazy SliverGrid (was a shrinkWrap GridView nested in a
    // SingleChildScrollView — that re-laid-out every item on each
    // pull-to-refresh overscroll frame and pegged the main thread → ANR).
    // Only visible cells build now.
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _FadeUpItem(
        delay: Duration(milliseconds: (i * 40).clamp(0, 400)),
        child: RepaintBoundary(
          child: _ItemCard(
            item: items[i],
            onDelete: () => onDelete(items[i].id),
            onToggleLike: () => onToggleLike(items[i].id),
            onWore: () => onWore(items[i].id),
            onShare: () => onShare(items[i].id),
            onTap: () => onTapCard(items[i].id),
          ),
        ),
      ),
    );
  }
}

class _FadeUpItem extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FadeUpItem({required this.child, required this.delay});

  @override
  State<_FadeUpItem> createState() => _FadeUpItemState();
}

class _FadeUpItemState extends State<_FadeUpItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ ITEM CARD ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _ItemCard extends StatefulWidget {
  final WardrobeItem item;
  final VoidCallback onDelete;
  final VoidCallback onToggleLike;
  final VoidCallback onWore;
  final VoidCallback onShare;
  final VoidCallback onTap;

  const _ItemCard({
    required this.item,
    required this.onDelete,
    required this.onToggleLike,
    required this.onWore,
    required this.onShare,
    required this.onTap,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _likeCtrl;
  late Animation<double> _likeScale;
  bool _deletePressed = false;
  bool _likeHovered = false;
  bool _likePressed = false;

  @override
  void initState() {
    super.initState();
    _likeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _likeScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.45,
        ).chain(CurveTween(curve: const Cubic(0.34, 1.2, 0.64, 1))),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.45,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.9,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_likeCtrl);
  }

  @override
  void dispose() {
    _likeCtrl.dispose();
    super.dispose();
  }

  static String _catEmoji(String cat) =>
      const {
        'Tops': 'TOP',
        'Bottoms': 'BOT',
        'Outerwear': 'OUT',
        'Footwear': 'SHO',
        'Dresses': 'DRS',
        'Accessories': 'ACC',
        'Bags': 'BAG',
        'Jewelry': 'JWL',
        'Makeup': 'MKP',
        'Skincare': 'SKN',
      }[cat] ??
      'ITM';

  void _handleLike() {
    widget.onToggleLike();
    _likeCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final item = widget.item;
    final resolvedImage = item.resolveImage(surface: 'wardrobe_grid');
    final wornLabel = item.worn == 0 ? 'New' : '${item.worn} worn';
    final wornColor = item.worn > 0
        ? t.accent.tertiary.withValues(alpha: 0.15)
        : t.mutedText.withValues(alpha: 0.12);
    final wornTextColor = item.worn > 0 ? t.accent.tertiary : t.mutedText;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: const Cubic(0.2, 0.8, 0.3, 1.0),
          transform: _hovered
              ? Matrix4.translationValues(0.0, -4.0, 0.0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.cardBorder, width: 1),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: t.backgroundPrimary.withValues(alpha: 0.4),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : [],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Main content ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            t.accent.primary.withValues(alpha: 0.15),
                            t.accent.secondary.withValues(alpha: 0.12),
                          ],
                        ),
                        // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Prioritize Masked URL over Raw URL
                        image: resolvedImage.url != null
                            ? DecorationImage(
                                image: NetworkImage(resolvedImage.url!),
                                fit: BoxFit.contain,
                              )
                            : (item.imageBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(item.imageBytes!),
                                      fit: BoxFit.contain,
                                    )
                                  : null),
                      ),
                      child:
                          (resolvedImage.url == null && item.imageBytes == null)
                          ? Center(
                              child: Text(
                                _catEmoji(item.cat),
                                style: const TextStyle(fontSize: 40),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontFamily: GoogleFonts.inter().fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: t.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item.cat,
                              style: TextStyle(
                                fontFamily: GoogleFonts.inter().fontFamily,
                                fontSize: 11,
                                color: t.mutedText,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: wornColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                wornLabel,
                                style: TextStyle(
                                  fontFamily: GoogleFonts.inter().fontFamily,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: wornTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Delete button ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _deletePressed = true),
                  onTapUp: (_) {
                    setState(() => _deletePressed = false);
                    widget.onDelete();
                  },
                  onTapCancel: () => setState(() => _deletePressed = false),
                  child: AnimatedScale(
                    scale: _deletePressed ? 0.88 : 1.0,
                    duration: Duration(milliseconds: _deletePressed ? 80 : 150),
                    child: _OfflineDimmer(child: _DeleteHoverButton()),
                  ),
                ),
              ),

              // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Like button ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
              Positioned(
                top: 8,
                right: 8,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _likeHovered = true),
                  onExit: (_) => setState(() => _likeHovered = false),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _likePressed = true),
                    onTapUp: (_) {
                      setState(() => _likePressed = false);
                      _handleLike();
                    },
                    onTapCancel: () => setState(() => _likePressed = false),
                    child: AnimatedBuilder(
                      animation: _likeScale,
                      builder: (_, child) {
                        double scale;
                        if (_likeCtrl.isAnimating) {
                          scale = _likeScale.value;
                        } else if (_likePressed) {
                          scale = 0.88;
                        } else if (_likeHovered) {
                          scale = 1.12;
                        } else {
                          scale = item.liked ? 1.15 : 1.0;
                        }
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: AnimatedContainer(
                        duration: Duration(
                          milliseconds: _likePressed ? 80 : 150,
                        ),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: item.liked
                              ? accent4.withValues(alpha: 0.2)
                              : (_likeHovered
                                    ? t.backgroundSecondary.withValues(
                                        alpha: 0.98,
                                      )
                                    : t.backgroundPrimary.withValues(
                                        alpha: 0.7,
                                      )),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: t.textPrimary.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: _likeHovered && !_likePressed
                              ? [
                                  BoxShadow(
                                    color: accent4.withValues(alpha: 0.18),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          item.liked ? Icons.favorite : Icons.favorite_border,
                          color: item.liked
                              ? accent4
                              : (_likeHovered ? accent4 : t.mutedText),
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Hover overlay ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
              AnimatedOpacity(
                opacity: _hovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          t.backgroundPrimary.withValues(alpha: 0.55),
                          kTransparent,
                        ],
                        stops: const [0.0, 0.52],
                      ),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onWore,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: t.accent.tertiary.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '+ Wore it',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.tileText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: widget.onShare,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: t.textPrimary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.ios_share_rounded,
                                color: t.accent.primary,
                                size: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _DeleteHoverButton extends StatefulWidget {
  @override
  State<_DeleteHoverButton> createState() => _DeleteHoverButtonState();
}

class _DeleteHoverButtonState extends State<_DeleteHoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _hovered
              ? accent4.withValues(alpha: 0.12)
              : t.backgroundPrimary.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: _hovered
                ? accent4.withValues(alpha: 0.28)
                : t.textPrimary.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: accent4.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.close,
          color: _hovered ? accent4 : t.mutedText,
          size: 12,
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ EMPTY STATES ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _EmptyState extends StatelessWidget {
  final VoidCallback onAddTap;
  const _EmptyState({required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.checkroom_outlined,
            size: 52,
            color: t.mutedText.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.t(context, 'wardrobe_empty_title'),
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.t(context, 'wardrobe_empty_subtitle'),
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 14,
              color: t.mutedText,
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _OfflineDimmer(
            child: GestureDetector(
              onTap: onAddTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.accent.primary, t.accent.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+ ${AppLocalizations.t(context, 'wardrobe_add_first_item')}',
                  style: TextStyle(
                    fontFamily: GoogleFonts.inter().fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
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

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Opacity(opacity: 0.4, child: Icon(Icons.search_off, size: 40)),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.t(context, 'wardrobe_no_search_results'),
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.t(context, 'wardrobe_no_search_subtitle'),
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 14,
              color: t.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ STATS PANEL ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _StatsPanel extends StatelessWidget {
  final List<WardrobeItem> wardrobe;
  const _StatsPanel({required this.wardrobe});

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final total = wardrobe.length;
    final worn = wardrobe.where((i) => i.worn > 0).length;
    final totalWears = wardrobe.fold<int>(0, (s, i) => s + i.worn);
    final wearRate = total > 0 ? (worn / total * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.t(context, 'wardrobe_overview'),
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.2,
            children: [
              _HoverStatCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.primary.withValues(alpha: 0.20),
                    t.accent.primary.withValues(alpha: 0.12),
                  ],
                ),
                iconBg: t.accent.primary.withValues(alpha: 0.25),
                iconChar: 'AI',
                number: '$total',
                label: AppLocalizations.t(context, 'wardrobe_total_pieces'),
                sub: 'in your wardrobe',
              ),
              _HoverStatCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent4.withValues(alpha: 0.20),
                    accent4.withValues(alpha: 0.12),
                  ],
                ),
                iconBg: accent4.withValues(alpha: 0.25),
                iconChar: 'AI',
                number: '0',
                label: AppLocalizations.t(context, 'wardrobe_outfits_saved'),
                sub: 'ready to wear',
              ),
              _HoverStatCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.tertiary.withValues(alpha: 0.20),
                    t.accent.tertiary.withValues(alpha: 0.12),
                  ],
                ),
                iconBg: t.accent.tertiary.withValues(alpha: 0.25),
                iconChar: 'AI',
                number: '$totalWears',
                label: AppLocalizations.t(context, 'wardrobe_times_worn_stat'),
                sub: 'total logs',
              ),
              _HoverStatCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.secondary.withValues(alpha: 0.20),
                    t.accent.secondary.withValues(alpha: 0.12),
                  ],
                ),
                iconBg: t.accent.secondary.withValues(alpha: 0.25),
                iconChar: 'AI',
                number: '$wearRate%',
                label: AppLocalizations.t(context, 'wardrobe_wear_rate'),
                sub: 'items worn at least once',
              ),
            ],
          ),
          const SizedBox(height: 28),
          _buildDivider(context, 'By category'),
          const SizedBox(height: 14),
          _buildBars(context),
          const SizedBox(height: 28),
          _buildDivider(context, 'Most worn'),
          const SizedBox(height: 14),
          _buildMostWorn(context),
          const SizedBox(height: 28),
          _buildDivider(context, 'Never worn - time to style these'),
          const SizedBox(height: 14),
          _buildNeverWorn(context),
        ],
      ),
    );
  }

  Widget _buildMostWorn(BuildContext context) {
    final t = context.themeTokens;
    final worn = wardrobe.where((i) => i.worn > 0).toList()
      ..sort((a, b) => b.worn.compareTo(a.worn));
    if (worn.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No wear logs yet',
            style: TextStyle(
              fontFamily: GoogleFonts.inter().fontFamily,
              fontSize: 13,
              color: t.mutedText,
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: worn
          .take(6)
          .map((item) => _MostWornHoverCard(item: item))
          .toList(),
    );
  }

  Widget _buildNeverWorn(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final neverWorn = wardrobe.where((i) => i.worn == 0).toList();
    if (neverWorn.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Everything has been worn - great work!',
          style: TextStyle(
            fontFamily: GoogleFonts.inter().fontFamily,
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: t.mutedText,
          ),
        ),
      );
    }
    return Column(
      children: neverWorn
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            t.accent.secondary.withValues(alpha: 0.12),
                            t.accent.primary.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _catEmoji(item.cat),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.cat,
                            style: TextStyle(
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontSize: 11,
                              color: t.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent4.withValues(alpha: 0.07),
                        border: Border.all(
                          color: accent4.withValues(alpha: 0.28),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Unworn',
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: accent4,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  static String _catEmoji(String cat) =>
      const {
        'Tops': 'TOP',
        'Bottoms': 'BOT',
        'Outerwear': 'OUT',
        'Footwear': 'SHO',
        'Dresses': 'DRS',
        'Accessories': 'ACC',
        'Bags': 'BAG',
        'Jewelry': 'JWL',
        'Makeup': 'MKP',
        'Skincare': 'SKN',
      }[cat] ??
      'ITM';

  Widget _buildDivider(BuildContext context, String label) => Row(
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: GoogleFonts.inter().fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.themeTokens.mutedText,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Divider(color: context.themeTokens.cardBorder, thickness: 1),
      ),
    ],
  );

  Widget _buildBars(BuildContext context) {
    final t = context.themeTokens;
    final accent4 = _accent4(t);
    final accent5 = _accent5(t);
    final bags = _bagsChip(t);
    final jewelry = _jewelryChip(t);
    final makeup = _makeupChip(t);
    final skincare = _skincareChip(t);

    final cats = [
      'Tops',
      'Bottoms',
      'Outerwear',
      'Footwear',
      'Dresses',
      'Accessories',
      'Bags',
      'Jewelry',
      'Makeup',
      'Skincare',
    ];
    final colors = [
      t.accent.primary,
      t.accent.secondary,
      t.accent.tertiary,
      accent5,
      accent4,
      t.accent.secondary,
      bags,
      jewelry,
      makeup,
      skincare,
    ];
    final counts = cats
        .map((c) => wardrobe.where((i) => i.cat == c).length)
        .toList();
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    return _BarSection(
      bars: List.generate(
        cats.length,
        (i) => _BarItem(
          label: cats[i],
          color: colors[i],
          value: max > 0 ? counts[i] / max : 0,
        ),
      ),
    );
  }
}

class _MostWornHoverCard extends StatefulWidget {
  final WardrobeItem item;
  const _MostWornHoverCard({required this.item});

  @override
  State<_MostWornHoverCard> createState() => _MostWornHoverCardState();
}

class _MostWornHoverCardState extends State<_MostWornHoverCard> {
  bool _hovered = false;

  static String _catEmoji(String cat) =>
      const {
        'Tops': 'TOP',
        'Bottoms': 'BOT',
        'Outerwear': 'OUT',
        'Footwear': 'SHO',
        'Dresses': 'DRS',
        'Accessories': 'ACC',
        'Bags': 'BAG',
        'Jewelry': 'JWL',
        'Makeup': 'MKP',
        'Skincare': 'SKN',
      }[cat] ??
      'ITM';

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: const Cubic(0.34, 1.32, 0.64, 1),
        transform: _hovered
            ? Matrix4.translationValues(0.0, -2.0, 0.0)
            : Matrix4.identity(),
        width: 100,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.cardBorder),
        ),
        child: Column(
          children: [
            Text(
              _catEmoji(widget.item.cat),
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 6),
            Text(
              widget.item.name,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.item.worn} worn',
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 10,
                color: t.accent.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverStatCard extends StatefulWidget {
  final LinearGradient gradient;
  final Color iconBg;
  final String iconChar;
  final String number;
  final String label;
  final String sub;
  const _HoverStatCard({
    required this.gradient,
    required this.iconBg,
    required this.iconChar,
    required this.number,
    required this.label,
    required this.sub,
  });

  @override
  State<_HoverStatCard> createState() => _HoverStatCardState();
}

class _HoverStatCardState extends State<_HoverStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        transform: _hovered
            ? (Matrix4.translationValues(0.0, -2.0, 0.0)
                ..multiply(Matrix4.diagonal3Values(1.01, 1.01, 1.0)))
            : Matrix4.identity(),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: t.backgroundPrimary.withValues(alpha: 0.4),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: t.backgroundPrimary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: widget.iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  widget.iconChar,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.number,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.sub,
              style: TextStyle(
                fontFamily: GoogleFonts.inter().fontFamily,
                fontSize: 12,
                color: t.textPrimary.withValues(alpha: 0.75),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarItem {
  final String label;
  final Color color;
  final double value;
  const _BarItem({
    required this.label,
    required this.color,
    required this.value,
  });
}

class _BarSection extends StatefulWidget {
  final List<_BarItem> bars;
  const _BarSection({required this.bars});

  @override
  State<_BarSection> createState() => _BarSectionState();
}

class _BarSectionState extends State<_BarSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Column(
        children: widget.bars
            .map(
              (bar) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        bar.label,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 13,
                          color: t.mutedText,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: t.panel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: bar.value.clamp(0.0, 1.0) * _anim.value,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  bar.color.withValues(alpha: 0.7),
                                  bar.color,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${(bar.value * 100).round()}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          fontSize: 12,
                          color: t.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ CUSTOM PAINTERS ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _ChevronLeftPainter extends CustomPainter {
  final Color color;
  const _ChevronLeftPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.7, 0)
        ..lineTo(size.width * 0.2, size.height / 2)
        ..lineTo(size.width * 0.7, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ LENS SHEET ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _WardrobeLensSheet extends StatelessWidget {
  final AppThemeTokens t;
  const _WardrobeLensSheet({required this.t});

  @override
  Widget build(BuildContext context) {
    final accent = t.accent.primary;
    final accentSecondary = t.accent.secondary;
    final textHeading = t.textPrimary;
    final textMuted = t.mutedText;
    final panel = t.panel;
    final surface = t.phoneShellInner;
    final bgSecondary = t.backgroundSecondary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface, bgSecondary],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 48,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(Icons.search, color: accent, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AHVI Lens',
                      style: TextStyle(
                        fontFamily: GoogleFonts.inter().fontFamily,
                        color: textHeading,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.20),
                        width: 1,
                      ),
                    ),
                    child: Icon(Icons.close, color: textMuted, size: 14),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panel,
              border: Border.all(
                color: accent.withValues(alpha: 0.15),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    color: accent.withValues(alpha: 0.08),
                  ),
                  child: Icon(Icons.circle, color: accent, size: 12),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visual AI Search',
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          color: textHeading,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Point at any item to find, save, or get styling advice.',
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          color: textMuted,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _WardrobeLensOption(
            icon: Icons.search,
            name: 'Find Similar',
            desc: 'Discover similar items with shopping links',
            color: accent,
            textHeading: textHeading,
            textMuted: textMuted,
            panel: panel,
            accentBorder: accent,
            onTap: () => Navigator.pop(context),
          ),
          _WardrobeLensOption(
            icon: Icons.add_photo_alternate_outlined,
            name: 'Add to Wardrobe',
            desc: 'Save to your collection',
            color: accentSecondary,
            textHeading: textHeading,
            textMuted: textMuted,
            panel: panel,
            accentBorder: accent,
            onTap: () {
              Navigator.pop(context);
              showAddToWardrobeModal(context);
            },
          ),
        ],
      ),
    );
  }
}

class _WardrobeLensOption extends StatefulWidget {
  final IconData icon;
  final String name;
  final String desc;
  final Color color;
  final Color textHeading;
  final Color textMuted;
  final Color panel;
  final Color accentBorder;
  final VoidCallback onTap;

  const _WardrobeLensOption({
    required this.icon,
    required this.name,
    required this.desc,
    required this.color,
    required this.textHeading,
    required this.textMuted,
    required this.panel,
    required this.accentBorder,
    required this.onTap,
  });

  @override
  State<_WardrobeLensOption> createState() => _WardrobeLensOptionState();
}

class _WardrobeLensOptionState extends State<_WardrobeLensOption> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.08)
                  : widget.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.30)
                    : widget.accentBorder.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          color: widget.textHeading,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.desc,
                        style: TextStyle(
                          fontFamily: GoogleFonts.inter().fontFamily,
                          color: widget.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  transform: Matrix4.translationValues(
                    _hovered ? 3.0 : 0.0,
                    0,
                    0,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _hovered ? widget.color : widget.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
//  ASK AHVI FAB ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â same button, font, icon, position as skincare screen
// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
class _AskAhviFab extends StatefulWidget {
  final VoidCallback onTap;
  const _AskAhviFab({required this.onTap});

  @override
  State<_AskAhviFab> createState() => _AskAhviFabState();
}

class _AskAhviFabState extends State<_AskAhviFab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  bool _pressed = false;
  bool _isRouteActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause animation when app goes to background to reduce janking
    if (state == AppLifecycleState.paused) {
      _pulseCtrl.stop();
    } else if (state == AppLifecycleState.resumed && _isRouteActive) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat();
    }
  }

  // FIX: Stop pulse animation when the route is not in the foreground so it
  // does not fire AnimatedBuilder callbacks during back-swipe transitions.
  // Enhanced with state tracking to prevent redundant animation control calls.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final routeActive = route?.isCurrent ?? false;

    // Only update if the route state actually changed
    if (routeActive != _isRouteActive) {
      _isRouteActive = routeActive;

      if (!_isRouteActive) {
        _pulseCtrl.stop();
      } else if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Pulse ring
              Positioned.fill(
                child: Opacity(
                  opacity: _pulseOpacity.value,
                  child: Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: t.accent.primary.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
            decoration: BoxDecoration(
              color: t.accent.primary,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: t.accent.primary.withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  AppLocalizations.t(context, 'ask_ahvi'),
                  style: GoogleFonts.anton(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
