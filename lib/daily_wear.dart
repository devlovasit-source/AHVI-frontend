import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/feature/chat/widgets/ahvi_processing_bubble.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/home_card_summary_provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/location_context_service.dart';
import 'package:myapp/tryon_safety.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/board_exporter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/style_board/saved_board_persistence.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/basic_markdown_text.dart';
import 'package:myapp/widgets/clear_chat_dialog.dart';
import 'package:myapp/widgets/try_on_coming_soon.dart';
import 'package:myapp/widgets/ahvi_unified_outfit_grid.dart';

enum _TryOnStage { preview, loading, camera, captured }

/// (canonicalBucket, label, icon) options for the Daily Wear save sheet.
/// Buckets must be members of [savedBoardBuckets] -- no invented strings.
const dailyWearSaveOccasionOptions = <(String, String, IconData)>[
  ('everything_else', 'Daily Wear', Icons.wb_sunny_outlined),
  ('party_looks', 'Party Looks', Icons.celebration_rounded),
  ('office_fits', 'Office Fits', Icons.work_outline_rounded),
  ('vacation', 'Vacation & Travel', Icons.flight_takeoff_rounded),
  ('occasion', 'Occasions & Events', Icons.diamond_outlined),
  ('everything_else', 'Everything Else', Icons.auto_awesome_rounded),
];

List<Map<String, dynamic>> buildDailyWearSaveItems(StyleBoardData board) {
  return board.items
      .map((item) {
        final saved = Map<String, dynamic>.from(item.raw)
          ..['id'] = item.id
          ..['item_id'] = item.id
          ..['role'] = item.role.name
          ..['name'] = item.name
          ..['source'] = item.source;
        final originalImage = (saved['image_url'] ?? saved['imageUrl'])
            ?.toString()
            .trim();
        final resolved = item.resolveImage(surface: 'style_board');
        if (originalImage != null &&
            originalImage.isNotEmpty &&
            resolved.field != 'image_url') {
          saved['original_image_url'] = originalImage;
        }
        if (resolved.field != 'image_url') {
          saved.remove('image_url');
          saved.remove('imageUrl');
        }
        if (item.maskedUrl.isNotEmpty) saved['masked_url'] = item.maskedUrl;
        if (item.normalizedUrl.isNotEmpty) {
          saved['normalized_url'] = item.normalizedUrl;
        }
        if (item.boardImageUrl.isNotEmpty) {
          saved['board_image_url'] = item.boardImageUrl;
        }
        if (resolved.field == 'image_url' && resolved.url != null) {
          saved['image_url'] = resolved.url;
        }
        saved[savedBoardAuthoritativeImageKey] = resolved;
        return saved;
      })
      .toList(growable: false);
}

class DailyWearScreen extends StatefulWidget {
  const DailyWearScreen({super.key});

  /// Returns the first non-empty list from board_items, composition_items,
  /// used_wardrobe_items, or items in exact precedence order.
  static List<dynamic> firstNonEmptyBoardItems(Map<String, dynamic> outfit) {
    for (final key in [
      'board_items',
      'composition_items',
      'used_wardrobe_items',
      'items',
    ]) {
      final val = outfit[key];
      if (val is List && val.isNotEmpty) {
        return val;
      }
    }
    return const [];
  }

  /// Resolves the coordinates DailyWear's weather request should use.
  ///
  /// Tries [locationLookup] (defaults to the shared [LocationContextService])
  /// and falls back to [fallbackLat]/[fallbackLon] on denied/disabled
  /// permission, a lookup error, or a null/invalid fix. Bounded by an
  /// explicit timeout so a stalled GPS lookup never blocks weather forever.
  static Future<({double lat, double lon})> resolveWeatherCoordinates({
    Future<Map<String, dynamic>> Function()? locationLookup,
    double fallbackLat = 16.5062,
    double fallbackLon = 80.648,
  }) async {
    final lookup =
        locationLookup ?? () => LocationContextService().getLocationContext();
    try {
      final ctx = await lookup().timeout(const Duration(seconds: 12));
      final lat = ctx['lat'];
      final lon = ctx['lon'];
      if (lat is num && lon is num) {
        return (lat: lat.toDouble(), lon: lon.toDouble());
      }
    } catch (_) {
      // Denied/disabled/timeout/unavailable/unexpected error: keep fallback.
    }
    return (lat: fallbackLat, lon: fallbackLon);
  }

  @override
  State<DailyWearScreen> createState() => _DailyWearScreenState();
}

/// Maps a BackendService.getCurrentWeather() response onto the (temp, feel,
/// code) triple _applyWeather expects. The canonical /api/weather proxy
/// requests temperature_2m/weather_code/wind_speed_10m from Open-Meteo and
/// does not currently guarantee an apparent/feels-like value, so feel falls
/// back to actual temperature rather than inventing one. Throws StateError
/// on an unavailable/malformed response; callers must catch and treat the
/// weather as honestly unavailable -- never substitute a fabricated value.
({int temp, int feel, int code}) mapDailyWearWeather(
  Map<String, dynamic> weather,
) {
  if (weather['status'] != 'available') {
    throw StateError(weather['reason']?.toString() ?? 'weather_unavailable');
  }
  final raw = weather['raw'] as Map? ?? const {};
  final tempRaw = weather['temperature_c'] ?? weather['temperature'];
  final codeRaw = raw['code'] ?? weather['weather_code'];
  if (tempRaw is! num || codeRaw is! num) {
    throw StateError('weather_malformed');
  }
  // Feels-like is optional and not currently guaranteed by the backend
  // contract -- a missing or malformed value degrades to actual temperature
  // rather than discarding an otherwise-valid reading.
  final feelCandidate = raw['apparent_temperature'] ?? weather['feels_like_c'];
  final feelRaw = feelCandidate is num ? feelCandidate : tempRaw;
  return (temp: tempRaw.round(), feel: feelRaw.round(), code: codeRaw.toInt());
}

