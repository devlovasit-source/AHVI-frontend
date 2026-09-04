import 'package:flutter/foundation.dart';

class ResolvedWardrobeImage {
  final String? url;
  final String field;
  final String sourceKind;
  final int tier;
  final bool expectedTransparent;
  final bool validated;
  final bool shouldFrame;

  /// Ordered fallback candidates (highest-priority first) for Style-board
  /// surfaces only; empty elsewhere. Each entry carries its own provenance so
  /// a runtime image failure can advance to the next source and reframe.
  /// The list's first entry equals this result.
  final List<ResolvedWardrobeImage> candidates;

  const ResolvedWardrobeImage({
    required this.url,
    required this.field,
    required this.sourceKind,
    required this.tier,
    required this.expectedTransparent,
    required this.validated,
    required this.shouldFrame,
    this.candidates = const [],
  });

  bool get usedMasked => sourceKind == 'masked';
  bool get requiresFrame => shouldFrame;
}

class _Candidate {
  final String field;
  final String? url;
  final String sourceKind;
  final int tier;
  final bool expectedTransparent;
  final bool validated;

  const _Candidate(
    this.field,
    this.url,
    this.sourceKind,
    this.tier,
    this.expectedTransparent,
    this.validated,
  );
}

final Set<String> _diagnosticKeys = <String>{};

@visibleForTesting
void resetWardrobeImageDiagnosticCache() => _diagnosticKeys.clear();

String? _clean(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

String _status(Map<String, dynamic> raw, String snake, String camel) =>
    _clean(raw[snake] ?? raw[camel])?.toLowerCase() ?? '';

bool _objectPathMatches(String? url, RegExp pattern) {
  if (url == null) return false;
  final path = Uri.tryParse(url)?.path ?? url.split(RegExp(r'[?#]')).first;
  try {
    return pattern.hasMatch(Uri.decodeComponent(path));
  } on FormatException {
    return pattern.hasMatch(path);
  }
}

// Style-board canvases render garments frameless, so they must prefer clean
// transparent cutouts (validated_cutout=0, legacy_masked=1) over the opaque
// catalog image (3). The wardrobe grid keeps catalog-first for consistent
// photography. Surface is passed explicitly by callers — never inferred.
// Garment-only sources a Style board may render. Everything else — raw
// image_url / original uploads (often a selfie, mirror photo or scene) — is
// rejected on board surfaces so a person photo never lands on the editorial
// canvas. Catalog/normalized are product cutouts on white, so they qualify.
const Set<String> _boardSafeSourceKinds = {
  'validated_cutout',
  'legacy_masked_cutout',
  'style_asset_cutout',
  'style_asset_processed',
  'catalog_fallback',
  'masked',
  'processed_cutout',
};

bool _isStyleBoardSurface(String surface) {
  final s = surface.trim().toLowerCase();
  return s.startsWith('style_board') ||
      s.startsWith('style_this') ||
      s == 'build_outfit' ||
      s == 'boards';
}

// The live Style This grid must show the backend's normalized/catalog asset
// first (backend's own supporting-piece ordering is normalized_url ->
// masked_url -> image_url) -- the generic board tier ranking below prefers
// cutout/board assets over normalized, which let a stale board_image_url
// alias (e.g. a leftover backpack asset) win over the correct normalized
// image once this surface started being treated as a board surface.
bool _isStyleThisPresentationSurface(String surface) =>
    surface.trim().toLowerCase() == 'style_this_unified_grid';

bool _isCatalogObject(String? url) => _objectPathMatches(
  url,
  RegExp(
    r'(?:^|/)catalog_[^/]*\.(?:png|jpe?g|webp)(?:$|/)',
    caseSensitive: false,
  ),
);

String? _urlIdentity(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return url;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port${uri.path}';
}

List<String> wardrobeItemStableIds(Map<String, dynamic> raw) => <String>{
  for (final value in [
    raw['item_id'],
    raw['id'],
    raw[r'$id'],
    raw['itemId'],
    raw['image_id'],
    raw['imageId'],
    raw['asset_id'],
    raw['wardrobe_item_id'],
    raw['wardrobeItemId'],
  ])
    if (_clean(value) != null) _clean(value)!,
}.toList(growable: false);

String wardrobeItemStableId(Map<String, dynamic> raw) {
  final ids = wardrobeItemStableIds(raw);
  return ids.isEmpty ? '' : ids.first;
}

Map<String, Map<String, dynamic>> buildWardrobeImageMap(
  Iterable<Map<String, dynamic>> items,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final item in items) {
    for (final id in wardrobeItemStableIds(item)) {
      byId[id] = item;
    }
  }
  return byId;
}

