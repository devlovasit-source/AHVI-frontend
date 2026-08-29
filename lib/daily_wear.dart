import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myapp/app_localizations.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:myapp/home_card_summary_provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/editorial_board_renderer.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';
import 'package:myapp/style_board/board_exporter.dart';

enum _TryOnStage { preview, loading, camera, captured }

class _DailyOccasionOption {
  final String key;
  final String label;
  final IconData icon;
  final String occasionCode;

  const _DailyOccasionOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.occasionCode,
  });
}

const List<_DailyOccasionOption> _dailyOccasionOptions = [
  _DailyOccasionOption(
    key: 'daily',
    label: 'Daily Wear',
    icon: Icons.wb_sunny_rounded,
    occasionCode: 'daily',
  ),
  _DailyOccasionOption(
    key: 'office_fits',
    label: 'Office Fits',
    icon: Icons.work_outline_rounded,
    occasionCode: 'office',
  ),
  _DailyOccasionOption(
    key: 'party_looks',
    label: 'Party Looks',
    icon: Icons.celebration_rounded,
    occasionCode: 'party',
  ),
  _DailyOccasionOption(
    key: 'vacation',
    label: 'Vacation & Travel',
    icon: Icons.flight_takeoff_rounded,
    occasionCode: 'travel',
  ),
  _DailyOccasionOption(
    key: 'occasion',
    label: 'Occasions & Events',
    icon: Icons.diamond_outlined,
    occasionCode: 'wedding',
  ),
  _DailyOccasionOption(
    key: 'everything_else',
    label: 'Everything Else',
    icon: Icons.auto_awesome_rounded,
    occasionCode: 'casual',
  ),
];

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

  @override
  State<DailyWearScreen> createState() => _DailyWearScreenState();
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
  bool _hasLoggedWear = false;
  bool _isLoading = true;
  bool _needsMoreClothes = false;
  String _emptyStateMessage = '';
  final PageController _pageController = PageController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Map<String, bool> _savedCarouselById = {};
  Map<String, bool> _savedOptionById = {};
  final Map<String, String> _savedBoardDocIds = {};
  final Map<String, GlobalKey> _boardCanvasKeys = {};

  String? _wornOutfitId;
  Timer? _autoPlayTimer;
  bool _userScrolling = false;
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _quickPromptsVisible = true;
  Timer? _chatGreetingTimer;

  final List<_ChatSession> _chatHistory = [];
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final GlobalKey<ScaffoldState> _chatScaffoldKey = GlobalKey<ScaffoldState>();

  int? _speakingMessageId;

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
  bool _bannerVisible = false;

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
    _checkSavedStates(outfits);
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

  Future<void> _checkSavedStates(List<Map<String, dynamic>> outfits) async {
    try {
      final savedList = await SavedBoardsStore.list();
      final savedIds = <String>{};
      for (final s in savedList) {
        final dir = s['direction'];
        if (dir is Map && dir['id'] != null) {
          savedIds.add(dir['id'].toString());
        }
        if (s['id'] != null) {
          savedIds.add(s['id'].toString());
        }
      }
      if (!mounted) return;
      setState(() {
        for (final outfit in outfits) {
          final id = (outfit['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final rawTitle = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look').toString().trim();
          final title = AppLocalizations.t(context, rawTitle);
          final storeId = SavedBoardsStore.idFor(occasion: 'daily', directionName: title);
          final isSaved = savedIds.contains(id) || savedIds.contains(storeId);
          _savedCarouselById[id] = isSaved;
          _savedOptionById[id] = isSaved;
        }
      });
    } catch (e) {
      debugPrint('Failed checking saved states: $e');
    }
  }

  Map<String, dynamic> _outfitById(String id) {
    final found = _displayedOutfits.where((o) => o['id'] == id);
    if (found.isNotEmpty) return found.first;
    final fallback = _fallbackOutfits();
    final fallbackFound = fallback.where((o) => o['id'] == id);
    return fallbackFound.isNotEmpty ? fallbackFound.first : <String, dynamic>{};
  }

  static List<dynamic> _firstNonEmptyBoardItems(Map<String, dynamic> outfit) =>
      DailyWearScreen.firstNonEmptyBoardItems(outfit);

  Map<String, dynamic> _normalizeDailyBoardCard(
      Map<String, dynamic> card,
      int index,
      ) {
    final rawItems = _firstNonEmptyBoardItems(card);
    final items = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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

  BoardItemRole _boardItemRoleFromString(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'top':
        return BoardItemRole.top;
      case 'bottom':
        return BoardItemRole.bottom;
      case 'footwear':
      case 'shoe':
      case 'shoes':
        return BoardItemRole.footwear;
      case 'outerwear':
      case 'jacket':
      case 'coat':
        return BoardItemRole.outerwear;
      case 'dress':
        return BoardItemRole.dress;
      case 'accessory':
      case 'accessories':
        return BoardItemRole.accessory;
      default:
        return BoardItemRole.unknown;
    }
  }

  StyleBoardItem _styleBoardItemFromMap(Map<String, dynamic> item) {
    final imageUrl = (item['image_url'] ??
        item['imageUrl'] ??
        item['img'] ??
        item['photo_url'] ??
        '')
        .toString()
        .trim();
    final id = (item['id'] ?? item['item_id'] ?? item['itemId'] ?? imageUrl)
        .toString();
    final name = (item['name'] ?? item['title'] ?? item['label'] ?? '')
        .toString();
    final category = (item['category'] ?? item['type'] ?? '').toString();
    return StyleBoardItem(
      id: id,
      name: name,
      imageUrl: imageUrl,
      category: category,
      role: _boardItemRoleFromString(
        (item['role'] ?? item['category'] ?? item['type'])?.toString(),
      ),
      raw: item,
    );
  }

  StyleBoardData? _styleBoardFromOutfit(Map<String, dynamic> outfit) {
    final rawItems = _firstNonEmptyBoardItems(outfit);
    if (rawItems.isEmpty) return null;
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

  Widget _buildStyleBoardLoadingShell() => Container(
    width: double.infinity,
    height: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
  );

  Widget _buildOutfitVisual(Map<String, dynamic> outfit) {
    final styleBoard = _styleBoardFromOutfit(outfit);
    if (styleBoard == null) return _buildStyleBoardLoadingShell();
    return EditorialBoardCanvas(board: styleBoard);
  }

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
    final intent = response?['intent']?.toString().toLowerCase().trim();
    final alert = response?['alert'] == true;
    final nestedIntent =
    data is Map ? data['intent']?.toString().toLowerCase().trim() : null;
    final nestedAlert = data is Map ? data['alert'] == true : false;
    return intent == 'insufficient_wardrobe' ||
        nestedIntent == 'insufficient_wardrobe' ||
        alert ||
        nestedAlert;
  }

  Future<void> _fetchDailyBoard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _needsMoreClothes = false;
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
        : _fallbackOutfits();

    setState(() {
      _applyOutfits(outfits);
      _isLoading = false;
      _needsMoreClothes = false;
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



    _pageController.addListener(_onPageScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_chatOpen || _tryOnOpen) {
        setState(() {
          _chatOpen = false;
          _tryOnOpen = false;
        });
      }
      try {
        final rootNav = Navigator.of(context, rootNavigator: true);
        while (rootNav.canPop()) {
          final route = ModalRoute.of(rootNav.context);
          if (route is PopupRoute || route is RawDialogRoute) {
            rootNav.pop();
          } else {
            break;
          }
        }
      } catch (_) {}
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
      if (!mounted || !_pageController.hasClients || _userScrolling || _displayedOutfits.isEmpty) return;
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
    const fallbackLat = 16.5062;
    const fallbackLon = 80.648;
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=$fallbackLat&longitude=$fallbackLon'
            '&current=temperature_2m,weathercode,apparent_temperature'
            '&timezone=auto',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>;
        final temp = (current['temperature_2m'] as num).round();
        final feel = (current['apparent_temperature'] as num).round();
        final code = current['weathercode'] as int;
        _applyWeather(temp, feel, code, context);
      }
    } catch (_) {
      debugPrint('AHVI_HEAVY_SCREEN_LOAD timeout screen=DailyWear');
      final hour = DateTime.now().hour;
      const baseTemps = [
        22,
        21,
        21,
        21,
        22,
        23,
        25,
        27,
        29,
        31,
        32,
        33,
        33,
        33,
        32,
        31,
        30,
        29,
        28,
        27,
        26,
        25,
        24,
        23,
      ];
      final t = baseTemps[hour];
      final feel = t + (hour >= 10 && hour <= 16 ? 2 : 0);
      final code = (hour >= 6 && hour <= 18)
          ? (hour >= 11 && hour <= 14 ? 1 : 2)
          : 0;
      _applyWeather(t, feel, code);
    }
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
    int score(Map<String, dynamic> outfit) {
      final range = ((outfit['range'] as List?)?.cast<int>() ?? [0, 99]);
      final low = range[0];
      final high = range[1];
      if (temp >= low && temp <= high) return 2;
      final delta = temp < low ? low - temp : temp - high;
      return delta <= 5 ? 1 : 0;
    }

    final baseOutfits = _displayedOutfits.isNotEmpty
        ? List<Map<String, dynamic>>.from(_displayedOutfits)
        : _fallbackOutfits();
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
          _tryOnOutfitId ??= sorted.first['id'] as String;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
    });
  }

  void _removeOverlay() {
    try {
      _toastEntry?.remove();
    } catch (_) {}
    _toastEntry = null;
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _chatController.dispose();
    _removeOverlay();
    _chatScrollController.dispose();
    _scanCtrl.dispose();
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
    super.dispose();
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
      if (!mounted) return;
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
    _recordWear(outfit);
    _pushWearToHome(outfit);
  }

  void _pushWearToHome(Map<String, dynamic> outfit) {
    try {
      final outfitName = AppLocalizations.t(context, outfit['nameKey'] as String);
      context.read<HomeCardSummaryProvider>().markWearDone(
        done: true,
        outfitName: outfitName,
      );
    } catch (_) {}
  }

  void _recordWear(Map<String, dynamic> outfit) {
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

    addFrom(outfit['items']);
    addFrom(outfit['used_wardrobe_items']);
    addFrom(outfit['item_ids']);
    if (ids.isEmpty) return;

    BackendService()
        .wearToday(
      itemIds: ids,
      boardId: (outfit['id'] ?? '').toString(),
      occasion: (outfit['occasion'] ?? '').toString(),
    )
        .then((ok) {
      if (!mounted) return;
      _showToast(
        ok
            ? AppLocalizations.t(context, 'daily_wear_toast_style_history_added')
            : AppLocalizations.t(context, 'daily_wear_toast_update_failed'),
        green: ok,
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

  void _openTryOn([String? outfitId]) {
    HapticFeedback.lightImpact();
    _clearTransientInputOverlay();
    _resetTryOnSimulation();
    setState(() {
      _tryOnOutfitId = outfitId ?? _currentOutfit['id'] as String;
      _tryOnOpen = true;
      _tryOnStage = _TryOnStage.preview;
    });
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

  List<String> _currentOutfitItemIds() {
    final ids = <String>{};
    for (final item in _currentOutfitItems()) {
      final rawId =
          item['id'] ?? item['item_id'] ?? item['itemId'] ?? item[r'$id'];
      final id = rawId?.toString().trim() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList(growable: false);
  }

  Future<void> _persistCurrentLook() async {
    final outfit = _currentOutfit;
    final imageUrl = (outfit['img'] ?? '').toString().trim();
    final title = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look')
        .toString()
        .trim();
    final description =
    (outfit['desc'] ?? outfit['tip'] ?? 'AHVI curated daily drop')
        .toString()
        .trim();
    final itemIds = _currentOutfitItemIds();
    final outfitItems = _currentOutfitItems();

    try {
      final saved = await AppwriteService().saveBoardToCollection(
        occasion: 'daily',
        outfitDescription:
        description.isEmpty ? 'AHVI curated daily drop' : description,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        boardCategory: 'daily',
        boardCategoryLabel: 'Daily Wear',
        title: title.isEmpty ? 'Daily Look' : title,
        prompt: 'Saved from Daily Wear',
        extra: {
          'itemIds': itemIds,
          'outfitItems': outfitItems,
          'items': outfitItems,
          'board_payload': {
            'title': title.isEmpty ? 'Daily Look' : title,
            'occasion': 'daily',
            'items': outfitItems,
          },
          'boardPayload': {
            'title': title.isEmpty ? 'Daily Look' : title,
            'occasion': 'daily',
            'items': outfitItems,
          },
        },
        emoji: '✨',
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

  Future<void> _shareOutfit(Map<String, dynamic> outfit) async {
    final outfitId = (outfit['id'] ?? '').toString();
    final titleKey = (outfit['nameKey'] ?? outfit['name'] ?? 'Daily Look').toString();
    final descKey = (outfit['descKey'] ?? outfit['desc'] ?? outfit['tip'] ?? '').toString();

    final title = AppLocalizations.t(context, titleKey);
    final desc = AppLocalizations.t(context, descKey);

    final shareText = '✨ AHVI Daily Wear Pick: $title\n\n'
        '${desc.isNotEmpty ? "$desc\n\n" : ""}'
        'Styled by AHVI — Your AI Personal Stylist';

    final canvasKey = _boardCanvasKeys[outfitId];
    if (canvasKey != null && canvasKey.currentContext != null) {
      try {
        final rawItems = _firstNonEmptyBoardItems(outfit);
        for (final item in rawItems.whereType<Map>()) {
          final imgUrl = (item['image_url'] ?? item['imageUrl'] ?? item['img'] ?? '').toString();
          if (imgUrl.isNotEmpty && imgUrl.startsWith('http')) {
            try {
              await precacheImage(NetworkImage(imgUrl), context);
            } catch (_) {}
          }
        }

        final bytes = await BoardExporter.capturePng(canvasKey);
        if (bytes != null) {
          final file = await BoardExporter.writeToTempFile(bytes, filename: 'ahvi_daily_board_$outfitId.png');
          if (file != null) {
            await Share.shareXFiles(
              [XFile(file.path, mimeType: 'image/png')],
              subject: 'AHVI Daily Wear: $title',
              text: shareText,
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('Failed sharing daily board image: $e');
      }
    }

    try {
      final result = await Share.share(
        shareText,
        subject: 'AHVI Daily Wear: $title',
      );
      if (result.status == ShareResultStatus.success) {
        _showToast(AppLocalizations.t(context, 'daily_wear_toast_link_copied'));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: shareText));
      _showToast(AppLocalizations.t(context, 'daily_wear_toast_link_copied'));
    }
  }

  Future<_DailyOccasionOption?> _showOccasionPickerSheet(
    BuildContext context,
    Map<String, dynamic> outfit,
  ) async {
    final titleKey = (outfit['nameKey'] ?? outfit['name'] ?? 'Daily Look').toString();
    final outfitTitle = AppLocalizations.t(context, titleKey);

    return showModalBottomSheet<_DailyOccasionOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cardBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cardBorderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.bookmark_add_rounded, color: accentColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Save to Board Location',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose occasion board for "$outfitTitle"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final option in _dailyOccasionOptions) ...[
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: panel2Color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(option.icon, color: accentColor, size: 20),
                            ),
                            title: Text(
                              option.label,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: mutedColor,
                              size: 20,
                            ),
                            onTap: () => Navigator.of(ctx).pop(option),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSaveOutfit(Map<String, dynamic> outfit) async {
    final outfitId = (outfit['id'] ?? '').toString().trim();
    if (outfitId.isEmpty) return;

    final currentlySaved = (_savedCarouselById[outfitId] ?? false) || (_savedOptionById[outfitId] ?? false);

    if (!currentlySaved) {
      final selectedOccasion = await _showOccasionPickerSheet(context, outfit);
      if (selectedOccasion == null) {
        return;
      }

      final success = await _saveOutfitToBoards(outfit, selectedOccasion: selectedOccasion);
      if (success) {
        setState(() {
          _savedCarouselById[outfitId] = true;
          _savedOptionById[outfitId] = true;
        });
        _showToast('Saved to ${selectedOccasion.label}');
      } else {
        setState(() {
          _savedCarouselById[outfitId] = false;
          _savedOptionById[outfitId] = false;
        });
        _showToast(AppLocalizations.t(context, 'daily_wear_save_failed'));
      }
    } else {
      setState(() {
        _savedCarouselById[outfitId] = false;
        _savedOptionById[outfitId] = false;
      });

      final toastMsg = AppLocalizations.t(context, 'daily_wear_toast_removed_wardrobe');
      _showToast(toastMsg == 'daily_wear_toast_removed_wardrobe' ? 'Removed from Saved Boards' : toastMsg);
      await _unsaveOutfit(outfitId, outfit);
    }
  }

  Future<bool> _saveOutfitToBoards(
    Map<String, dynamic> outfit, {
    _DailyOccasionOption selectedOccasion = const _DailyOccasionOption(
      key: 'daily',
      label: 'Daily Wear',
      icon: Icons.wb_sunny_rounded,
      occasionCode: 'daily',
    ),
  }) async {
    final outfitId = (outfit['id'] ?? '').toString().trim();
    final imageUrl = (outfit['img'] ?? '').toString().trim();
    final rawTitle = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look').toString().trim();
    final title = AppLocalizations.t(context, rawTitle);

    final rawDesc = (outfit['desc'] ?? outfit['descKey'] ?? outfit['tip'] ?? 'AHVI curated daily drop').toString().trim();
    final description = AppLocalizations.t(context, rawDesc);

    final rawItems = _firstNonEmptyBoardItems(outfit);
    final outfitItems = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final itemIds = outfitItems
        .map(
          (item) =>
              (item['id'] ??
                      item['item_id'] ??
                      item['itemId'] ??
                      item[r'$id'])
                  ?.toString()
                  .trim() ??
              '',
        )
        .where((id) => id.isNotEmpty)
        .toList();

    dynamic doc;
    try {
      doc = await AppwriteService().saveBoardToCollection(
        occasion: selectedOccasion.occasionCode,
        outfitDescription: description.isEmpty ? 'AHVI curated daily drop' : description,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        boardCategory: selectedOccasion.key,
        boardCategoryLabel: selectedOccasion.label,
        title: title.isEmpty ? 'Daily Look' : title,
        prompt: 'Saved from Daily Wear to ${selectedOccasion.label}',
        extra: {
          'outfitId': outfitId,
          'itemIds': itemIds,
          'outfitItems': outfitItems,
          'items': outfitItems,
          'board_payload': {
            'title': title.isEmpty ? 'Daily Look' : title,
            'occasion': selectedOccasion.occasionCode,
            'board_category': selectedOccasion.key,
            'items': outfitItems,
          },
        },
        emoji: '✨',
      );
    } catch (e) {
      debugPrint('Failed to save daily look to Appwrite boards: $e');
      return false;
    }

    if (doc == null) {
      debugPrint('Appwrite saveBoardToCollection returned null; aborting local cache write.');
      return false;
    }

    if (outfitId.isNotEmpty) {
      _savedBoardDocIds[outfitId] = doc.$id;
    }

    try {
      await SavedBoardsStore.saveBoard(
        occasion: selectedOccasion.occasionCode,
        directionName: title.isEmpty ? 'Daily Look' : title,
        direction: {
          'id': outfitId,
          'direction_name': title,
          'title': title,
          'why_it_works': description,
          'short_note': description,
          'board_category': selectedOccasion.key,
          'board_category_label': selectedOccasion.label,
          'owned_items': outfitItems,
          'items': outfitItems,
        },
        editorialCover: {'image_url': imageUrl},
      );
    } catch (e) {
      debugPrint('Failed local saved boards store save: $e');
    }

    return true;
  }

  Future<void> _unsaveOutfit(String outfitId, Map<String, dynamic> outfit) async {
    final rawTitle = (outfit['name'] ?? outfit['nameKey'] ?? 'Daily Look').toString().trim();
    final title = AppLocalizations.t(context, rawTitle);
    final boardStoreId = SavedBoardsStore.idFor(occasion: 'daily', directionName: title);

    try {
      await SavedBoardsStore.remove(boardStoreId);
    } catch (e) {
      debugPrint('Failed to remove from local saved boards store: $e');
    }

    final docId = _savedBoardDocIds[outfitId];
    if (docId != null && docId.isNotEmpty) {
      try {
        await AppwriteService().deleteSavedBoard(docId);
        _savedBoardDocIds.remove(outfitId);
      } catch (e) {
        debugPrint('Failed to delete saved board from Appwrite: $e');
      }
    }
  }

  Future<void> _logWearForCurrentLook() async {
    final itemIds = _currentOutfitItemIds();
    if (itemIds.isEmpty || _hasLoggedWear) return;

    setState(() => _hasLoggedWear = true);
    try {
      final ok = await BackendService().wearToday(
        itemIds: itemIds,
        boardId: (_currentOutfit['id'] ?? '').toString(),
        occasion: (_currentOutfit['occasion'] ?? '').toString(),
      );
      if (!ok) {
        if (!mounted) return;
        setState(() => _hasLoggedWear = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to log outfit. Try again.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Outfit logged! We'll rotate these pieces tomorrow."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasLoggedWear = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to log outfit. Try again.')),
      );
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
    final wornNote = _wornOutfitId != null
        ? 'Wearing today: "${_outfitById(_wornOutfitId!)['name']}"'
        : 'No outfit chosen yet.';
    final prompt =
        '$userText\n\n'
        'Current outfit: ${currentOutfit['name']} - ${currentOutfit['desc']}. '
        'Tags: ${((currentOutfit['tags'] as List?)?.cast<String>() ?? <String>[]).join(', ')}. '
        'Occasions: ${((currentOutfit['occ'] as List?)?.cast<String>() ?? <String>[]).join(', ')}. '
        'Weather: ${_weatherContext.isEmpty ? 'unknown' : _weatherContext}. $wornNote';

    final history = _messages
        .take(_messages.length - 1)
        .map(
          (m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    )
        .toList();

    try {
      final response = await BackendService().sendChatQuery(
        prompt,
        '',
        List<Map<String, String>>.from(history),
        '',
        moduleContext: 'style',
      );
      if (!mounted) return;
      final rawMessage = response['message'];
      final replyText =
      (response['message_text'] ??
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
        text: 'AHVI style request failed: $err',
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
                    else if (_needsMoreClothes)
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
        ),
      ),
    );
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
            child: Icon(Icons.checkroom_rounded, color: accentColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.t(context, 'daily_wear_wardrobe_alert'),
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
              onPressed: () => showAddToWardrobeModal(context),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(AppLocalizations.t(context, 'daily_wear_add_wardrobe')),
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
      return _buildStyleBoardLoadingShell();
    }

    final canvasKey = _boardCanvasKeys.putIfAbsent(outfitId, () => GlobalKey());

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: canvasKey,
          child: EditorialBoardCanvas(board: styleBoard),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
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
                  _circleAction(
                    saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    () {
                      _toggleSaveOutfit(outfit);
                    },
                  ),
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
                      'Build Outfit',
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

  Widget _circleAction(dynamic icon, VoidCallback onTap) => _PressScaleButton(
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
        child: icon is IconData
            ? Icon(icon, size: 18, color: icon == Icons.bookmark_rounded ? accentColor : textColor)
            : Text(icon.toString(), style: TextStyle(fontSize: 15, color: textColor)),
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

    final optionCanvasKey = _boardCanvasKeys.putIfAbsent(outfitId, () => GlobalKey());

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
                  RepaintBoundary(
                    key: optionCanvasKey,
                    child: EditorialBoardCanvas(board: styleBoard),
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
                      _smallIcon(
                        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        () {
                          final outfitData = _outfitById(outfitId);
                          _toggleSaveOutfit(
                            outfitData.isNotEmpty
                                ? outfitData
                                : {
                                    'id': outfitId,
                                    'nameKey': card['nameKey'],
                                    'name': card['name'],
                                    'descKey': card['sub'],
                                    'desc': card['sub'],
                                    'img': card['img'],
                                  },
                          );
                        },
                      ),
                      const SizedBox(width: 5),
                      _smallShare(
                        fullOutfit.isNotEmpty
                            ? fullOutfit
                            : {
                                'id': outfitId,
                                'nameKey': card['nameKey'],
                                'name': card['name'],
                                'descKey': card['sub'],
                                'desc': card['sub'],
                                'img': card['img'],
                              },
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

  Widget _smallIcon(dynamic icon, VoidCallback onTap) => _PressScaleButton(
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
        child: icon is IconData
            ? Icon(icon, size: 16, color: icon == Icons.bookmark_rounded ? accentColor : mutedColor)
            : Text(
                icon.toString(),
                style: TextStyle(
                  fontSize: 13,
                  color: icon == '❤️' ? accent4Color : mutedColor,
                ),
              ),
      ),
    ),
  );

  Widget _smallShare(Map<String, dynamic> outfit) => _PressScaleButton(
    scaleDown: 0.92,
    onTap: () => _shareOutfit(outfit),
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
      Positioned.fill(
        child: GestureDetector(
          onTap: _closeTryOn,
          child: const ColoredBox(color: Color(0x00000000)),
        ),
      ),
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
                        builder: (_, __) => Positioned(
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _actionBtn(
              AppLocalizations.t(context, 'daily_wear_wear_today'),
              _logWearForCurrentLook,
              primary: true,
            ),
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
            const SizedBox(width: 10),
            Expanded(
              child: _actionBtn(
                AppLocalizations.t(context, 'daily_wear_wear_today'),
                _logWearForCurrentLook,
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
  _ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
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
                  child: _RichChatText(
                    text: message.text,
                    color: t.textPrimary,
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

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: t.accent.primary,
          child: Icon(Icons.auto_awesome_rounded, size: 14),
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.cardBorder),
          ),
          child: Row(
            children: List.generate(
              3,
                  (i) => _BounceDot(controller: _ctrl, delay: i * 0.18),
            ),
          ),
        ),
      ],
    );
  }
}

class _BounceDot extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  const _BounceDot({required this.controller, required this.delay});
  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final anim =
    TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -6),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -6, end: 0),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
    ]).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          delay,
          (delay + 0.5).clamp(0, 1.0),
          curve: Curves.easeInOut,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, anim.value),
        child: Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            color: t.accent.primary.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _RichChatText extends StatelessWidget {
  final String text;
  final Color color;
  const _RichChatText({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: TextStyle(fontSize: 13.5, height: 1.6, color: color),
      children: _parse(text),
    ),
  );
  List<InlineSpan> _parse(String raw) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*.*?\*\*|\*.*?\*)');
    var last = 0;
    for (final match in regex.allMatches(raw)) {
      if (match.start > last) {
        spans.add(TextSpan(text: raw.substring(last, match.start)));
      }
      final token = match.group(0)!;
      spans.add(
        TextSpan(
          text: token.startsWith('**')
              ? token.substring(2, token.length - 2)
              : token.substring(1, token.length - 1),
          style: TextStyle(
            fontWeight: token.startsWith('**')
                ? FontWeight.w700
                : FontWeight.w400,
            fontStyle: token.startsWith('**')
                ? FontStyle.normal
                : FontStyle.italic,
          ),
        ),
      );
      last = match.end;
    }
    if (last < raw.length) spans.add(TextSpan(text: raw.substring(last)));
    return spans;
  }
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