class _DailyWearScreenState extends State<DailyWearScreen>
    with TickerProviderStateMixin {
  AppThemeTokens get _t => context.themeTokens;
  Color get _cardBorder => _t.cardBorder;
  Color get _accent => _t.accent.primary;
  Color get _accent2 => _t.accent.secondary;
  Color get _accent3 => _t.accent.tertiary;
  Color get _accent4 => _t.accent.primary;
  Color get _accent5 => _t.accent.secondary;

  // Daily Wear is intentionally rendered as a bright editorial board in both
  // app themes. On Samsung night mode, dark/translucent tokens were being
  // composited into a permanent grey wash on this page.
  Color get bgColor => const Color(0xFFF9FBFF);
  Color get bg2Color => Colors.white;
  Color get panelColor => Colors.white;
  Color get panel2Color => const Color(0xFFE4EAF8);

  Color get cardBorderColor => _cardBorder;
  Color get textColor => const Color(0xFF1A1D26);
  Color get mutedColor => const Color(0xFF66708A);
  Color get accentColor => _accent;
  Color get accent2Color => _accent2;
  Color get accent3Color => _accent3;
  Color get accent4Color => _accent4;
  Color get accent5Color => _accent5;
  Color get tileTextColor => const Color(0xFF182031);
  Color get phoneShellColor => const Color(0xFFEEF2FB);
  Color get phoneShellInnerColor => const Color(0xFFF4F7FF);

  final ValueNotifier<int> _carouselIndexNotifier = ValueNotifier(0);
  int get _carouselIndex => _carouselIndexNotifier.value;
  bool _chatOpen = false;
  bool _tryOnOpen = false;
  bool _isLoading = true;
  bool _needsMoreClothes = false;
  // Distinct from _needsMoreClothes: a board-generation hiccup with no
  // explicit insufficient_wardrobe signal from the backend. Must never say
  // "add more clothes" -- the wardrobe may be perfectly fine.
  bool _loadUnavailable = false;
  String _emptyStateMessage = '';
  final PageController _pageController = PageController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Map<String, bool> _savedCarouselById = {};
  Map<String, bool> _savedOptionById = {};

  String? _wornOutfitId;
  Timer? _autoPlayTimer;
  bool _userScrolling = false;
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _quickPromptsVisible = true;
  Timer? _chatGreetingTimer;

  // ── Chat History ─────────────────────────────────────────────────────
  final List<_ChatSession> _chatHistory = [];
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final GlobalKey<ScaffoldState> _chatScaffoldKey = GlobalKey<ScaffoldState>();

  int? _speakingMessageId;

  // ── Plus button ───────────────────────────────────────────────────────────

  final ValueNotifier<String> _liveDayNotifier = ValueNotifier('THU');
  final ValueNotifier<String> _liveDateNotifier = ValueNotifier('FEB 19');
  final ValueNotifier<String> _liveTimeNotifier = ValueNotifier('00:00');
  String get _liveDay => _liveDayNotifier.value;
  String get _liveDate => _liveDateNotifier.value;
  String get _liveTime => _liveTimeNotifier.value;
  Timer? _clockTimer;

  String _weatherIcon = '☀️';
  String _weatherLabel = 'Clear';
  String _weatherDetail = 'Fetching conditions';
  String _weatherTemp = '--°';
  String _weatherContext = '';
  String? _suggestionBanner;
  bool _bannerVisible = false; // kept for API compat, unused

  List<Map<String, dynamic>> _buildAllOutfits(BuildContext context) => [
    {
      'id': 'o0',
      'nameKey': 'outfit_linen_air_name',
      'descKey': 'outfit_linen_air_desc',
      'tipKey': 'outfit_linen_air_tip',
      'name': AppLocalizations.t(context, 'outfit_linen_air_name'),
      'desc': AppLocalizations.t(context, 'outfit_linen_air_desc'),
      'tip': AppLocalizations.t(context, 'outfit_linen_air_tip'),
      'range': [26, 99],
      'occ': [
        AppLocalizations.t(context, 'occ_casual'),
        AppLocalizations.t(context, 'occ_weekend'),
        AppLocalizations.t(context, 'occ_travel'),
      ],
      'colors': ['#e8e0d5', '#c8b89a', '#d4a472'],
      'arTags': [
        {
          't': AppLocalizations.t(context, 'ar_linen_overshirt'),
          'top': 0.28,
          'left': 0.18,
        },
        {
          't': AppLocalizations.t(context, 'ar_drawstring_shorts'),
          'top': 0.60,
          'left': 0.12,
        },
        {
          't': AppLocalizations.t(context, 'ar_sandals'),
          'top': 0.82,
          'left': 0.22,
        },
      ],
      'tags': [
        AppLocalizations.t(context, 'tag_breezy'),
        AppLocalizations.t(context, 'tag_linen'),
        AppLocalizations.t(context, 'tag_relaxed_fit'),
        AppLocalizations.t(context, 'tag_warm_weather'),
      ],
      'img':
      'https://i.pinimg.com/736x/dc/f4/05/dcf405a9b3fa1734bf1a68c689295012.jpg',
      'localImg': 'assets/images/outfit_linen_air.jpg',
    },
    {
      'id': 'o1',
      'nameKey': 'outfit_coffee_run_name',
      'descKey': 'outfit_coffee_run_desc',
      'tipKey': 'outfit_coffee_run_tip',
      'name': AppLocalizations.t(context, 'outfit_coffee_run_name'),
      'desc': AppLocalizations.t(context, 'outfit_coffee_run_desc'),
      'tip': AppLocalizations.t(context, 'outfit_coffee_run_tip'),
      'range': [15, 25],
      'occ': [
        AppLocalizations.t(context, 'occ_casual'),
        AppLocalizations.t(context, 'occ_weekend'),
        AppLocalizations.t(context, 'occ_errands'),
      ],
      'colors': ['#8d8d8d', '#4a6fa5', '#f5f5f5'],
      'arTags': [
        {
          't': AppLocalizations.t(context, 'ar_oversized_hoodie'),
          'top': 0.30,
          'left': 0.15,
        },
        {
          't': AppLocalizations.t(context, 'ar_straight_jeans'),
          'top': 0.62,
          'left': 0.10,
        },
        {
          't': AppLocalizations.t(context, 'ar_chunky_sneakers'),
          'top': 0.83,
          'left': 0.20,
        },
      ],
      'tags': [
        AppLocalizations.t(context, 'tag_cosy'),
        AppLocalizations.t(context, 'tag_casual'),
        AppLocalizations.t(context, 'tag_everyday'),
        AppLocalizations.t(context, 'tag_comfortable'),
      ],
      'img':
      'https://i.pinimg.com/736x/a3/f2/18/a3f218d89461024773e4b0c0a0b52de2.jpg',
      'localImg': 'assets/images/outfit_coffee_run.jpg',
    },
    {
      'id': 'o2',
      'nameKey': 'outfit_office_hours_name',
      'descKey': 'outfit_office_hours_desc',
      'tipKey': 'outfit_office_hours_tip',
      'name': AppLocalizations.t(context, 'outfit_office_hours_name'),
      'desc': AppLocalizations.t(context, 'outfit_office_hours_desc'),
      'tip': AppLocalizations.t(context, 'outfit_office_hours_tip'),
      'range': [18, 28],
      'occ': [
        AppLocalizations.t(context, 'occ_work'),
        AppLocalizations.t(context, 'occ_meetings'),
        AppLocalizations.t(context, 'tag_formal'),
      ],
      'colors': ['#2c3e50', '#a8bbd1', '#1a1a1a'],
      'arTags': [
        {
          't': AppLocalizations.t(context, 'ar_slim_blazer'),
          'top': 0.28,
          'left': 0.16,
        },
        {
          't': AppLocalizations.t(context, 'ar_tailored_trousers'),
          'top': 0.63,
          'left': 0.11,
        },
        {
          't': AppLocalizations.t(context, 'ar_chelsea_boots'),
          'top': 0.83,
          'left': 0.21,
        },
      ],
      'tags': [
        AppLocalizations.t(context, 'tag_smart'),
        AppLocalizations.t(context, 'tag_formal'),
        AppLocalizations.t(context, 'tag_polished'),
        AppLocalizations.t(context, 'tag_work_ready'),
      ],
      'img':
      'https://i.pinimg.com/736x/e0/c1/9d/e0c19d4fc4c0afe55a832318c50c5b8a.jpg',
      'localImg': 'assets/images/outfit_office_hours.jpg',
    },
    {
      'id': 'o3',
      'nameKey': 'outfit_golden_hour_name',
      'descKey': 'outfit_golden_hour_desc',
      'tipKey': 'outfit_golden_hour_tip',
      'name': AppLocalizations.t(context, 'outfit_golden_hour_name'),
      'desc': AppLocalizations.t(context, 'outfit_golden_hour_desc'),
      'tip': AppLocalizations.t(context, 'outfit_golden_hour_tip'),
      'range': [20, 30],
      'occ': [
        AppLocalizations.t(context, 'tag_date_night'),
        AppLocalizations.t(context, 'occ_casual'),
        AppLocalizations.t(context, 'occ_dinner'),
      ],
      'colors': ['#c8864a', '#8b6f5c', '#d4b483'],
      'arTags': [
        {
          't': AppLocalizations.t(context, 'ar_knit_polo'),
          'top': 0.29,
          'left': 0.16,
        },
        {
          't': AppLocalizations.t(context, 'ar_camel_trousers'),
          'top': 0.62,
          'left': 0.10,
        },
        {
          't': AppLocalizations.t(context, 'ar_suede_loafers'),
          'top': 0.83,
          'left': 0.20,
        },
      ],
      'tags': [
        AppLocalizations.t(context, 'tag_earth_tones'),
        AppLocalizations.t(context, 'tag_trendy'),
        AppLocalizations.t(context, 'tag_textured'),
        AppLocalizations.t(context, 'tag_date_night'),
      ],
      'img':
      'https://i.pinimg.com/474x/33/f8/a6/33f8a65105a50fbc1948e176221182d0.jpg',
      'localImg': 'assets/images/outfit_golden_hour.jpg',
    },
  ];
  List<Map<String, dynamic>> _displayedOutfits = [];

  _TryOnStage _tryOnStage = _TryOnStage.preview;
  String? _tryOnOutfitId;
  bool _frontCamera = true;
  int _selectedSwatchIndex = 0;
  int _visibleArTags = 0;

  Timer? _tryOnStageTimer;
  final List<Timer> _arTagTimers = [];
  late String _tryOnLoadingMessage;

  late AnimationController _scanCtrl;
  late Animation<double> _scanLineY;

  late AnimationController _screenFadeCtrl;
  late Animation<double> _screenFade;

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  final FocusNode _chatFocusNode = FocusNode();
  bool _micActive = false;
  Timer? _clockAlignTimer;

  late List<String> quickPrompts;
  bool _quickPromptsInited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tryOnLoadingMessage = AppLocalizations.t(
      context,
      'daily_wear_requesting_camera',
    );

    if (!_quickPromptsInited) {
      quickPrompts = [
        AppLocalizations.t(context, 'wear_chip_today'),
        AppLocalizations.t(context, 'wear_chip_style_tips'),
        AppLocalizations.t(context, 'wear_chip_first_date'),
        AppLocalizations.t(context, 'wear_chip_linen'),
        AppLocalizations.t(context, 'wear_chip_colours'),
        AppLocalizations.t(context, 'wear_chip_office'),
      ];
      _quickPromptsInited = true;
    } else {
      // Refresh quick prompts text on language change
      quickPrompts = [
        AppLocalizations.t(context, 'wear_chip_today'),
        AppLocalizations.t(context, 'wear_chip_style_tips'),
        AppLocalizations.t(context, 'wear_chip_first_date'),
        AppLocalizations.t(context, 'wear_chip_linen'),
        AppLocalizations.t(context, 'wear_chip_colours'),
        AppLocalizations.t(context, 'wear_chip_office'),
      ];
    }
  }

  List<Map<String, dynamic>> get optionCards {
    if (_displayedOutfits.length < 2) return const [];
    final options = _displayedOutfits.skip(1).take(3).toList();
    final borders = [accentColor, accent3Color, accent2Color];
    final gradients = [
      [
        accentColor.withValues(alpha: 0.24),
        accentColor.withValues(alpha: 0.11),
      ],
      [
        accent3Color.withValues(alpha: 0.22),
        accent3Color.withValues(alpha: 0.10),
      ],
      [
        accent2Color.withValues(alpha: 0.23),
        accent2Color.withValues(alpha: 0.11),
      ],
    ];
    return List.generate(options.length, (index) {
      final outfit = options[index];
      return {
        'outfitId': outfit['id'],
        'nameKey': outfit['nameKey'],
        'name': outfit['nameKey'],
        'sub': outfit['descKey'],
        'img': outfit['img'],
        'borderColor': borders[index],
        'gradient': gradients[index],
      };
    });
  }

  Map<String, dynamic> get _currentOutfit {
    if (_displayedOutfits.isEmpty) return <String, dynamic>{};
    final idx = _carouselIndex.clamp(0, _displayedOutfits.length - 1).toInt();
    return _displayedOutfits[idx];
  }

  List<Map<String, dynamic>> _fallbackOutfits() =>
      List<Map<String, dynamic>>.from(_buildAllOutfits(context));

  void _applyOutfits(List<Map<String, dynamic>> outfits) {
    final currentId = _displayedOutfits.isNotEmpty
        ? _displayedOutfits[_carouselIndex.clamp(
      0,
      _displayedOutfits.length - 1,
    ).toInt()]['id']?.toString()
        : null;

    _displayedOutfits = outfits;
    _savedCarouselById = {
      for (final outfit in outfits) outfit['id'] as String: false,
    };
    _savedOptionById = {
      for (final outfit in outfits) outfit['id'] as String: false,
    };
    if (_displayedOutfits.isNotEmpty) {
      final nextIndex = currentId == null
          ? 0
          : _displayedOutfits.indexWhere((o) => o['id'] == currentId);
      _carouselIndexNotifier.value = nextIndex >= 0 ? nextIndex : 0;
      _tryOnOutfitId = _displayedOutfits[_carouselIndexNotifier.value]['id']
      as String;
    } else {
      _carouselIndexNotifier.value = 0;
      _tryOnOutfitId = null;
    }
  }

  Map<String, dynamic> _outfitById(String id) {
    final found = _displayedOutfits.where((o) => o['id'] == id);
    if (found.isNotEmpty) return found.first;
    final fallback = _fallbackOutfits();
    final fallbackFound = fallback.where((o) => o['id'] == id);
    return fallbackFound.isNotEmpty ? fallbackFound.first : <String, dynamic>{};
  }

  Map<String, dynamic> _normalizeDailyBoardCard(
      Map<String, dynamic> card,
      int index,
      ) {
    // The backend's board contract carries garments under `board_items`
    // (sometimes `composition_items`) — the same field the canonical chat
    // board renderer (ahvi_outfit_board_card.dart) prefers first. Raw
    // `items` is the pre-enrichment list (name/category/raw photo only,
    // no masked/normalized cutout) and resolves to an empty imageUrl for
    // every entry, leaving _styleBoardFromOutfit permanently null even
    // though the card itself is non-empty. `items` stays as the last
    // resort for cards that never got an adapted board_items at all.
    // `used_wardrobe_items` sits between composition_items and items in
    // precedence (see DailyWearScreen.firstNonEmptyBoardItems) for cards
    // shaped by the wardrobe-recommendation response path.
    final rawItems = DailyWearScreen.firstNonEmptyBoardItems(card);
    final items = List<Map<String, dynamic>>.from(
      rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
    final cover = (card['image_url'] ??
        card['imageUrl'] ??
        card['thumbnailUrl'] ??
        card['cover_url'] ??
        card['coverUrl'] ??
        (items.isNotEmpty ? items.first['image_url'] : null) ??
        (items.isNotEmpty ? items.first['imageUrl'] : null) ??
        '')
        .toString()
        .trim();
    final title = (card['title'] ??
        card['name'] ??
        card['direction_name'] ??
        card['occasion'] ??
        'Daily Look ${index + 1}')
        .toString()
        .trim();
    final desc = (card['description'] ??
        card['desc'] ??
        card['reason'] ??
        card['context'] ??
        card['outfitDescription'] ??
        '')
        .toString()
        .trim();
    final rawId = (card['id'] ?? card['board_id'] ?? card['boardId'] ?? title)
        .toString()
        .trim();
    return {
      'id': rawId.isEmpty ? 'daily-board-$index' : rawId,
      'nameKey': title,
      'name': title,
      'descKey': desc,
      'desc': desc,
      'tip': desc,
      'img': cover.isNotEmpty ? cover : _localOutfitImage(index),
      'localImg': _localOutfitImage(index),
      'items': items,
      'used_wardrobe_items': items,
      'occ': const <String>[],
      'tags': const <String>[],
      'arTags': const <Map<String, dynamic>>[],
    };
  }

  String _localOutfitImage(int index) {
    final fallback = _fallbackOutfits();
    if (fallback.isEmpty) return '';
    return (fallback[index % fallback.length]['localImg'] ?? '').toString();
  }

  StyleBoardItem _styleBoardItemFromMap(Map<String, dynamic> item) {
    return StyleBoardItem.fromJson(item);
  }

  /// Builds the Style Board for [outfit] from the wardrobe items the
  /// backend attached to its daily-board card (see `_normalizeDailyBoardCard`).
  /// Returns null when the backend hasn't supplied item-level data for this
  /// outfit yet — the UI treats that as "still loading" and shows the bare
  /// layout shell instead.
  StyleBoardData? _styleBoardFromOutfit(Map<String, dynamic> outfit) {
    final rawItems = outfit['items'];
    if (rawItems is! List || rawItems.isEmpty) return null;
    final items = rawItems
        .whereType<Map>()
        .map((e) => _styleBoardItemFromMap(Map<String, dynamic>.from(e)))
        .where((i) => i.imageUrl.isNotEmpty)
        .toList();
    if (items.isEmpty) return null;

    final storyRaw = outfit['story'];
    final story = storyRaw is Map
        ? BoardStory.fromJson(Map<String, dynamic>.from(storyRaw))
        : null;

    return StyleBoardData(
      title: (outfit['name'] ?? '').toString(),
      occasion: (outfit['desc'] ?? '').toString(),
      whyItWorks: (outfit['tip'] ?? '').toString(),
      items: items,
      story: story,
      stylingTip: (outfit['tip'] ?? '').toString(),
    );
  }

  /// Bare Style Board canvas shown while item-level data for this outfit
  /// hasn't arrived from the backend yet. Intentionally carries no text,
  /// titles, chips, or buttons — just the outfit layout surface.
  Widget _buildStyleBoardLoadingShell() => Container(
    width: double.infinity,
    height: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
  );

  /// The real Style Board once the backend has supplied item-level data for
  /// [outfit], otherwise the bare loading shell placeholder.
  Widget _buildOutfitVisual(Map<String, dynamic> outfit) {
    final styleBoard = _styleBoardFromOutfit(outfit);
    if (styleBoard == null) return _buildStyleBoardLoadingShell();
    return _buildUnifiedOutfitGrid(styleBoard);
  }

  Widget _buildUnifiedOutfitGrid(StyleBoardData board) =>
      AhviUnifiedOutfitGrid(
        items: board.items
            .map(
              (item) => AhviUnifiedOutfitGridItem.fromStyleBoardItem(
                item,
                // 'style_board' prefix is required for
                // wardrobe_image_resolver's board-safe, cutout-first
                // candidate ordering to apply to the canonical Daily Wear
                // board.
                surface: 'style_board_daily_wear_unified_grid',
              ),
            )
            .toList(growable: false),
      );

  List<Map<String, dynamic>> _normalizeDailyBoardCards(List<dynamic> cards) {
    return cards
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false)
        .asMap()
        .entries
        .map((entry) => _normalizeDailyBoardCard(entry.value, entry.key))
        .toList(growable: false);
  }

  bool _isInsufficientWardrobeResponse(Map<String, dynamic>? response) {
    final data = response?['data'];
    final meta = response?['meta'];
    // Explicit machine-readable signal only (routers.chat._demo_style_board_
    // payload's no-cards branch: type/reason/status/meta.reason all set to
    // "insufficient_wardrobe" only when the wardrobe genuinely lacks
    // required role coverage). Do NOT infer this from cards.isEmpty alone --
    // any other board-generation hiccup must fall through to a neutral
    // retry state instead of falsely claiming the wardrobe is too small.
    bool isFlag(dynamic v) => v?.toString().toLowerCase().trim() == 'insufficient_wardrobe';
    return isFlag(response?['type']) ||
        isFlag(response?['reason']) ||
        isFlag(response?['status']) ||
        (data is Map && isFlag(data['type'])) ||
        (data is Map && isFlag(data['reason'])) ||
        (meta is Map && isFlag(meta['reason']));
  }

  Future<void> _fetchDailyBoard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _needsMoreClothes = false;
      _loadUnavailable = false;
      _emptyStateMessage = '';
    });

    final response = await BackendService().getDailyBoard();
    if (!mounted) return;

    final data = response?['data'];
    final Map<String, dynamic> dataMap = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    if (_isInsufficientWardrobeResponse(response)) {
      final contextMessage =
          (dataMap['context'] ?? response?['message'])?.toString().trim() ?? '';
      setState(() {
        _isLoading = false;
        _needsMoreClothes = true;
        _emptyStateMessage = contextMessage.isNotEmpty
            ? contextMessage
            : AppLocalizations.t(context, 'daily_wear_add_clothes_unlock');
      });
      return;
    }

    final cards = dataMap['cards'] ??
        (response is Map<String, dynamic> ? response['cards'] as List? : null);
    final outfits = cards is List && cards.isNotEmpty
        ? _normalizeDailyBoardCards(cards)
        : const <Map<String, dynamic>>[];

    // No usable Daily Board came back and the backend didn't explicitly flag
    // insufficient_wardrobe. The local demo-outfits helper used to fill this
    // gap with garments shaped for the old renderer (no `items`), which
    // _styleBoardFromOutfit always rejects — a permanent blank white board
    // that also misrepresented demo pieces as the user's own wardrobe.
    // Never claim "add more clothes" without the backend's explicit signal
    // (already checked and returned above) -- an unexplained empty result
    // is a generic unavailable/retry state instead.
    if (outfits.isEmpty) {
      setState(() {
        _isLoading = false;
        _loadUnavailable = true;
        _emptyStateMessage = AppLocalizations.t(context, 'daily_wear_unavailable_retry');
      });
      return;
    }

    setState(() {
      _applyOutfits(outfits);
      _isLoading = false;
      _needsMoreClothes = false;
      _loadUnavailable = false;
      _emptyStateMessage = '';
    });
  }

  @override
  void initState() {
    super.initState();

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _scanLineY = Tween<double>(
      begin: 0.10,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));

    // Screen fade-in removed — instant display
    _screenFadeCtrl = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: 1.0,
    );
    _screenFade = CurvedAnimation(
      parent: _screenFadeCtrl,
      curve: Curves.linear,
    );

    _pageController.addListener(_onPageScroll);

    // ── Deferred startup ──────────────────────────────────────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Defensive reset: guarantees the chat / try-on overlay flags are
      // false on every fresh entry into Daily Wear.
      if (_chatOpen || _tryOnOpen) {
        setState(() {
          _chatOpen = false;
          _tryOnOpen = false;
        });
      }
      // Pop any stuck root-level modal (e.g. a loading dialog from the
      // AHVI Lens sheet that failed to dismiss because its backend call
      // threw before Navigator.pop fired). Without this a stale modal
      // scrim sits on top of Daily Wear and blocks every tap — the
      // reported "whole screen greyed out, nothing responds" symptom.
      try {
        final rootNav = Navigator.of(context, rootNavigator: true);
        while (rootNav.canPop()) {
          final route = ModalRoute.of(rootNav.context);
          // Only pop transient overlay routes; keep the page route.
          if (route is PopupRoute || route is RawDialogRoute) {
            rootNav.pop();
          } else {
            break;
          }
        }
      } catch (_) {
        // Best-effort cleanup; never crash Daily Wear because of it.
      }
      _clearTransientInputOverlay();
      _startAutoPlay();
      _fetchDailyBoard();

      _updateClock();
      _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) _updateClock();
      });
      final now = DateTime.now();
      final nextMinute = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + 1,
      );
      _clockAlignTimer = Timer(nextMinute.difference(now), () {
        if (!mounted) return;
        _updateClock();
        _clockTimer?.cancel();
        _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) _updateClock();
        });
      });

      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _fetchWeather();
      });
    });
  }

  void _clearTransientInputOverlay() {
    FocusManager.instance.primaryFocus?.unfocus();
    _chatFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _updateClock() {
    final now = DateTime.now();
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    // Update without setState — no Scaffold rebuild
    _liveDayNotifier.value = days[now.weekday % 7];
    _liveDateNotifier.value = '${months[now.month - 1]} ${now.day}';
    _liveTimeNotifier.value =
    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _onPageScroll() {
    final pos = _pageController.page ?? 0;
    if ((pos - pos.round()).abs() > 0.01) {
      if (!_userScrolling) {
        _userScrolling = true;
        _autoPlayTimer?.cancel();
      }
    } else if (_userScrolling) {
      _userScrolling = false;
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // `_displayedOutfits` can go non-empty (weather-driven fallback sort)
      // before the PageView carrying `_pageController` has actually mounted
      // (still behind `_isLoading`) — animateToPage on an unattached
      // controller throws "Bad state: No element". hasClients is the direct
      // signal that a Scrollable is actually attached.
      if (!mounted ||
          _userScrolling ||
          _displayedOutfits.isEmpty ||
          !_pageController.hasClients) {
        return;
      }
      final next = (_carouselIndex + 1) % _displayedOutfits.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _fetchWeather() async {
    debugPrint('AHVI_HEAVY_SCREEN_LOAD start screen=DailyWear');
    try {
      // Canonical weather source -- same BackendService().getCurrentWeather()
      // contract Home uses, which resolves device location internally via
      // LocationContextService. No direct Open-Meteo call and no hardcoded
      // coordinates here: DailyWearScreen.resolveWeatherCoordinates() remains
      // available for callers that need raw coordinates, but weather itself
      // must come from the shared backend path, not a duplicate provider.
      final weather = await BackendService().getCurrentWeather();
      final mapped = mapDailyWearWeather(weather);
      _applyWeather(mapped.temp, mapped.feel, mapped.code, context);
    } catch (_) {
      debugPrint('AHVI_HEAVY_SCREEN_LOAD weather_unavailable screen=DailyWear');
      _applyWeatherUnavailable();
    }
  }

  /// Honest unavailable state: no fabricated temperature/condition. Only the
  /// weather chrome updates -- outfit order/banner are left as-is rather than
  /// sorted against a made-up temperature.
  void _applyWeatherUnavailable() {
    if (!mounted) return;
    setState(() {
      _weatherIcon = '—';
      _weatherLabel = 'Weather unavailable';
      _weatherDetail = '';
      _weatherTemp = '--°';
      _weatherContext = '';
    });
  }

  void _applyWeather(int temp, int feel, int code, [BuildContext? ctx]) {
    final context = ctx ?? this.context;
    final wm = <int, List<String>>{
      0: [
        '☀️',
        AppLocalizations.t(context, 'weather_clear_sky'),
        AppLocalizations.t(context, 'weather_clear_sky_tip'),
      ],
      1: [
        '🌤️',
        AppLocalizations.t(context, 'weather_mostly_clear'),
        AppLocalizations.t(context, 'weather_mostly_clear_tip'),
      ],
      2: [
        '⛅',
        AppLocalizations.t(context, 'weather_partly_cloudy'),
        AppLocalizations.t(context, 'weather_partly_cloudy_tip'),
      ],
      3: [
        '☁️',
        AppLocalizations.t(context, 'weather_overcast'),
        AppLocalizations.t(context, 'weather_overcast_tip'),
      ],
      45: [
        '🌫️',
        AppLocalizations.t(context, 'weather_foggy'),
        AppLocalizations.t(context, 'weather_foggy_tip'),
      ],
      51: [
        '🌦️',
        AppLocalizations.t(context, 'weather_light_drizzle'),
        AppLocalizations.t(context, 'weather_light_drizzle_tip'),
      ],
      61: [
        '🌧️',
        AppLocalizations.t(context, 'weather_light_rain'),
        AppLocalizations.t(context, 'weather_light_rain_tip'),
      ],
      63: [
        '🌧️',
        AppLocalizations.t(context, 'weather_rain'),
        AppLocalizations.t(context, 'weather_rain_tip'),
      ],
      65: [
        '⛈️',
        AppLocalizations.t(context, 'weather_heavy_rain'),
        AppLocalizations.t(context, 'weather_heavy_rain_tip'),
      ],
      80: [
        '🌦️',
        AppLocalizations.t(context, 'weather_showers'),
        AppLocalizations.t(context, 'weather_showers_tip'),
      ],
      95: [
        '⛈️',
        AppLocalizations.t(context, 'weather_thunderstorm'),
        AppLocalizations.t(context, 'weather_thunderstorm_tip'),
      ],
    };
    final feelsLike = feel >= 36
        ? AppLocalizations.t(context, 'feels_very_hot')
        : feel >= 30
        ? AppLocalizations.t(context, 'feels_hot')
        : feel >= 24
        ? AppLocalizations.t(context, 'feels_warm')
        : feel >= 18
        ? AppLocalizations.t(context, 'feels_mild')
        : feel >= 10
        ? AppLocalizations.t(context, 'feels_cool')
        : AppLocalizations.t(context, 'feels_cold');

    final w = wm[code] ?? wm[2]!;
    final weatherDetail = temp >= 30
        ? 'Keep it breathable - light fabrics and relaxed fits are best today.'
        : w[2];
    if (!mounted) return;

    // Merge weather data + outfit reorder into ONE deferred setState
    // to prevent the double-rebuild flash/fade.
    _applyWeatherAndSort(
      temp: temp,
      icon: w[0],
      label: '${w[1]} · $feelsLike',
      detail: weatherDetail,
      weatherCtx: '${w[1]}, $feelsLike, $temp°C',
    );
  }

  void _applyWeatherAndSort({
    required int temp,
    required String icon,
    required String label,
    required String detail,
    required String weatherCtx,
  }) {
    // A genuinely empty _displayedOutfits (still loading, or the real fetch
    // legitimately came back with nothing) must never be backfilled with
    // the demo catalog here -- that would silently make _currentOutfit
    // (used for wear/save/share and the current_outfit chat payload) a
    // fake outfit even while the empty-state UI is correctly shown.
    // Weather chrome still updates; outfit sort/banner waits for real data.
    if (_displayedOutfits.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_weatherTemp != '$temp°') {
          setState(() {
            _weatherIcon = icon;
            _weatherLabel = label;
            _weatherDetail = detail;
            _weatherTemp = '$temp°';
            _weatherContext = weatherCtx;
          });
        }
      });
      return;
    }

    int score(Map<String, dynamic> outfit) {
      final range = ((outfit['range'] as List?)?.cast<int>() ?? [0, 99]);
      final low = range[0];
      final high = range[1];
      if (temp >= low && temp <= high) return 2;
      final delta = temp < low ? low - temp : temp - high;
      return delta <= 5 ? 1 : 0;
    }

    final baseOutfits = List<Map<String, dynamic>>.from(_displayedOutfits);
    final sorted = baseOutfits..sort((a, b) => score(b).compareTo(score(a)));
    final hero = sorted.first;
    final tempIcon = temp >= 30
        ? '🌡️'
        : temp >= 22
        ? '🌤️'
        : temp >= 15
        ? '🍃'
        : '🧣';
    final banner = score(hero) == 2
        ? AppLocalizations.t(context, 'banner_perfect_fit')
        .replaceAll('{icon}', tempIcon)
        .replaceAll(
      '{name}',
      AppLocalizations.t(context, hero['nameKey'] as String),
    )
        .replaceAll('{temp}', '$temp')
        : AppLocalizations.t(
      context,
      'banner_sorted_for',
    ).replaceAll('{icon}', tempIcon).replaceAll('{temp}', '$temp');

    // Single postFrameCallback — ONE setState for both weather + outfit data.
    // Previously: setState (weather) → _sortOutfitsForWeather → setState (outfits)
    // = 2 rebuilds = flash. Now: 1 rebuild = no flash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_weatherTemp != '$temp°') {
        setState(() {
          _weatherIcon = icon;
          _weatherLabel = label;
          _weatherDetail = detail;
          _weatherTemp = '$temp°';
          _weatherContext = weatherCtx;
          _displayedOutfits = sorted;
          _carouselIndexNotifier.value = 0;
          _suggestionBanner = banner;
          _bannerVisible = true;
          _tryOnOutfitId ??= nullableText(sorted.first['id']);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
    });
  }

  void _sortOutfitsForWeather(int temp) {
    // Delegate to merged method — preserves existing weather display values
    _applyWeatherAndSort(
      temp: temp,
      icon: _weatherIcon,
      label: _weatherLabel,
      detail: _weatherDetail,
      weatherCtx: _weatherContext,
    );
  }

  void _removeOverlay() {
    try {
      _toastEntry?.remove();
    } catch (_) {}
    _toastEntry = null;
  }

  // ──────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _chatController.dispose();
    _removeOverlay();
    _chatScrollController.dispose();
    _scanCtrl.dispose();
    _screenFadeCtrl.dispose();
    _autoPlayTimer?.cancel();
    _toastTimer?.cancel();
    _liveDayNotifier.dispose();
    _liveDateNotifier.dispose();
    _liveTimeNotifier.dispose();
    _carouselIndexNotifier.dispose();

    try {
      _toastEntry?.remove();
    } catch (_) {}
    _chatFocusNode.dispose();
    _clockAlignTimer?.cancel();
    _clockTimer?.cancel();
    _chatGreetingTimer?.cancel();
    _tryOnStageTimer?.cancel();
    for (final timer in _arTagTimers) {
      timer.cancel();
    }
    super.dispose(); // ✅ ADD THIS
  }

  void _showToast(String message, {bool green = false}) {
    _toastEntry?.remove();
    _toastEntry = null;
    _toastTimer?.cancel();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [_ToastWidget(message: message, green: green)],
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    _toastTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted)
        return; // guard: widget may have been disposed before timer fires
      try {
        entry.remove();
      } catch (_) {}
      if (_toastEntry == entry) _toastEntry = null;
    });
  }

  void _wearOutfit(String outfitId, {bool closeModal = false}) {
    final outfit = _outfitById(outfitId);
    HapticFeedback.lightImpact();
    setState(() => _wornOutfitId = outfitId);
    if (closeModal) {
      setState(() => _tryOnOpen = false);
    }
    _showToast(
      AppLocalizations.t(context, 'daily_wear_toast_wearing').replaceAll(
        '{name}',
        AppLocalizations.t(context, outfit['nameKey'] as String),
      ),
      green: true,
    );
    // Record the wear so AHVI learns. Best-effort: only fires when the outfit
    // carries real wardrobe item ids; demo outfits without ids are skipped.
    _recordWear(outfit);
    // 🆕 Push to Home: marks the "Wear" routine bubble/card as done today,
    // with this outfit's name as the subtitle. Home's routine cards section
    // already watches HomeCardSummaryProvider, so this updates it live —
    // no navigation-return refresh needed.
    _pushWearToHome(outfit);
  }

  /// Notify HomeCardSummaryProvider that today's outfit has been picked.
  void _pushWearToHome(Map<String, dynamic> outfit) {
    try {
      final outfitName = AppLocalizations.t(context, outfit['nameKey'] as String);
      context.read<HomeCardSummaryProvider>().markWearDone(
        done: true,
        outfitName: outfitName,
      );
    } catch (_) {
      // HomeCardSummaryProvider not found above this screen in the tree —
      // fail silently so wearing an outfit never breaks on this alone.
    }
  }

  final Set<String> _wearInFlight = {};
  final Map<String, GlobalKey> _boardCanvasKeys = {};

  GlobalKey _boardCanvasKeyFor(String outfitId) =>
      _boardCanvasKeys.putIfAbsent(outfitId, () => GlobalKey());

  /// Captures the on-screen Daily Wear board (via RepaintBoundary) and
  /// shares it as an image with descriptive text. Never changes the board
  /// renderer or item parser -- purely captures whatever is already
  /// rendered. Falls back to a text-only share if image capture fails for
  /// any reason (missing boundary, network image not yet painted, etc.), and
  /// never throws back into the caller.
  Future<void> _shareOutfit(Map<String, dynamic> outfit) async {
    final outfitId = (outfit['id'] ?? '').toString();
    final title = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look')
        .toString()
        .trim();
    final shareText = title.isEmpty
        ? 'My AHVI daily look'
        : '$title — styled by AHVI';
    final key = _boardCanvasKeys[outfitId];
    try {
      final bytes = key == null ? null : await BoardExporter.capturePng(key);
      if (bytes != null && bytes.isNotEmpty) {
        final file = await BoardExporter.writeToTempFile(
          bytes,
          filename: 'ahvi_daily_board_${outfitId.isEmpty ? DateTime.now().millisecondsSinceEpoch : outfitId}.png',
        );
        if (file != null) {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: 'image/png')],
              subject: title.isEmpty ? 'AHVI Look' : title,
              text: shareText,
            ),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('AHVI_DAILY_WEAR_SHARE_IMAGE_FAILED: $e');
    }
    // Text fallback -- image capture unavailable/failed, but sharing must
    // still work and must never crash the screen.
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: title.isEmpty ? 'AHVI Look' : title,
        ),
      );
    } catch (e) {
      debugPrint('AHVI_DAILY_WEAR_SHARE_TEXT_FAILED: $e');
    }
  }

  void _recordWear(Map<String, dynamic> outfit) {
    final outfitId = (outfit['id'] ?? '').toString();
    if (outfitId.isNotEmpty && _wearInFlight.contains(outfitId)) {
      return; // duplicate fast tap on the same outfit -- already recording.
    }

    final ids = <String>[];
    void addFrom(dynamic v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) {
            final id = (e['id'] ?? e['\$id'] ?? e['item_id'] ?? '')
                .toString()
                .trim();
            if (id.isNotEmpty) ids.add(id);
          } else if (e is String && e.trim().isNotEmpty) {
            ids.add(e.trim());
          }
        }
      }
    }

    // Canonical precedence (board_items > composition_items >
    // used_wardrobe_items > items), same helper Daily Board card
    // normalization uses -- never falls back to demo/fallback ids.
    addFrom(DailyWearScreen.firstNonEmptyBoardItems(outfit));
    addFrom(outfit['item_ids']);
    if (ids.isEmpty) return; // demo outfit — nothing real to record.

    if (outfitId.isNotEmpty) _wearInFlight.add(outfitId);
    BackendService()
        .wearToday(
      itemIds: ids,
      boardId: outfitId,
      occasion: (outfit['occasion'] ?? '').toString(),
    )
        .then((ok) {
      if (outfitId.isNotEmpty) _wearInFlight.remove(outfitId);
      if (!mounted) return;
      _showToast(
        ok
            ? AppLocalizations.t(context, 'daily_wear_toast_style_history_added')
            : AppLocalizations.t(context, 'daily_wear_toast_update_failed'),
        green: ok,
      );
    }).catchError((_) {
      if (outfitId.isNotEmpty) _wearInFlight.remove(outfitId);
      if (!mounted) return;
      _showToast(
        AppLocalizations.t(context, 'daily_wear_toast_update_failed'),
        green: false,
      );
    });
  }

  void _openChat() {
    HapticFeedback.lightImpact();
    setState(() => _chatOpen = true);
    _chatGreetingTimer?.cancel();
    if (_messages.isEmpty) {
      _chatGreetingTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted || _messages.isNotEmpty) return;
        setState(() {
          _messages.add(
            _ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch,
              text: AppLocalizations.t(context, 'daily_wear_ahvi_greeting'),
              isUser: false,
              createdAt: DateTime.now(),
            ),
          );
        });
        _scrollChatToBottom();
      });
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Scaffold(
          key: _chatScaffoldKey,
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          drawer: _historyDrawer(),
          body: Container(
            decoration: BoxDecoration(
              color: bg2Color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: cardBorderColor),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: panel2Color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _chatHeader(),
                Expanded(child: _chatMessages()),
                if (_quickPromptsVisible) _chatQuickPrompts(),
                _chatBar(),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      _clearTransientInputOverlay();
      if (mounted) {
        setState(() {
          _chatOpen = false;
          // Defensive: ensure the try-on flag is also low after any
          // bottom-sheet closure so no stale overlay state survives.
          _tryOnOpen = false;
        });
      }
    });
  }

  void _closeChat() {
    _chatGreetingTimer?.cancel();
    _clearTransientInputOverlay();
    Navigator.of(context).pop();
  }

  void _showTryOnError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Try On could not be completed. Please try again.'),
      ),
    );
  }

  void _openTryOn([String? outfitId]) {
    unawaited(showTryOnComingSoon(context));
  }

  void _closeTryOn() {
    _clearTransientInputOverlay();
    _resetTryOnSimulation();
    setState(() => _tryOnOpen = false);
  }

  void _resetTryOnSimulation() {
    _tryOnStageTimer?.cancel();
    for (final timer in _arTagTimers) {
      timer.cancel();
    }
    _arTagTimers.clear();
    if (mounted) {
      setState(() {
        _visibleArTags = 0;
        _selectedSwatchIndex = 0;
        _frontCamera = true;
        _tryOnLoadingMessage = AppLocalizations.t(
          context,
          'daily_wear_requesting_camera',
        );
        _tryOnStage = _TryOnStage.preview;
      });
    } else {
      _visibleArTags = 0;
      _selectedSwatchIndex = 0;
      _frontCamera = true;
      _tryOnLoadingMessage = AppLocalizations.t(
        context,
        'daily_wear_requesting_camera',
      );
      _tryOnStage = _TryOnStage.preview;
    }
  }

  void _startTryOnCamera() {
    setState(() {
      _tryOnStage = _TryOnStage.loading;
      _tryOnLoadingMessage = AppLocalizations.t(
        context,
        'daily_wear_requesting_camera',
      );
    });
    _tryOnStageTimer?.cancel();
    _tryOnStageTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(
            () => _tryOnLoadingMessage = AppLocalizations.t(
          context,
          'daily_wear_initialising_ar',
        ),
      );
      _tryOnStageTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _tryOnStage = _TryOnStage.camera;
          _visibleArTags = 0;
        });
        _scheduleArTags();
      });
    });
  }

  void _scheduleArTags() {
    final tags = (_selectedTryOnOutfit['arTags'] as List)
        .cast<Map<String, dynamic>>();
    for (var i = 0; i < tags.length; i++) {
      final timer = Timer(Duration(milliseconds: i * 300), () {
        if (mounted && _tryOnStage == _TryOnStage.camera) {
          setState(() => _visibleArTags = i + 1);
        }
      });
      _arTagTimers.add(timer);
    }
  }

  void _flipCamera() {
    HapticFeedback.selectionClick();
    setState(() => _frontCamera = !_frontCamera);
  }

  void _captureTryOn() {
    HapticFeedback.lightImpact();
    setState(() => _tryOnStage = _TryOnStage.captured);
    _showToast(AppLocalizations.t(context, 'daily_wear_toast_captured'));
  }

  void _saveCapturedLook() {
    HapticFeedback.selectionClick();
    _persistCurrentLook();
  }

  List<Map<String, dynamic>> _currentOutfitItems() {
    final items = <Map<String, dynamic>>[];
    final outfit = _currentOutfit;

    void addAllFrom(dynamic raw) {
      if (raw is! Iterable) return;
      for (final entry in raw) {
        if (entry is Map) {
          items.add(Map<String, dynamic>.from(entry));
        }
      }
    }

    addAllFrom(outfit['items']);
    addAllFrom(outfit['used_wardrobe_items']);
    return items;
  }

  List<Map<String, dynamic>> _savedDailyWearItems(StyleBoardData board) {
    return buildDailyWearSaveItems(board);
  }

  Future<void> _persistCurrentLook() async {
    final outfit = _currentOutfit;
    final board = _styleBoardFromOutfit(outfit);
    final title = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look')
        .toString()
        .trim();
    if (board == null) {
      _showToast(AppLocalizations.t(context, 'daily_wear_save_failed'));
      return;
    }
    final outfitItems = _savedDailyWearItems(board);
    final imageUrl = board.items
        .map((item) => item.displayImageUrl.trim())
        .firstWhere(
          (url) => url.isNotEmpty,
          orElse: () => '',
        );
    if (imageUrl.isEmpty) {
      _showToast(AppLocalizations.t(context, 'daily_wear_save_failed'));
      return;
    }

    try {
      final content = buildSavedBoardContent(
        board: {
          'board_id': outfit['id'],
          'revision': 1,
          'source_policy': 'wardrobe',
        },
        items: outfitItems,
        selection: const SavedBoardSelection(bucket: 'everything_else'),
        title: title.isEmpty ? 'Saved Look' : title,
        originalOccasion: 'daily',
      );
      final saved = await AppwriteService().saveBoardToCollection(
        imageUrl: imageUrl,
        content: content,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                ? AppLocalizations.t(context, 'daily_wear_save_failed')
                : AppLocalizations.t(context, 'daily_wear_saved_boards'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${AppLocalizations.t(context, 'daily_wear_save_error')}: $e'
          ),
        ),
      );
    }
  }

  /// Same categories/canonical buckets as the chat style-board save sheet
  /// (ahvi_outfit_board_card.dart) -- Daily Wear has no bucket of its own,
  /// so "Daily Wear" maps to everything_else like any other unmatched look.
  Future<String?> _showSaveOccasionSheet(Map<String, dynamic> outfit) {
    const categories = dailyWearSaveOccasionOptions;
    var selectedLabel = categories.first.$2;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Save this look to',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final category in categories)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(category.$3),
                    title: Text(category.$2),
                    trailing: Icon(
                      selectedLabel == category.$2
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                    ),
                    onTap: () =>
                        setSheetState(() => selectedLabel = category.$2),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(
                      categories
                          .firstWhere((c) => c.$2 == selectedLabel)
                          .$1,
                    ),
                    child: const Text('Save look'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns true only after authoritative persistence succeeds -- callers
  /// must gate any "saved" UI state on this return value, never flip it
  /// optimistically before the Appwrite write is confirmed.
  Future<bool> _saveOutfitToBoards(
    Map<String, dynamic> outfit, {
    String occasionBucket = 'everything_else',
  }) async {
    final board = _styleBoardFromOutfit(outfit);
    final title = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look')
        .toString()
        .trim();
    if (board == null) return false;
    final outfitItems = _savedDailyWearItems(board);
    final imageUrl = board.items
        .map((item) => item.displayImageUrl.trim())
        .firstWhere(
          (url) => url.isNotEmpty,
          orElse: () => '',
        );
    if (imageUrl.isEmpty) return false;

    try {
      final content = buildSavedBoardContent(
        board: {
          'board_id': outfit['id'],
          'revision': 1,
          'source_policy': 'wardrobe',
        },
        items: outfitItems,
        selection: SavedBoardSelection(bucket: occasionBucket),
        title: title.isEmpty ? 'Saved Look' : title,
        originalOccasion: 'daily',
      );
      final saved = await AppwriteService().saveBoardToCollection(
        imageUrl: imageUrl,
        content: content,
      );
      return saved != null;
    } catch (e) {
      debugPrint('Failed to save daily look to boards: $e');
      return false;
    }
  }

  void _toggleMic() {
    setState(() => _micActive = !_micActive);
    if (_micActive) {
      _showToast(AppLocalizations.t(context, 'daily_wear_toast_voice_on'));
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isTyping) return;
    final displayText = trimmed;
    _chatController.clear();
    setState(() {
      _messages.add(
        _ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch,
          text: displayText,
          isUser: true,
          createdAt: DateTime.now(),
        ),
      );
      _isTyping = true;
      _quickPromptsVisible = false;
    });
    _scrollChatToBottom();
    _callBackendStylist(displayText);
  }

  Future<void> _callBackendStylist(String userText) async {
    final currentOutfit = _currentOutfit;

    final history = _messages
        .take(_messages.length - 1)
        .where((m) => !m.excludeFromSemanticHistory)
        .map(
          (m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    )
        .toList();

    try {
      final response = await BackendService().sendModuleChat(
        domain: 'daily_wear',
        message: userText,
        chatHistory: List<Map<String, String>>.from(history),
        context: {
          'surface': 'daily_wear',
          // Keep the local session identity with the canonical request while
          // the backend continues to use bounded history for continuity.
          'conversation_id': _currentSessionId,
          'session_id': _currentSessionId,
          'current_outfit': Map<String, dynamic>.from(currentOutfit),
          'weather_context': _weatherContext,
          'worn_outfit_id': _wornOutfitId,
        },
      );
      if (!mounted) return;
      final rawMessage = response?['message'];
      final replyText =
      (response?['message_text'] ??
          (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
          '')
          .toString()
          .trim();
      final message = _ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch,
        text: replyText.isNotEmpty
            ? replyText
            : "I'm having a moment - try again.",
        isUser: false,
        createdAt: DateTime.now(),
        excludeFromSemanticHistory:
            !shouldAppendModuleChatResponseToSemanticHistory(response),
      );
      setState(() {
        _isTyping = false;
        _messages.add(message);
      });
      _scrollChatToBottom();
      _saveCurrentSession();
      if (_micActive) _speakMessage(message);
    } catch (err) {
      if (!mounted) return;
      final message = _ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch,
        text: "I'm having a moment - try again.",
        isUser: false,
        createdAt: DateTime.now(),
      );
      setState(() {
        _isTyping = false;
        _messages.add(message);
      });
      _scrollChatToBottom();
      _saveCurrentSession();
      if (_micActive) _speakMessage(message);
    }
  }

  void _speakMessage(_ChatMessage message) {
    setState(() => _speakingMessageId = message.id);
    // ignore: deprecated_member_use
    SemanticsService.announce(_stripMarkdown(message.text), TextDirection.ltr);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _speakingMessageId == message.id) {
        setState(() => _speakingMessageId = null);
      }
    });
  }

  void _saveCurrentSession() {
    if (_messages.isEmpty) return;
    final userMessages = _messages.where((m) => m.isUser).toList();
    if (userMessages.isEmpty) return;
    final title = userMessages.first.text.length > 40
        ? '${userMessages.first.text.substring(0, 40)}…'
        : userMessages.first.text;
    final existingIdx = _chatHistory.indexWhere(
          (s) => s.id == _currentSessionId,
    );
    final session = _ChatSession(
      id: _currentSessionId,
      title: title,
      createdAt: DateTime.now(),
      messages: List.from(_messages),
    );
    if (existingIdx != -1) {
      _chatHistory[existingIdx] = session;
    } else {
      _chatHistory.insert(0, session);
    }
  }

  void _startNewChat() {
    _saveCurrentSession();
    _chatScaffoldKey.currentState?.closeDrawer();
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages.clear();
      _quickPromptsVisible = true;
      _chatController.clear();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _messages.isNotEmpty) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch,
            text: AppLocalizations.t(context, 'daily_wear_ahvi_greeting'),
            isUser: false,
            createdAt: DateTime.now(),
          ),
        );
      });
    });
  }

  Future<void> _clearCurrentChat() async {
    if (!await confirmClearChat(context) || !mounted) return;

    setState(() {
      _chatHistory.clear();
      _currentSessionId = DateTime.now().microsecondsSinceEpoch.toString();
      _messages.clear();
      _isTyping = false;
      _quickPromptsVisible = true;
      _chatController.clear();
    });
    _chatGreetingTimer?.cancel();
    _chatGreetingTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _messages.isNotEmpty) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch,
            text: AppLocalizations.t(context, 'daily_wear_ahvi_greeting'),
            isUser: false,
            createdAt: DateTime.now(),
          ),
        );
      });
    });
  }

  void _loadSession(_ChatSession session) {
    _saveCurrentSession();
    _chatScaffoldKey.currentState?.closeDrawer();
    setState(() {
      _currentSessionId = session.id;
      _messages
        ..clear()
        ..addAll(session.messages);
      _quickPromptsVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _historyDrawer() {
    final t = context.themeTokens;
    return Drawer(
      backgroundColor: t.backgroundPrimary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.t(context, 'common_chats'),
                    style: GoogleFonts.anton(
                      fontSize: 20,
                      color: t.textPrimary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _startNewChat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [t.accent.primary, t.accent.tertiary],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.t(context, 'common_new'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: t.cardBorder, height: 1),
            Expanded(
              child: _chatHistory.isEmpty
                  ? Center(
                child: Text(
                  AppLocalizations.t(context, 'chat_no_history'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.mutedText, fontSize: 13),
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _chatHistory.length,
                separatorBuilder: (_, __) => Divider(
                  color: t.cardBorder,
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
                itemBuilder: (_, i) {
                  final session = _chatHistory[i];
                  final isActive = session.id == _currentSessionId;
                  return GestureDetector(
                    onTap: () => _loadSession(session),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: isActive
                          ? t.accent.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? t.accent.primary.withValues(
                                alpha: 0.15,
                              )
                                  : t.panel,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? t.accent.primary.withValues(
                                  alpha: 0.4,
                                )
                                    : t.cardBorder,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isActive
                                      ? t.accent.primary
                                      : t.mutedText,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive
                                        ? t.accent.primary
                                        : t.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${session.messages.length} ${AppLocalizations.t(context, 'wear_messages')}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: t.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.accent.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'$1');
  }

  Map<String, dynamic> get _selectedTryOnOutfit {
    if (_displayedOutfits.isEmpty) return <String, dynamic>{};
    final id = _tryOnOutfitId ?? _currentOutfit['id'];
    return _displayedOutfits.firstWhere(
          (outfit) => outfit['id'] == id,
      orElse: () => _currentOutfit,
    );
  }

  Color _parseHexColor(String hex) {
    final value = hex.replaceAll('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  String _formatCapturedDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildWeatherBar(),
                    _suggestionBanner != null
                        ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _buildSuggestionBanner(),
                    )
                        : const SizedBox.shrink(),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      _buildDailyBoardLoadingState()
                    else if (_needsMoreClothes || _loadUnavailable)
                      _buildDailyBoardEmptyState()
                    else ...[
                        _buildCarousel(),
                        const SizedBox(height: 24),
                        _buildSectionTitle(),
                        const SizedBox(height: 14),
                        _buildOptionCards(),
                      ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Visibility(
                visible: !_chatOpen && !_tryOnOpen,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: RepaintBoundary(child: _buildChatFab()),
              ),
            ),
            if (_tryOnOpen)
              AnimatedSlide(
                offset: _tryOnOpen ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: _buildTryOnOverlay(),
              ),
          ],
        ), // Stack
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildDailyBoardLoadingState() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      height: 260,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.t(context, 'daily_wear_loading'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildDailyBoardEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.10),
            accent3Color.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _loadUnavailable ? Icons.refresh_rounded : Icons.checkroom_rounded,
              color: accentColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _loadUnavailable
                ? AppLocalizations.t(context, 'daily_wear_unavailable_title')
                : AppLocalizations.t(context, 'daily_wear_wardrobe_alert'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _emptyStateMessage.isNotEmpty
                ? _emptyStateMessage
                : AppLocalizations.t(context, 'daily_wear_add_clothes_unlock'),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadUnavailable
                  ? () => _fetchDailyBoard()
                  // P0.21: this screen doesn't own WardrobeScreen's state,
                  // so a successful save signals completion through the
                  // existing shared AppwriteService.invalidateWardrobeCache()
                  // notifier — WardrobeScreen listens for it and reconciles.
                  : () => showAddToWardrobeModal(
                      context,
                      onSaved: (_) =>
                          AppwriteService().invalidateWardrobeCache(),
                    ),
              icon: Icon(_loadUnavailable ? Icons.refresh_rounded : Icons.add_a_photo_outlined),
              label: Text(
                _loadUnavailable
                    ? AppLocalizations.t(context, 'daily_wear_retry')
                    : AppLocalizations.t(context, 'daily_wear_add_wardrobe'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final backBtn = GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorderColor),
            ),
            child: Icon(Icons.chevron_left_rounded, color: textColor, size: 18),
          ),
        );
        final leftBlock = Row(
          children: [
            Text(
              AppLocalizations.t(context, 'daily_wear_title'),
              style: TextStyle(
                fontSize: 22.0,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [backBtn, const SizedBox(width: 12), leftBlock]),
              const SizedBox(height: 10),
              _buildDatePill(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [backBtn, const SizedBox(width: 12), leftBlock]),
                _buildDatePill(),
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _buildDatePill() => ValueListenableBuilder<String>(
    valueListenable: _liveTimeNotifier,
    builder: (_, __, ___) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.18),
            accent3Color.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: accentColor.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _liveDay,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            ' · ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accentColor.withValues(alpha: 0.5),
              letterSpacing: 1.2,
            ),
          ),
          Text(
            _liveDate,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _liveTime,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: accentColor.withValues(alpha: 0.65),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildWeatherBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      constraints: const BoxConstraints(minHeight: 68),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.13),
            accent2Color.withValues(alpha: 0.08),
            accent3Color.withValues(alpha: 0.11),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final left = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_weatherIcon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _weatherLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _weatherDetail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: mutedColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  )
              ),
            ],
          );
          final temp = ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, accent3Color],
            ).createShader(bounds),
            child: Text(
              _weatherTemp,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w300,
                color: textColor,
              ),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [left, const SizedBox(height: 8), temp],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: left),
              Flexible(child: temp),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildSuggestionBanner() {
    final icon = _suggestionBanner!.split(' ').first;
    final body = _suggestionBanner!.substring(icon.length).trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                body,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  letterSpacing: 0.2,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarousel() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      height: 340,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: cardBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.45),
                    blurRadius: 48,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: PageView.builder(
                controller: _pageController,
                itemCount: _displayedOutfits.length,
                onPageChanged: (i) => _carouselIndexNotifier.value = i,
                itemBuilder: (_, i) =>
                    _buildCarouselSlide(_displayedOutfits[i], i),
              ),
            ),
          ),
          _buildCarouselArrow(left: true),
          _buildCarouselArrow(left: false),
          Positioned(
            bottom: 82,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: _carouselIndexNotifier,
              builder: (_, idx, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_displayedOutfits.length, (i) {
                  final isOn = i == idx;
                  return GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      width: isOn ? 22 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isOn ? accentColor : mutedColor,
                        borderRadius: BorderRadius.circular(isOn ? 3 : 50),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildCarouselArrow({required bool left}) {
    return ValueListenableBuilder<int>(
      valueListenable: _carouselIndexNotifier,
      builder: (_, idx, __) {
        final disabled = left ? idx == 0 : idx == _displayedOutfits.length - 1;
        return Positioned(
          left: left ? 10 : null,
          right: left ? null : 10,
          top: 0,
          bottom: 80,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: disabled ? 0.3 : 1.0,
              child: _PressScaleButton(
                scaleDown: 0.92,
                onTap: disabled
                    ? null
                    : () {
                  if (left) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.30),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      left ? '‹' : '›',
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCarouselSlide(Map<String, dynamic> outfit, int index) {
    final outfitId = outfit['id'] as String;
    final saved = _savedCarouselById[outfitId] ?? false;
    final styleBoard = _styleBoardFromOutfit(outfit);

    if (styleBoard == null) {
      // Style Board data for this outfit hasn't come back from the
      // backend yet: show only the outfit layout, with no title, chips,
      // counter, or buttons on top of it.
      return _buildStyleBoardLoadingShell();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: RepaintBoundary(
            key: _boardCanvasKeyFor(outfitId),
            child: _buildUnifiedOutfitGrid(styleBoard),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Bottom-only darkening so the white outfit name +
                // counter chip stay legible. Previous gradient leaked
                // ~2 % alpha at the very top + 10 % at the midpoint,
                // which read as a permanent faded grey overlay across
                // the whole image. The top half is now fully clear.
                stops: const [0.0, 0.55, 0.78, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.32),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          right: 18,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  AppLocalizations.t(context, 'daily_wear_ahvi_pick'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Row(
                children: [
                  _circleAction(saved ? '❤️' : '🤍', () async {
                    if (saved) {
                      setState(() => _savedCarouselById[outfitId] = false);
                      return;
                    }
                    final bucket = await _showSaveOccasionSheet(outfit);
                    if (bucket == null || !mounted) return;
                    final ok = await _saveOutfitToBoards(
                      outfit,
                      occasionBucket: bucket,
                    );
                    if (!mounted) return;
                    if (ok) {
                      setState(() => _savedCarouselById[outfitId] = true);
                      _showToast(
                        AppLocalizations.t(
                          context,
                          'daily_wear_toast_saved_wardrobe',
                        ),
                      );
                    } else {
                      _showToast(
                        AppLocalizations.t(context, 'daily_wear_save_failed'),
                        green: false,
                      );
                    }
                  }),
                  const SizedBox(width: 8),
                  _circleShare(outfit),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.t(
                            context,
                            outfit['nameKey'] as String,
                          ),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.3,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.t(
                            context,
                            outfit['descKey'] as String,
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '${index + 1} / ${_displayedOutfits.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children:
                ((outfit['tags'] as List?)?.cast<String>() ?? <String>[])
                    .map(
                      (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
                    .toList(),
              ),
              const SizedBox(height: 14),
              _PressScaleButton(
                scaleDown: 0.98,
                opacityDown: 0.85,
                onTap: () => _openTryOn(outfitId),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accentColor, accent3Color],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Try-On',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tileTextColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleAction(String icon, VoidCallback onTap) => _PressScaleButton(
    scaleDown: 0.92,
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: panelColor,
        shape: BoxShape.circle,
        border: Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: Text(icon, style: TextStyle(fontSize: 15, color: textColor)),
      ),
    ),
  );

  Widget _circleShare(Map<String, dynamic> outfit) => _PressScaleButton(
    scaleDown: 0.92,
    onTap: () => _shareOutfit(outfit),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: panelColor,
        shape: BoxShape.circle,
        border: Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(16, 16),
          painter: _ShareIconPainter(color: textColor),
        ),
      ),
    ),
  );

  Widget _buildSectionTitle() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(
      AppLocalizations.t(context, 'daily_wear_other_options'),
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
        letterSpacing: 0.2,
      ),
    ),
  );

  Widget _buildOptionCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          if (compact) {
            return SizedBox(
              height: 268,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: optionCards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  return SizedBox(
                    width: 180,
                    child: _buildOptCard(optionCards[i]),
                  );
                },
              ),
            );
          }
          return Row(
            children: [
              for (var i = 0; i < optionCards.length; i++) ...[
                Expanded(child: _buildOptCard(optionCards[i])),
                if (i < optionCards.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildOptCard(Map<String, dynamic> card) {
    final outfitId = card['outfitId'] as String;
    final isWorn = _wornOutfitId == outfitId;
    final saved = _savedOptionById[outfitId] ?? false;
    final fullOutfit = _outfitById(outfitId);
    final styleBoard = _styleBoardFromOutfit(
      fullOutfit.isNotEmpty ? fullOutfit : card,
    );

    if (styleBoard == null) {
      // Style Board data for this outfit hasn't come back from the
      // backend yet: show only the outfit layout, with no title, chips,
      // or buttons on top of it.
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 115,
          child: _buildStyleBoardLoadingShell(),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.58, -0.58),
          end: const Alignment(0.58, 0.58),
          colors: (card['gradient'] as List).cast<Color>(),
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          children: [
            SizedBox(
              height: 115,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 320,
                        child: _buildUnifiedOutfitGrid(styleBoard),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.28, 1.0],
                          colors: [
                            Colors.black.withValues(alpha: 0),
                            Colors.black.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.t(context, card['nameKey'] as String),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.t(context, card['sub'] as String),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: mutedColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      _smallIcon(saved ? '❤️' : '🤍', () async {
                        if (saved) {
                          setState(() => _savedOptionById[outfitId] = false);
                          return;
                        }
                        final outfitData = _outfitById(outfitId);
                        if (outfitData.isEmpty) return;
                        final bucket = await _showSaveOccasionSheet(
                          outfitData,
                        );
                        if (bucket == null || !mounted) return;
                        final ok = await _saveOutfitToBoards(
                          outfitData,
                          occasionBucket: bucket,
                        );
                        if (!mounted) return;
                        if (ok) {
                          setState(() => _savedOptionById[outfitId] = true);
                          _showToast(
                            AppLocalizations.t(
                              context,
                              'daily_wear_toast_outfit_saved',
                            ),
                          );
                        } else {
                          _showToast(
                            AppLocalizations.t(context, 'daily_wear_save_failed'),
                            green: false,
                          );
                        }
                      }),
                      const SizedBox(width: 5),
                      _smallShare(
                        AppLocalizations.t(context, card['nameKey'] as String),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _smallButton(
                      isWorn
                          ? AppLocalizations.t(context, 'daily_wear_wearing')
                          : AppLocalizations.t(context, 'daily_wear_wear'),
                      isWorn ? null : () => _wearOutfit(outfitId),
                      primary: !isWorn,
                      activeLabelColor: isWorn ? accent3Color : tileTextColor,
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

  Widget _smallIcon(String icon, VoidCallback onTap) => _PressScaleButton(
    scaleDown: 0.92,
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: Text(
          icon,
          style: TextStyle(
            fontSize: 13,
            color: icon == '❤️' ? accent4Color : mutedColor,
          ),
        ),
      ),
    ),
  );

  Widget _smallShare(String text) => _PressScaleButton(
    scaleDown: 0.92,
    onTap: () {
      Clipboard.setData(ClipboardData(text: text));
      _showToast(AppLocalizations.t(context, 'daily_wear_toast_link_copied'));
    },
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(13, 13),
          painter: _ShareIconPainter(color: mutedColor),
        ),
      ),
    ),
  );

  Widget _smallButton(
      String label,
      VoidCallback? onTap, {
        required bool primary,
        required Color activeLabelColor,
      }) => _PressScaleButton(
    scaleDown: 0.96,
    opacityDown: 0.7,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 34,
      decoration: BoxDecoration(
        gradient: primary
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor, accent3Color],
        )
            : null,
        color: primary ? null : panelColor,
        borderRadius: BorderRadius.circular(10),
        border: primary ? null : Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: activeLabelColor,
          ),
        ),
      ),
    ),
  );

  Widget _buildChatFab() => IgnorePointer(
    ignoring: _chatOpen || _tryOnOpen,
    child: Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 20, bottom: 30),
        child: _PressScaleButton(
          scaleDown: 0.95,
          onTap: _openChat,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
            decoration: BoxDecoration(
              color: _t.accent.primary,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: _t.accent.primary.withValues(alpha: 0.40),
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
                    size: 12,
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
    ),
  );
  int _cacheWidth(BuildContext context, double logicalWidth) {
    final ratio = MediaQuery.of(context).devicePixelRatio;
    // Cap at 2x to prevent over-sampling on high-DPI Android devices
    // which causes a visible fade/flash while Flutter resizes the image
    return (logicalWidth * math.min(ratio, 2.0)).round();
  }

  Widget _chatHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
    child: Row(
      children: [
        _PressScaleButton(
          scaleDown: 0.90,
          onTap: _closeChat,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorderColor),
            ),
            child: Center(
              child: Icon(
                Icons.chevron_left_rounded,
                color: textColor,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AhviHomeText(
            color: textColor,
            fontSize: 28.0,
            letterSpacing: 3.2,
            fontWeight: FontWeight.w400,
          ),
        ),
        _PressScaleButton(
          scaleDown: 0.90,
          onTap: () => _chatScaffoldKey.currentState?.openDrawer(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: panelColor,
              shape: BoxShape.circle,
              border: Border.all(color: cardBorderColor),
            ),
            child: Center(
              child: Icon(Icons.history_rounded, color: mutedColor, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Chat options',
          onSelected: (value) {
            if (value == 'clear') _clearCurrentChat();
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(value: 'clear', child: Text('Clear chat')),
          ],
          icon: Icon(Icons.more_horiz_rounded, color: mutedColor),
        ),
      ],
    ),
  );

  Widget _chatMessages() {
    final showEmptyState = _messages.isEmpty;
    final itemCount = _messages.length + (_isTyping ? 1 : 0);
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (showEmptyState) {
          return const SizedBox.shrink();
        }

        if (_isTyping && i == _messages.length) {
          return const _TypingBubble();
        }
        final m = _messages[i];
        return _ChatBubble(
          message: m,
          isSpeaking: _speakingMessageId == m.id,
          onSpeak: m.isUser ? null : () => _speakMessage(m),
        );
      },
    );
  }

  Widget _chatQuickPrompts() => SizedBox(
    height: 52,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      itemCount: quickPrompts.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => _PressScaleButton(
        scaleDown: 0.94,
        onTap: () => _sendMessage(quickPrompts[i]),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardBorderColor),
          ),
          child: Center(
            child: Text(
              quickPrompts[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent5Color,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _chatBar() {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: phoneShellInnerColor,
        border: Border(top: BorderSide(color: cardBorderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attachment preview chip — shown when a file / image / web search is pending
          AhviChatPromptBar(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            controller: _chatController,
            focusNode: _chatFocusNode,
            hintText: AppLocalizations.t(context, 'daily_wear_chat_hint'),
            hasTextListenable: _chatController,
            surface: phoneShellInnerColor,
            border: cardBorderColor,
            accent: accentColor,
            accentSecondary: accent2Color,
            textHeading: textColor,
            textMuted: mutedColor,
            shadowMedium: bgColor.withValues(alpha: 0.20),
            onAccent: tileTextColor,
            onSendMessage: _sendMessage,
            themeTokens: context.themeTokens,
            onVisualSearch: null,
            onFindSimilar: null,
            onAddToWardrobe: null,
          ),
        ],
      ),
    );
  }

  Widget _buildTryOnOverlay() => Stack(
    children: [
      // Scrim
      Positioned.fill(
        child: GestureDetector(
          onTap: _closeTryOn,
          child: const ColoredBox(color: Color(0x00000000)),
        ),
      ),
      // Sheet — no animation
      Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: BoxDecoration(
                color: bg2Color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: cardBorderColor),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  32 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: panel2Color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.topRight,
                      child: _PressScaleButton(
                        scaleDown: 0.90,
                        onTap: _closeTryOn,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: panelColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Center(
                            child: Text(
                              '✕',
                              style: TextStyle(color: mutedColor),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.t(context, 'daily_wear_build_outfit'),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.t(
                        context,
                        'daily_wear_fitting',
                      ).replaceAll(
                        '{name}',
                        _selectedTryOnOutfit['name'] as String,
                      ),
                      style: TextStyle(fontSize: 13, color: mutedColor),
                    ),
                    const SizedBox(height: 18),
                    _tryOnBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _tryOnBody() {
    final outfit = _selectedTryOnOutfit;
    if (_tryOnStage == _TryOnStage.loading) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: accentColor,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _tryOnLoadingMessage,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLocalizations.t(context, 'wear_preparing_ar'),
                style: TextStyle(color: mutedColor),
              ),
            ],
          ),
        ),
      );
    }
    if (_tryOnStage == _TryOnStage.camera) {
      final colors =
      ((outfit['colors'] as List?)?.cast<String>() ?? <String>[]);
      final tags =
      ((outfit['arTags'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[]);
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LayoutBuilder(
                builder: (_, constraints) => Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 14,
                      child: Row(
                        children: [
                          const _LiveDot(),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.t(context, 'daily_wear_live_ar'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _frontCamera
                                ? AppLocalizations.t(context, 'daily_wear_hd_front')
                                : AppLocalizations.t(context, 'daily_wear_hd_back'),
                            style: TextStyle(fontSize: 10, color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Container(
                        width: constraints.maxWidth * 0.52,
                        height: constraints.maxHeight * 0.80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(120),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    TickerMode(
                      enabled: _tryOnOpen && _tryOnStage == _TryOnStage.camera,
                      child: AnimatedBuilder(
                        animation: _scanCtrl,
                        builder: (_, _) => Positioned(
                          top: constraints.maxHeight * _scanLineY.value,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            color: accentColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(
                      math.min(_visibleArTags, tags.length),
                          (index) => Positioned(
                        left:
                        constraints.maxWidth *
                            (tags[index]['left'] as double),
                        top:
                        constraints.maxHeight *
                            (tags[index]['top'] as double),
                        child: _ArTag(
                          label: AppLocalizations.t(
                            context,
                            tags[index]['t'] as String,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(colors.length, (i) {
                              final selected = i == _selectedSwatchIndex;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedSwatchIndex = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 26,
                                  height: 26,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _parseHexColor(colors[i]),
                                    border: Border.all(
                                      color: selected
                                          ? accentColor
                                          : cardBorderColor,
                                      width: selected ? 2.5 : 2,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  '📸 ${AppLocalizations.t(context, 'daily_wear_capture')}',
                  _captureTryOn,
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: _actionBtn('🔄', _flipCamera, primary: false),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: _actionBtn(
                  '✕',
                      () => setState(() => _tryOnStage = _TryOnStage.preview),
                  primary: false,
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (_tryOnStage == _TryOnStage.captured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ColoredBox(color: panelColor),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent3Color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accent3Color.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '✓ ${AppLocalizations.t(context, 'daily_wear_captured').toUpperCase()}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent3Color,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.50),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ' ${AppLocalizations.t(context, outfit['nameKey'] as String)} · AHVI',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        Text(
                          _formatCapturedDate(DateTime.now()),
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor.withValues(alpha: 0.42),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  AppLocalizations.t(context, 'daily_wear_save_look'),
                  _saveCapturedLook,
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  AppLocalizations.t(context, 'daily_wear_retake'),
                  _startTryOnCamera,
                  primary: false,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              SizedBox(
                height: 260,
                width: double.infinity,
                child: ColoredBox(color: panelColor),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.4, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.t(context, 'daily_wear_ar_mode'),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                left: 18,
                child: Text(
                  AppLocalizations.t(context, outfit['nameKey'] as String),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Text('💡'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.t(context, outfit['tipKey'] as String),
                  style: TextStyle(
                    fontSize: 12,
                    color: mutedColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                AppLocalizations.t(context, 'daily_wear_start_tryon'),
                _startTryOnCamera,
                primary: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn(
      String label,
      VoidCallback onTap, {
        required bool primary,
      }) => _PressScaleButton(
    scaleDown: 0.97,
    opacityDown: 0.78,
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: primary
            ? LinearGradient(colors: [accentColor, accent3Color])
            : null,
        color: primary ? null : panel2Color,
        borderRadius: BorderRadius.circular(16),
        border: primary ? null : Border.all(color: cardBorderColor),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primary ? tileTextColor : accent5Color,
          ),
        ),
      ),
    ),
  );
}

class _PressScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final double opacityDown;
  const _PressScaleButton({
    required this.child,
    required this.onTap,
    this.scaleDown = 0.94,
    this.opacityDown = 1.0,
  });
  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1,
      end: widget.scaleDown,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 1,
      end: widget.opacityDown,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.onTap == null ? null : (_) => _ctrl.forward(),
    onTapUp: widget.onTap == null
        ? null
        : (_) {
      _ctrl.reverse();
      widget.onTap?.call();
    },
    onTapCancel: () => _ctrl.reverse(),
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: widget.child,
    ),
  );
}

class _ChatMessage {
  final int id;
  final String text;
  final bool isUser;
  final DateTime createdAt;
  final bool excludeFromSemanticHistory;
  _ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
    this.excludeFromSemanticHistory = false,
  });
}

class _ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<_ChatMessage> messages;

  _ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messages,
  });
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isSpeaking;
  final VoidCallback? onSpeak;
  const _ChatBubble({
    required this.message,
    required this.isSpeaking,
    required this.onSpeak,
  });
  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final isUser = message.isUser;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(
              radius: 15,
              backgroundColor: t.accent.primary,
              child: Icon(Icons.auto_awesome_rounded, size: 14),
            ),
          if (!isUser) const SizedBox(width: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: isUser
                      ? null
                      : BoxDecoration(
                    color: t.panel,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: const Radius.circular(4),
                      bottomRight: const Radius.circular(20),
                    ),
                    border: Border.all(color: t.cardBorder),
                  ),
                  child: isUser
                      ? Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: t.textPrimary,
                          ),
                        )
                      : BasicMarkdownText(
                          message.text,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: t.textPrimary,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(fontSize: 10, color: t.mutedText),
                    ),
                    if (!isUser && onSpeak != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onSpeak,
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 14,
                          color: isSpeaking ? t.accent.secondary : t.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 9),
          if (isUser)
            CircleAvatar(
              radius: 15,
              backgroundColor: t.panelBorder,
              child: Text(
                '👤',
                style: TextStyle(fontSize: 12, color: t.mutedText),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chat-facing wrapper — delegates to the shared branded [AhviProcessingBubble].
class _TypingBubble extends StatelessWidget {
  final String message;
  const _TypingBubble({String? message})
      : message = message ?? 'AHVI is thinking';

  @override
  Widget build(BuildContext context) =>
      AhviProcessingBubble(message: message);
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.28, end: 1).animate(_ctrl),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [t.accent.primary, t.accent.secondary],
          ),
        ),
      ),
    );
  }
}

class _ArTag extends StatelessWidget {
  final String label;
  const _ArTag({required this.label});
  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.backgroundPrimary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: t.accent.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool green;
  const _ToastWidget({required this.message, required this.green});
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _slide = Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _ctrl, curve: const Cubic(0.32, 0.72, 0, 1)),
    );

    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final accent3Color = t.accent.tertiary;
    final phoneShellColor = t.phoneShell;
    final cardBorderColor = t.cardBorder;
    final textColor = t.textPrimary;
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 30,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: widget.green
                      ? accent3Color.withValues(alpha: 0.15)
                      : phoneShellColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: widget.green
                        ? accent3Color.withValues(alpha: 0.35)
                        : cardBorderColor,
                  ),
                ),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.green ? accent3Color : textColor,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareIconPainter extends CustomPainter {
  final Color color;
  const _ShareIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.092
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final double r = w * 0.125;

    canvas.drawCircle(Offset(w * 0.75, h * 0.208), r, paint);
    canvas.drawCircle(Offset(w * 0.25, h * 0.5), r, paint);
    canvas.drawCircle(Offset(w * 0.75, h * 0.792), r, paint);
    canvas.drawLine(
      Offset(w * 0.358, h * 0.563),
      Offset(w * 0.643, h * 0.271),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.358, h * 0.437),
      Offset(w * 0.643, h * 0.729),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShareIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