ResolvedWardrobeImage resolveWardrobeImage(
  Map<String, dynamic> raw, {
  String? normalizedUrl,
  String? imageUrl,
  String? maskedUrl,
  String surface = 'wardrobe',
  String itemId = '',
  bool emitDiagnostic = true,
  Map<String, dynamic>? wardrobeRecord,
}) {
  final boardStatus = _status(raw, 'board_status', 'boardStatus');
  final cutoutStatus = _status(raw, 'cutout_status', 'cutoutStatus');
  final imageStatus = _status(raw, 'image_status', 'imageStatus');
  final wardrobe = wardrobeRecord ?? const <String, dynamic>{};
  final wardrobeBoardStatus = _status(wardrobe, 'board_status', 'boardStatus');
  final wardrobeCutoutStatus = _status(
    wardrobe,
    'cutout_status',
    'cutoutStatus',
  );
  final wardrobeImageStatus = _status(wardrobe, 'image_status', 'imageStatus');
  final cutoutReady = cutoutStatus == 'ready';
  final boardReady = boardStatus == 'cutout_ready';
  final rmbgReady = imageStatus == 'rmbg_complete';
  final wardrobeCutoutReady = wardrobeCutoutStatus == 'ready';
  final wardrobeBoardReady = wardrobeBoardStatus == 'cutout_ready';
  final wardrobeRmbgReady = wardrobeImageStatus == 'rmbg_complete';
  final source =
      (_clean(raw['source'] ?? raw['item_source'] ?? raw['itemSource']) ?? '')
          .toLowerCase();
  final isStyleAsset = const {
    'style_asset',
    'style_assets',
    'shared_asset',
    'shared_assets',
    'asset',
    'asset_library',
    'curated',
    'style-library',
    'style_library',
  }.contains(source);
  final originalUrls = <String>{
    ...[
      imageUrl,
      raw['image_url'],
      raw['imageUrl'],
      raw['original_image_url'],
      raw['originalImageUrl'],
      raw['raw_url'],
      raw['rawUrl'],
      raw['preview_url'],
      raw['previewUrl'],
    ].map(_clean).whereType<String>(),
  };

  final boardImage = _clean(raw['board_image_url'] ?? raw['boardImageUrl']);
  final cutoutImage = _clean(raw['cutout_url'] ?? raw['cutoutUrl']);
  final resolvedMasked = _clean(
    maskedUrl ?? raw['masked_url'] ?? raw['maskedUrl'],
  );
  final maskedImage = _clean(raw['masked_image_url'] ?? raw['maskedImageUrl']);
  final wardrobeBoardImage = _clean(
    wardrobe['board_image_url'] ?? wardrobe['boardImageUrl'],
  );
  final wardrobeCutoutImage = _clean(
    wardrobe['cutout_url'] ?? wardrobe['cutoutUrl'],
  );
  final wardrobeMasked = _clean(
    wardrobe['masked_url'] ?? wardrobe['maskedUrl'],
  );
  final wardrobeMaskedImage = _clean(
    wardrobe['masked_image_url'] ?? wardrobe['maskedImageUrl'],
  );
  final rmbgImage = _clean(raw['rmbg_url'] ?? raw['rmbgUrl']);
  final transparentImage = _clean(
    raw['transparent_image_url'] ?? raw['transparentImageUrl'],
  );
  final processedImage = _clean(raw['processed_url'] ?? raw['processedUrl']);
  final wardrobeRmbgImage = _clean(wardrobe['rmbg_url'] ?? wardrobe['rmbgUrl']);
  final assetCutoutImage = _clean(
    raw['asset_cutout_url'] ?? raw['assetCutoutUrl'] ?? raw['cutout_url'],
  );
  final assetMaskedImage = _clean(
    raw['asset_masked_url'] ??
        raw['assetMaskedUrl'] ??
        raw['transparent_url'] ??
        raw['transparentUrl'] ??
        raw['transparent_image_url'] ??
        raw['transparentImageUrl'],
  );
  final assetProcessedImage = _clean(
    raw['processed_asset_url'] ??
        raw['processedAssetUrl'] ??
        raw['processed_image_url'] ??
        raw['processedImageUrl'] ??
        raw['processed_url'] ??
        raw['processedUrl'],
  );
  final wardrobeOriginalUrls = <String>{
    ...[
      wardrobe['image_url'],
      wardrobe['imageUrl'],
      wardrobe['original_image_url'],
      wardrobe['originalImageUrl'],
      wardrobe['raw_url'],
      wardrobe['rawUrl'],
      wardrobe['preview_url'],
      wardrobe['previewUrl'],
    ].map(_clean).whereType<String>(),
  };
  final catalogUrls = <String>{
    ...[
      normalizedUrl,
      raw['normalized_url'],
      raw['normalizedUrl'],
      raw['normalized_image_url'],
      raw['normalizedImageUrl'],
      raw['catalog_image_url'],
      raw['catalogImageUrl'],
      raw['display_image_url'],
      raw['displayImageUrl'],
    ].map(_clean).whereType<String>(),
  };
  final wardrobeCatalogUrls = <String>{
    ...[
      wardrobe['normalized_url'],
      wardrobe['normalizedUrl'],
      wardrobe['normalized_image_url'],
      wardrobe['normalizedImageUrl'],
      wardrobe['catalog_image_url'],
      wardrobe['catalogImageUrl'],
      wardrobe['display_image_url'],
      wardrobe['displayImageUrl'],
    ].map(_clean).whereType<String>(),
  };
  final allOriginalUrls = {...originalUrls, ...wardrobeOriginalUrls};
  final allOriginalUrlIds = allOriginalUrls
      .map(_urlIdentity)
      .whereType<String>()
      .toSet();
  final frozenOriginalUrlIds = <String>{
    ...wardrobeOriginalUrls,
    ...[
      raw['original_image_url'],
      raw['originalImageUrl'],
      raw['raw_url'],
      raw['rawUrl'],
      raw['preview_url'],
      raw['previewUrl'],
    ].map(_clean).whereType<String>(),
  }.map(_urlIdentity).whereType<String>().toSet();
  final allCatalogUrlIds = {
    ...catalogUrls,
    ...wardrobeCatalogUrls,
  }.map(_urlIdentity).whereType<String>().toSet();
  bool isOriginalAlias(String? url) =>
      url != null && allOriginalUrlIds.contains(_urlIdentity(url));
  bool isFrozenOriginalAlias(String? url) =>
      url != null && frozenOriginalUrlIds.contains(_urlIdentity(url));
  bool isCatalogAlias(String? url) =>
      url != null && allCatalogUrlIds.contains(_urlIdentity(url));
  final maskedIsOriginal =
      resolvedMasked != null && isOriginalAlias(resolvedMasked);
  final maskedImageIsOriginal =
      maskedImage != null && isOriginalAlias(maskedImage);
  final wardrobeMaskedIsOriginal =
      wardrobeMasked != null && isOriginalAlias(wardrobeMasked);
  final wardrobeMaskedImageIsOriginal =
      wardrobeMaskedImage != null && isOriginalAlias(wardrobeMaskedImage);
  final maskedIsCatalog = _isCatalogObject(resolvedMasked);
  final maskedImageIsCatalog = _isCatalogObject(maskedImage);
  final wardrobeMaskedIsCatalog = _isCatalogObject(wardrobeMasked);
  final wardrobeMaskedImageIsCatalog = _isCatalogObject(wardrobeMaskedImage);
  bool rawCutoutIsSafe(String? url) =>
      url != null &&
      !isOriginalAlias(url) &&
      !isCatalogAlias(url) &&
      !_isCatalogObject(url);
  bool wardrobeCutoutIsSafe(String? url) =>
      url != null &&
      !isOriginalAlias(url) &&
      !isCatalogAlias(url) &&
      !_isCatalogObject(url);
  final frozenField = _clean(raw['selected_field']);
  final frozenSource = _clean(raw['source_kind']);
  final frozenUrl = frozenField != null && frozenSource != null
      ? _clean(raw['image_url'] ?? raw['imageUrl'])
      : null;
  final frozenIsCatalog = _isCatalogObject(frozenUrl);
  final frozenExpected = raw['expected_transparent'] == true;
  final frozenValidated =
      frozenExpected &&
      const {
        'validated_cutout',
        'legacy_masked_cutout',
        'style_asset_cutout',
        'masked',
        'processed_cutout',
      }.contains(frozenSource);

  String fallbackKind(String? url) =>
      _isCatalogObject(url) ? 'catalog_fallback' : 'original';
  int fallbackTier(String? url) => _isCatalogObject(url) ? 3 : 4;
  int frozenTier(String source) => switch (source) {
    'validated_cutout' || 'style_asset_cutout' => 0,
    'legacy_masked_cutout' || 'masked' => 1,
    'processed_cutout' => 2,
    'catalog_fallback' || 'style_asset_processed' => 3,
    _ => 4,
  };
  final isStyleThisPresentation = _isStyleThisPresentationSurface(surface);
  final isBoardSurface = _isStyleBoardSurface(surface) || isStyleThisPresentation;
  bool explicitMaskIsSafeForBoard(String? url) =>
      isBoardSurface &&
      url != null &&
      // A masked_url that aliases the raw upload is a fabricated cutout (the
      // backend copies image_url into masked_url when RMBG produced nothing) —
      // often a selfie. Never admit it to a board surface.
      !isOriginalAlias(url) &&
      !isCatalogAlias(url) &&
      !_isCatalogObject(url);

  // Prefer the polished catalog image whenever a real one exists — for the
  // wardrobe grid AND Style This boards (the anchor's raw/bad cutout otherwise
  // shows on the board). The winner is first-non-null in list order, so prepend
  // the catalog candidate. Style assets keep their own cutout-first pipeline.
  final catalogFirstUrl = _clean(
    normalizedUrl ??
        raw['normalized_url'] ??
        raw['normalizedUrl'] ??
        raw['catalog_image_url'] ??
        raw['catalogImageUrl'] ??
        wardrobe['normalized_url'] ??
        wardrobe['normalizedUrl'],
  );
  // The two unconditional "trust the field name" normalized_url fallbacks
  // below are labeled catalog_fallback (a board-safe source kind) without
  // verifying the URL is actually a distinct processed asset. When a wardrobe
  // item hasn't been through catalog/cutout processing, the backend can
  // alias normalized_url to the same raw upload as image_url -- admitting
  // that unfiltered would put a raw photo (cropped mirror/selfie shot) on a
  // Style board labeled as a safe catalog image. Reject the alias case here.
  final wardrobeNormalizedFallback = _clean(
    wardrobe['normalized_url'] ??
        wardrobe['normalizedUrl'] ??
        wardrobe['normalized_image_url'] ??
        wardrobe['normalizedImageUrl'],
  );
  final rawNormalizedFallback = _clean(
    normalizedUrl ??
        raw['normalized_url'] ??
        raw['normalizedUrl'] ??
        raw['normalized_image_url'] ??
        raw['normalizedImageUrl'],
  );
  final candidates = <_Candidate>[
    if (!isStyleAsset && _isCatalogObject(catalogFirstUrl))
      _Candidate(
        'normalized_url',
        catalogFirstUrl,
        'catalog_fallback',
        3,
        false,
        false,
      ),
    if (frozenUrl != null &&
        (!frozenValidated ||
            (!isCatalogAlias(frozenUrl) && !isFrozenOriginalAlias(frozenUrl))))
      _Candidate(
        frozenField!,
        frozenUrl,
        frozenIsCatalog ? 'catalog_fallback' : frozenSource!,
        frozenIsCatalog ? 3 : frozenTier(frozenSource!),
        frozenIsCatalog ? false : frozenExpected,
        frozenIsCatalog ? false : frozenValidated,
      ),
    if (isStyleAsset && rawCutoutIsSafe(assetCutoutImage))
      _Candidate(
        raw['asset_cutout_url'] != null ? 'asset_cutout_url' : 'cutout_url',
        assetCutoutImage,
        'style_asset_cutout',
        0,
        true,
        true,
      ),
    if (isStyleAsset && rawCutoutIsSafe(assetMaskedImage))
      _Candidate(
        raw['asset_masked_url'] != null
            ? 'asset_masked_url'
            : 'transparent_url',
        assetMaskedImage,
        'style_asset_cutout',
        1,
        true,
        true,
      ),
    if (isStyleAsset && assetProcessedImage != null)
      _Candidate(
        'processed_asset_url',
        assetProcessedImage,
        'style_asset_processed',
        3,
        false,
        false,
      ),
    if (isStyleAsset)
      _Candidate(
        'normalized_url',
        _clean(
          normalizedUrl ??
              raw['normalized_url'] ??
              raw['normalizedUrl'] ??
              raw['normalized_image_url'] ??
              raw['normalizedImageUrl'],
        ),
        'catalog_fallback',
        3,
        false,
        false,
      ),
    if (isStyleAsset)
      _Candidate(
        'image_url',
        _clean(imageUrl ?? raw['image_url'] ?? raw['imageUrl'] ?? raw['url']),
        'style_asset_original',
        4,
        false,
        false,
      ),
    if (!isStyleAsset && cutoutReady && rawCutoutIsSafe(cutoutImage))
      _Candidate('cutout_url', cutoutImage, 'validated_cutout', 0, true, true),
    if (!isStyleAsset &&
        wardrobeCutoutReady &&
        wardrobeCutoutIsSafe(wardrobeCutoutImage))
      _Candidate(
        'cutout_url',
        wardrobeCutoutImage,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        wardrobeRmbgReady &&
        wardrobeCutoutIsSafe(wardrobeMasked))
      _Candidate(
        'masked_url',
        wardrobeMasked,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset && rmbgReady && rawCutoutIsSafe(resolvedMasked))
      _Candidate(
        'masked_url',
        resolvedMasked,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset && wardrobeCutoutIsSafe(wardrobeMasked))
      _Candidate(
        'masked_url',
        wardrobeMasked,
        'legacy_masked_cutout',
        1,
        true,
        true,
      ),
    if (!isStyleAsset &&
        (rawCutoutIsSafe(resolvedMasked) ||
            explicitMaskIsSafeForBoard(resolvedMasked)))
      _Candidate(
        'masked_url',
        resolvedMasked,
        'legacy_masked_cutout',
        1,
        true,
        true,
      ),
    if (!isStyleAsset && boardReady && rawCutoutIsSafe(boardImage))
      _Candidate(
        'board_image_url',
        boardImage,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        wardrobeBoardReady &&
        wardrobeCutoutIsSafe(wardrobeBoardImage))
      _Candidate(
        'board_image_url',
        wardrobeBoardImage,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        wardrobeRmbgReady &&
        !wardrobeMaskedIsOriginal &&
        !isCatalogAlias(wardrobeMasked) &&
        !wardrobeMaskedIsCatalog)
      _Candidate(
        'masked_url',
        wardrobeMasked,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        wardrobeRmbgReady &&
        !wardrobeMaskedImageIsOriginal &&
        !isCatalogAlias(wardrobeMaskedImage) &&
        !wardrobeMaskedImageIsCatalog)
      _Candidate(
        'masked_image_url',
        wardrobeMaskedImage,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        rmbgReady &&
        !maskedIsOriginal &&
        !isCatalogAlias(resolvedMasked) &&
        !maskedIsCatalog)
      _Candidate(
        'masked_url',
        resolvedMasked,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        rmbgReady &&
        !maskedImageIsOriginal &&
        !isCatalogAlias(maskedImage) &&
        !maskedImageIsCatalog)
      _Candidate(
        'masked_image_url',
        maskedImage,
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset &&
        boardReady &&
        rawCutoutIsSafe(
          _clean(raw['image_url'] ?? raw['imageUrl'] ?? imageUrl),
        ))
      _Candidate(
        'image_url',
        _clean(raw['image_url'] ?? raw['imageUrl'] ?? imageUrl),
        'validated_cutout',
        0,
        true,
        true,
      ),
    if (!isStyleAsset && rmbgReady && rawCutoutIsSafe(rmbgImage))
      _Candidate('rmbg_url', rmbgImage, 'processed_cutout', 2, true, true),
    if (!isStyleAsset &&
        wardrobeRmbgReady &&
        wardrobeCutoutIsSafe(wardrobeRmbgImage))
      _Candidate(
        'rmbg_url',
        wardrobeRmbgImage,
        'processed_cutout',
        2,
        true,
        true,
      ),
    if (!isStyleAsset &&
        (boardReady || cutoutReady) &&
        rawCutoutIsSafe(transparentImage))
      _Candidate(
        'transparent_image_url',
        transparentImage,
        'processed_cutout',
        2,
        true,
        true,
      ),
    if (!isStyleAsset && rmbgReady && rawCutoutIsSafe(processedImage))
      _Candidate(
        'processed_url',
        processedImage,
        'processed_cutout',
        2,
        true,
        true,
      ),
    if (!isStyleAsset && !isOriginalAlias(wardrobeNormalizedFallback))
      _Candidate(
        'normalized_url',
        wardrobeNormalizedFallback,
        'catalog_fallback',
        3,
        false,
        false,
      ),
    if (!isStyleAsset && !isOriginalAlias(rawNormalizedFallback))
      _Candidate(
        'normalized_url',
        rawNormalizedFallback,
        'catalog_fallback',
        3,
        false,
        false,
      ),
    _Candidate(
      'catalog_image_url',
      _clean(raw['catalog_image_url'] ?? raw['catalogImageUrl']),
      'catalog_fallback',
      3,
      false,
      false,
    ),
    _Candidate(
      'display_image_url',
      _clean(raw['display_image_url'] ?? raw['displayImageUrl']),
      'catalog_fallback',
      3,
      false,
      false,
    ),
    if (maskedIsCatalog)
      _Candidate(
        'masked_url',
        resolvedMasked,
        'catalog_fallback',
        3,
        false,
        false,
      ),
    if (maskedImageIsCatalog)
      _Candidate(
        'masked_image_url',
        maskedImage,
        'catalog_fallback',
        3,
        false,
        false,
      ),
    _Candidate(
      'image_url',
      _clean(
        wardrobe['image_url'] ??
            wardrobe['imageUrl'] ??
            wardrobe['raw_url'] ??
            wardrobe['rawUrl'],
      ),
      'original',
      4,
      false,
      false,
    ),
    _Candidate(
      'board_image_url',
      boardImage,
      fallbackKind(boardImage),
      fallbackTier(boardImage),
      false,
      false,
    ),
    _Candidate(
      'cutout_url',
      cutoutImage,
      fallbackKind(cutoutImage),
      fallbackTier(cutoutImage),
      false,
      false,
    ),
    for (final fallback in <(String, String?)>[
      ('rmbg_url', rmbgImage),
      ('transparent_image_url', transparentImage),
      ('processed_url', processedImage),
      ('rmbg_url', wardrobeRmbgImage),
    ])
      _Candidate(
        fallback.$1,
        fallback.$2,
        fallbackKind(fallback.$2),
        fallbackTier(fallback.$2),
        false,
        false,
      ),
    if (!maskedIsOriginal && !maskedIsCatalog)
      _Candidate(
        'masked_url',
        resolvedMasked,
        fallbackKind(resolvedMasked),
        fallbackTier(resolvedMasked),
        false,
        false,
      ),
    if (!maskedImageIsOriginal && !maskedImageIsCatalog)
      _Candidate(
        'masked_image_url',
        maskedImage,
        fallbackKind(maskedImage),
        fallbackTier(maskedImage),
        false,
        false,
      ),
    _Candidate(
      'image_url',
      _clean(imageUrl ?? raw['image_url'] ?? raw['imageUrl']),
      'original',
      4,
      false,
      false,
    ),
    _Candidate(
      'raw_url',
      _clean(raw['raw_url'] ?? raw['rawUrl']),
      'original',
      4,
      false,
      false,
    ),
    _Candidate(
      'preview_url',
      _clean(raw['preview_url'] ?? raw['previewUrl']),
      'original',
      4,
      false,
      false,
    ),
    _Candidate(
      'url',
      _clean(raw['url'] ?? raw['thumbnailUrl']),
      'original',
      4,
      false,
      false,
    ),
  ];

  final available = candidates.where((c) => c.url != null).toList();
  // Admission guard: board surfaces drop raw/original candidates entirely, so
  // a missing cutout can never fall through to a person photo. If nothing
  // garment-only survives, the item resolves to no image and the renderer
  // omits it (never a raw upload). The wardrobe grid keeps every candidate.
  final boardPool = isBoardSurface
      ? available
            .where((c) => _boardSafeSourceKinds.contains(c.sourceKind))
            .toList()
      : available;
  final rejectedUnsafe = isBoardSurface
      ? available.length - boardPool.length
      : 0;
  final selected = boardPool.isEmpty
      ? const _Candidate('none', null, 'missing', 5, false, false)
      : isStyleThisPresentation
      // Style This live grid: normalized/catalog asset first (matches the
      // backend's own normalized_url -> masked_url -> image_url ordering for
      // supporting pieces), falling back to the board-safe cutout ranking
      // below only when no normalized candidate survived admission.
      ? boardPool.firstWhere(
          (c) => c.field == 'normalized_url',
          orElse: () => boardPool.reduce((a, b) => b.tier < a.tier ? b : a),
        )
      : isBoardSurface
      // Board canvas: cutout-first over garment-only sources. `tier` is a
      // priority RANK, lower = higher preference (validated_cutout=0,
      // legacy_masked=1, catalog=3) — not a quality score. Minimum-rank wins;
      // reduce is stable on ties.
      ? boardPool.reduce((a, b) => b.tier < a.tier ? b : a)
      // Wardrobe grid etc: keep catalog-first (first non-null in order).
      : boardPool.first;
  // Ordered fallback candidates — board surfaces only. Rank order (lower tier
  // first, stable within a tier), deduped by URL identity. The renderer walks
  // this list when the preferred image fails at runtime.
  List<ResolvedWardrobeImage> boardCandidates() {
    if (!isBoardSurface || boardPool.isEmpty) return const [];
    final ordered = [
      for (var t = 0; t <= 5; t++) ...boardPool.where((c) => c.tier == t),
    ];
    final strongestByUrl = <String, _Candidate>{};
    for (final c in ordered) {
      final id = _urlIdentity(c.url) ?? c.url;
      if (id == null) continue;
      final existing = strongestByUrl[id];
      if (existing == null || c.tier < existing.tier) {
        strongestByUrl[id] = c;
      }
    }
    final out = <ResolvedWardrobeImage>[];
    for (final c in strongestByUrl.values) {
      out.add(
        ResolvedWardrobeImage(
          url: c.url,
          field: c.field,
          sourceKind: c.sourceKind,
          tier: c.tier,
          expectedTransparent: c.expectedTransparent,
          validated: c.validated,
          shouldFrame: c.url != null && !c.validated,
        ),
      );
    }
    return out;
  }

  final result = ResolvedWardrobeImage(
    url: selected.url,
    field: selected.field,
    sourceKind: selected.sourceKind,
    tier: selected.tier,
    expectedTransparent: selected.expectedTransparent,
    validated: selected.validated,
    shouldFrame: selected.url != null && !selected.validated,
    candidates: boardCandidates(),
  );

  if (emitDiagnostic) {
    final diagnosticId = itemId.trim().isNotEmpty
        ? itemId.trim()
        : _clean(raw['item_id'] ?? raw['id'] ?? raw[r'$id']) ?? 'unknown';
    final key = '$diagnosticId|$surface|${result.field}|${result.sourceKind}';
    if (_diagnosticKeys.add(key)) {
      String fingerprint(Object? value) {
        final clean = _clean(value);
        if (clean == null) return 'none';
        var hash = 0x811c9dc5;
        for (final codeUnit in clean.codeUnits) {
          hash ^= codeUnit;
          hash = (hash * 0x01000193) & 0xffffffff;
        }
        return hash.toRadixString(16).padLeft(8, '0');
      }

      Object? compared(String snake, String camel) =>
          raw[snake] ?? raw[camel] ?? wardrobe[snake] ?? wardrobe[camel];
      debugPrint(
        'AHVI_IMAGE_SELECTION_DECISION '
        'item_id=$diagnosticId '
        'surface=$surface '
        'source=${isStyleAsset ? "style_asset" : "wardrobe"} '
        'selected_field=${result.field} '
        'reason=${switch (result.sourceKind) {
          "validated_cutout" => "validated_cutout",
          "legacy_masked_cutout" => "legacy_masked",
          "style_asset_cutout" => "asset_cutout",
          "catalog_fallback" => "catalog_fallback",
          _ => "original",
        }} '
        'expected_transparent=${result.expectedTransparent} '
        'requires_frame=${result.requiresFrame}',
      );
      debugPrint(
        'AHVI_IMAGE_FIELD_COMPARE '
        'item_id=$diagnosticId '
        'board_image_url_fp=${fingerprint(compared('board_image_url', 'boardImageUrl'))} '
        'masked_url_fp=${fingerprint(compared('masked_url', 'maskedUrl'))} '
        'normalized_url_fp=${fingerprint(compared('normalized_url', 'normalizedUrl'))} '
        'image_url_fp=${fingerprint(compared('image_url', 'imageUrl'))} '
        'selected_field=${result.field} '
        'source_kind=${result.sourceKind} '
        'expected_transparent=${result.expectedTransparent}',
      );
      debugPrint(
        'AHVI_WARDROBE_IMAGE_RESOLVE '
        'item_id=$diagnosticId '
        'surface=$surface '
        'selected_field=${result.field} '
        'source_kind=${result.sourceKind} '
        'expected_transparent=${result.expectedTransparent}',
      );
      if (isBoardSurface) {
        debugPrint(
          'AHVI_STYLE_ITEM_IMAGE_SELECTED '
          'item_id=$diagnosticId '
          'surface=$surface '
          'selected_field=${result.field} '
          'source_kind=${result.sourceKind} '
          'expected_transparent=${result.expectedTransparent} '
          'requires_frame=${result.requiresFrame} '
          'candidate_count=${boardPool.length} '
          'rejected_unsafe=$rejectedUnsafe',
        );
      }
    }
  }
  return result;
}

/// Ordered fallback candidates (highest-priority first) for a Style-board
/// surface; empty for non-board surfaces. Same selection logic as
/// [resolveWardrobeImage] — this just exposes the whole ordered list so a
/// renderer can advance on runtime image failure. See
/// [ResolvedWardrobeImage.candidates].
List<ResolvedWardrobeImage> resolveWardrobeImageCandidates(
  Map<String, dynamic> raw, {
  String? normalizedUrl,
  String? imageUrl,
  String? maskedUrl,
  String surface = 'style_board_render',
  String itemId = '',
  Map<String, dynamic>? wardrobeRecord,
}) => resolveWardrobeImage(
  raw,
  normalizedUrl: normalizedUrl,
  imageUrl: imageUrl,
  maskedUrl: maskedUrl,
  surface: surface,
  itemId: itemId,
  emitDiagnostic: false,
  wardrobeRecord: wardrobeRecord,
).candidates;

Map<String, dynamic> resolveStyleBoardItemImage(
  Map<String, dynamic> item,
  Map<String, Map<String, dynamic>> wardrobeById, {
  required String surface,
  bool emitDiagnostic = true,
}) {
  final id = wardrobeItemStableId(item);
  final result = resolveWardrobeImage(
    item,
    surface: surface,
    itemId: id,
    emitDiagnostic: emitDiagnostic,
    wardrobeRecord: id.isEmpty ? null : wardrobeById[id],
  );
  final originalImage = _clean(item['image_url'] ?? item['imageUrl']);
  return <String, dynamic>{
    ...item,
    if (originalImage != null &&
        originalImage != result.url &&
        _clean(item['original_image_url'] ?? item['originalImageUrl']) == null)
      'original_image_url': originalImage,
    if (result.url != null && result.field != 'none') result.field: result.url,
    if (result.url != null) 'image_url': result.url,
    'selected_field': result.field,
    'source_kind': result.sourceKind,
    'expected_transparent': result.expectedTransparent,
    '_image_should_frame': result.shouldFrame,
    '_image_source_kind': result.sourceKind,
    '_image_expected_transparent': result.expectedTransparent,
  };
}
