import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:myapp/models/calendar_event_record.dart';
import 'package:myapp/models/planner_actions.dart';
import 'package:myapp/navigation/ahvi_back_navigation.dart';
import 'package:flutter/services.dart';
import 'package:myapp/boards.dart';
import 'package:myapp/profile.dart' as profile;
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_lens_sheet.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/ahvi_speech_service.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart'; // AhVi single chat implementation
import 'package:myapp/app_localizations.dart'; // 🆕 Localization
import 'package:myapp/daily_wear.dart';
import 'package:myapp/diet_fitness.dart';
import 'package:myapp/fitness_page.dart';
import 'package:myapp/diet_page.dart';
import 'package:myapp/skincare.dart';
import 'package:myapp/home_card_summary_provider.dart';
import 'package:myapp/widgets/home_routine_carousel.dart';
// skincare & medicine state now merged into HomeCardSummaryProvider
import 'package:myapp/medi_tracker.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// 🎯 AHVI HOME SCREEN - COMPLETE LOCALIZATION
/// ═══════════════════════════════════════════════════════════════════════════
///
/// This screen implements full localization for 8 languages:
/// English, Hindi, Telugu, Tamil, Kannada, Malayalam, Marathi, Bengali
///
/// 📋 MAIN LOCALIZATION KEYS:
/// ───────────────────────────────────────────────────────────────────────────
/// Navigation (Bottom Nav):
///   • nav_home, nav_chat, nav_wardrobe, nav_planner, nav_explore
///
/// Hero Card:
///   • home_hero_title → "Your Effortlessly Put-Together Day ✨"
///   • home_hero_badge_routine → "Routine"
///
/// Routine Items:
///   • routine_wear, routine_wear_desc
///   • routine_move, routine_move_desc
///   • routine_eat, routine_eat_desc
///   • routine_care, routine_care_desc
///
/// Greetings (Time-based):
///   • home_greeting_morning, home_greeting_afternoon, home_greeting_evening
///
/// ✅ HELPER METHODS FOR EASY ACCESS:
/// ───────────────────────────────────────────────────────────────────────────
///   _getTimeBasedGreeting() → Returns "Good morning"/"Good afternoon"/"Good evening"
///   _getPersonalizedGreeting(name) → Returns "Good morning, John"
///   _getNavLabels() → Returns List<String> of 5 nav item labels
///   _getHeroTitle() → Returns localized hero card title with emoji
///   _getRoutineItems() → Returns List of routine items with labels
///   _getCtaLabels() → Returns gym outfit & plan workout labels
///   _getAskPlaceholder() → Returns chat input placeholder
///
/// 🚀 QUICK USAGE EXAMPLES:
/// ───────────────────────────────────────────────────────────────────────────
///   // Direct key usage
///   Text(AppLocalizations.t(context, 'nav_home'))
///
///   // Using helper methods
///   Text(_getPersonalizedGreeting(_userName))
///   final labels = _getNavLabels() // All 5 nav labels
///
///   // Greeting in chat
///   greeting: _getTimeBasedGreeting()
///
/// ═══════════════════════════════════════════════════════════════════════════

// ─── Colors ──────────────────────────────────────────────

// 🆕 LOCALIZATION KEYS REFERENCE
// ─────────────────────────────────────────────────────────
// Navigation Keys (Bottom Nav):
//   'nav_home', 'nav_chat', 'nav_wardrobe', 'nav_planner', 'nav_explore'
// Hero Card Keys:
//   'home_hero_title' - "Your Effortlessly Put-Together Day ✨"
//   'home_hero_badge_routine' - "Routine"
// Routine Items:
//   'routine_wear', 'routine_wear_desc'
//   'routine_move', 'routine_move_desc'
//   'routine_eat', 'routine_eat_desc'
//   'routine_care', 'routine_care_desc'
// Greeting Keys:
//   'home_greeting_morning', 'home_greeting_afternoon', 'home_greeting_evening'
// CTA Keys:
//   'cta_gym_outfit', 'cta_plan_workout', 'cta_ask_ahvi'

// ═══════════════════════════════════════════════════════════════════════════
// 🆕 WEATHER SERVICE - Open Meteo API Integration
// ═══════════════════════════════════════════════════════════════════════════
class _WeatherService {
  static Future<Map<String, dynamic>> fetchWeather() async {
    final weather = await BackendService().getCurrentWeather();
    final raw = weather['raw'] as Map? ?? const {};
    return {
      'temperature': weather['temperature_c'] ?? weather['temperature'],
      'weather_code': raw['code'],
      'is_day': weather['time_of_day'] != 'night',
      'success': weather['status'] == 'available',
      'reason': weather['reason'],
    };
  }

  /// Map weather code to description - returns localization key
  static String getWeatherDescription(int code, {bool isDay = true}) {
    if (code == 0) return 'weather_clear';
    if (code == 1 || code == 2) return 'weather_partly_cloudy';
    if (code == 3) return 'weather_overcast';
    if ([45, 48].contains(code)) return 'weather_foggy';
    if ([51, 53, 55, 61, 63, 65, 80, 81, 82].contains(code))
      return 'weather_rainy';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return 'weather_snowy';
    if ([80, 81, 82].contains(code)) return 'weather_showers';
    if (code == 95 || code == 96 || code == 99) return 'weather_thunderstorm';
    return 'weather_partly_cloudy';
  }
}

// 🆕 Nav items are now built dynamically in _buildBottomNav() using localization
// _homeNavItems icons only — labels come from JSON
const _homeNavIcons = <IconData>[
  Icons.home_outlined,
  Icons.chat_bubble_outline_rounded,
  Icons.dry_cleaning_outlined,
  Icons.grid_view_rounded,
  Icons.explore_outlined,
];

// 🆕 Localization keys for navigation (used by _buildBottomNav)
const _homeNavKeys = <String>[
  'nav_home',
  'nav_chat',
  'nav_wardrobe',
  'nav_planner',
  'nav_explore',
];

// Keep original for fallback / non-localized usage
const _homeNavItems = <({IconData icon, String label})>[
  (icon: Icons.home_outlined, label: 'Home'),
  (icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
  (icon: Icons.dry_cleaning_outlined, label: 'Wardrobe'),
  (icon: Icons.grid_view_rounded, label: 'Planner'),
  (icon: Icons.explore_outlined, label: 'Explore'),
];

/// 🆕 SINGLE SOURCE OF TRUTH for the screen's responsive horizontal gutter.
///
/// Previously this breakpoint math was duplicated: once inline inside the
/// body's LayoutBuilder (drives padding for the greeting/cards/routine
/// sections), and the fixed AHVI logo bar never used it at all — it was
/// rendered via a full-bleed `Positioned(left: 0, right: 0)` while
/// `AhviHeader` applied its own hardcoded 20px inset. On small phones the
/// body gutter can be as low as 8px while the header stayed at 20px, and on
/// tablets the body content is centered (gutter = (screenW-620)/2, often
/// >20px) while the header still sat at a flat 20 — so the logo never lined
/// up with the greeting/date text beneath it except by coincidence at
/// exactly the 480–640dp bucket. Both call sites now read from here, so the
/// logo is guaranteed to share the same left edge as everything below it on
/// every screen size.
({double horizontalPad, double maxContentWidth}) _responsiveGutter(
  double screenW,
) {
  if (screenW < 340) {
    // Very small phones (iPhone SE) - 280-340dp
    return (horizontalPad: 8.0, maxContentWidth: screenW - 16.0);
  } else if (screenW < 360) {
    // Small phones (Galaxy A12) - 340-360dp
    return (horizontalPad: 10.0, maxContentWidth: screenW - 20.0);
  } else if (screenW < 480) {
    // Small/Standard phones (iPhone 11, Pixel 5) - 360-480dp
    return (horizontalPad: 16.0, maxContentWidth: screenW - 32.0);
  } else if (screenW < 640) {
    // Large phones (iPhone 14 Pro Max, Pixel 7 Pro) - 480-640dp
    return (horizontalPad: 20.0, maxContentWidth: screenW - 40.0);
  } else {
    // Tablets and large devices (iPad, foldables) - 640+dp — content is
    // centered at a fixed max width, so the gutter grows to fill the rest.
    const maxContentWidth = 620.0;
    return (
      horizontalPad: (screenW - maxContentWidth) / 2,
      maxContentWidth: maxContentWidth,
    );
  }
}

Color _accent(AppThemeTokens t) => t.accent.primary;
Color _accentSecondary(AppThemeTokens t) => t.accent.secondary;
Color _accentTertiary(AppThemeTokens t) => t.accent.tertiary;

// ─── Dynamic Recommendation Engine ──────────────────────────────────────────

/// Dynamic content for a home card (title, subtitle, CTA, icon, prompt).
class _CardContent {
  const _CardContent({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.icon,
    required this.prompt,
  });

  final String title;
  final String subtitle;
  final String cta;
  final IconData icon;
  final String prompt;
}

// ── Weather signal ────────────────────────────────────────────────────────────

enum _WeatherCondition { clear, cloudy, rainy, cold, hot, unknown }

class _WeatherSignal {
  const _WeatherSignal({
    this.tempCelsius,
    this.condition = _WeatherCondition.unknown,
    this.description = '',
  });

  final double? tempCelsius;
  final _WeatherCondition condition;
  final String description; // e.g. "partly cloudy", "heavy rain"

  bool get isCold => tempCelsius != null && tempCelsius! < 18;
  bool get isHot => tempCelsius != null && tempCelsius! > 32;
  bool get isRainy => condition == _WeatherCondition.rainy;
  bool get isClear => condition == _WeatherCondition.clear;

  String get tempLabel =>
      tempCelsius != null ? '${tempCelsius!.round()}°C' : '';
}

// ── Calendar signal ───────────────────────────────────────────────────────────

enum _EventType { meeting, occasion, workout, travel, dinner, other }

class _CalendarEvent {
  const _CalendarEvent({
    required this.title,
    required this.startsAt,
    this.type = _EventType.other,
  });

  final String title;
  final DateTime startsAt;
  final _EventType type;

  /// Hours until this event from now.
  int get hoursUntil =>
      startsAt.difference(DateTime.now()).inHours.clamp(0, 999);

  bool get isSoon => hoursUntil <= 4;
  bool get isToday {
    final now = DateTime.now();
    return startsAt.year == now.year &&
        startsAt.month == now.month &&
        startsAt.day == now.day;
  }
}

// ── Wardrobe signal ───────────────────────────────────────────────────────────

class _WardrobeSignal {
  const _WardrobeSignal({
    this.lastWornItemName = '',
    this.daysSinceLastWorn = 0,
    this.totalItems = 0,
    this.unwornItems = 0,
    this.favoriteStyle = '',
  });

  final String lastWornItemName;
  final int daysSinceLastWorn;
  final int totalItems;
  final int unwornItems;
  final String favoriteStyle; // e.g. "minimal", "streetwear"

  bool get hasUnwornItems => unwornItems > 0;
  bool get wardrobeNeedsAttention => daysSinceLastWorn >= 2;
}

// ── Fitness signal ────────────────────────────────────────────────────────────

class _FitnessSignal {
  const _FitnessSignal({
    this.workoutStreakDays = 0,
    this.calorieGoalMet = false,
    this.stepGoalMet = false,
    this.nextWorkoutLabel = '',
    this.waterGlassesToday = 0,
  });

  final int workoutStreakDays;
  final bool calorieGoalMet;
  final bool stepGoalMet;
  final String nextWorkoutLabel; // e.g. "Leg Day", "Cardio"
  final int waterGlassesToday;

  bool get hasActiveStreak => workoutStreakDays >= 2;
  bool get mealPlanNeeded => !calorieGoalMet;
}

// ── Unified context ───────────────────────────────────────────────────────────

/// All context signals used to score and rank suggestions.
class _RecommendationContext {
  const _RecommendationContext({
    required this.hour,
    required this.weekday,
    required this.userName,
    required this.recentIntents,
    this.weather = const _WeatherSignal(),
    this.upcomingEvents = const [],
    this.wardrobe = const _WardrobeSignal(),
    this.fitness = const _FitnessSignal(),
  });

  final int hour;
  final int weekday;
  final String userName;
  final List<String> recentIntents;
  final _WeatherSignal weather;
  final List<_CalendarEvent> upcomingEvents;
  final _WardrobeSignal wardrobe;
  final _FitnessSignal fitness;

  // ── Time helpers ─────────────────────────────────────────────────────────
  bool get isMorning => hour >= 5 && hour < 12;
  bool get isAfternoon => hour >= 12 && hour < 17;
  bool get isEvening => hour >= 17 && hour < 21;
  bool get isNight => hour >= 21 || hour < 5;

  bool get isWeekday => weekday >= 1 && weekday <= 5;
  bool get isWeekend => weekday == 6 || weekday == 7;

  bool get isMondayMorning => weekday == 1 && isMorning;
  bool get isFridayEvening => weekday == 5 && isEvening;
  bool get isSunday => weekday == 7;

  // ── Calendar helpers ──────────────────────────────────────────────────────
  _CalendarEvent? get nextMeeting => upcomingEvents
      .where((e) => e.type == _EventType.meeting && e.isToday)
      .cast<_CalendarEvent?>()
      .firstOrNull;

  _CalendarEvent? get nextOccasion => upcomingEvents
      .where((e) => e.type == _EventType.occasion && e.isToday)
      .cast<_CalendarEvent?>()
      .firstOrNull;

  bool get hasSoonMeeting => nextMeeting?.isSoon ?? false;
  bool get hasSoonOccasion => nextOccasion?.isSoon ?? false;
}

// ── String helper ─────────────────────────────────────────────────────────────
extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// 🆕 Prepare chips keys for localization
const _prepareChipKeys = [
  ('prepare_carry_on', '✈️ Carry-on Packing'),
  ('prepare_birthday', '🎂 Birthday Party Planning'),
  ('prepare_camping', '🏕️ Camping Trip'),
  ('prepare_wedding', '💍 Wedding Planning'),
  ('prepare_workout', '🏋️ Gym Workout Routine'),
  ('prepare_meal_prep', '🍳 Weekly Meal Prep'),
  ('prepare_dev_project', '💻 New Coding Project Setup'),
  ('prepare_moving', '🏠 House Moving Checklist'),
  ('prepare_study', '🎓 Exam Study Plan'),
  ('prepare_gardening', '🌿 Garden Planting'),
];
const _prepareChips = [
  ('✈️ Carry-on', '✈️ Carry-on Packing'),
  ('🎂 Birthday Party', '🎂 Birthday Party Planning'),
  ('🏕️ Camping', '🏕️ Camping Trip'),
  ('💍 Wedding', '💍 Wedding Planning'),
  ('🏋️ Workout', '🏋️ Gym Workout Routine'),
  ('🍳 Meal Prep', '🍳 Weekly Meal Prep'),
  ('💻 Dev Project', '💻 New Coding Project Setup'),
  ('🏠 Moving House', '🏠 House Moving Checklist'),
  ('🎓 Study Plan', '🎓 Exam Study Plan'),
  ('🌿 Gardening', '🌿 Garden Planting'),
];

typedef _ClockState = ({String greeting, String date});

class Screen4 extends StatefulWidget {
  const Screen4({
    super.key,
    this.onShellNavTap,
    this.loadContextSignals = true,
  });

  final ValueChanged<int>? onShellNavTap;
  final bool loadContextSignals;

  @override
  State<Screen4> createState() => _Screen4State();
}

class _Screen4State extends State<Screen4>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  AppThemeTokens get _t => context.themeTokens;

  // 🔧 FIX: Palette switch అయినప్పుడు full rebuild trigger చేయడానికి
  // accent color track చేస్తాం — change అయితే setState() చేస్తాం
  Color? _cachedAccent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAccent = context.themeTokens.accent.primary;
    if (_cachedAccent != null && _cachedAccent != newAccent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _cachedAccent = newAccent;

    if (!widget.loadContextSignals) return;

    // ✅ FIX: Defer heavy operations until AFTER frame completes
    // This prevents blocking the back-nav animation (Wardrobe → Home)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Add delay to ensure back-nav animation fully completes (~500ms)
        // before loading images
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            // Re-sync fitness signal whenever HomeCardSummaryProvider notifies
            _syncFitnessSignal();
            // 🔧 FIX: Wear card was static — _fetchWardrobeSignal() was only
            // ever called once in initState, so picking/wearing an outfit in
            // DailyWearScreen never refreshed Home's copy until app restart.
            // Now it re-syncs every time Home's dependencies change (e.g.
            // navigating back from DailyWearScreen), matching fitness signal
            // behavior so the Wear bubble + card status update immediately.
            _fetchWardrobeSignal();
            _preloadHomeImages();
            // NOTE: home-summary refresh is intentionally NOT scheduled here.
            // The single guarded initial fetch runs once in initState; resume
            // and explicit refreshes cover the rest. Firing an unguarded
            // delayed refresh on every dependency change is redundant with the
            // provider's own user+date cache guard.
          }
        });
      }
    });
  }

  Color get _bgPrimary => _t.backgroundPrimary;
  Color get _bgSecondary => _t.backgroundSecondary;
  Color get _surface => _t.phoneShellInner;
  Color get _textHeading => _t.textPrimary;
  Color get _textSub => _t.mutedText;
  Color get _textMuted => _t.mutedText;
  Color get _accent => _t.accent.primary;
  Color get _accentSecondary => _t.accent.secondary;
  Color get _accentTertiary => _t.accent.tertiary;
  Color get _panel => _t.panel;
  Color get _card => _t.card;
  Color get _phoneShell => _t.phoneShell;
  Color get _tileText => _t.tileText;
  Color get _shadowStrong => _bgPrimary.withOpacity(0.35);
  Color get _shadowMedium => _bgPrimary.withOpacity(0.20);
  Color get _shadowLight => _bgPrimary.withOpacity(0.12);
  Color get _transparent => _bgPrimary.withOpacity(0.0);
  Color get _onAccent => Theme.of(context).colorScheme.onPrimary;
  Color get _border => _t.cardBorder;
  LinearGradient get _accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_accent, _accentTertiary],
  );
  LinearGradient get _accentGradient2 => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_accent, _accentSecondary],
  );

  late AnimationController _aurora1Ctrl;
  late AnimationController _aurora2Ctrl;
  late AnimationController _aurora3Ctrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _pulseCtrl;
  int _activeNavIdx = 0;

  late AnimationController _floatBadgeCtrl;
  late AnimationController _breatheCtrl;
  late List<AnimationController> _heartPopCtrls;
  final List<bool> _likedState = [false, false, true, false];

  // ── Plus menu ─────────────────────────────────────────────────────────────
  // (Lens sheet manages its own state — no local controller needed)
  late AnimationController _plusMenuCtrl; // kept to avoid dispose() errors

  bool _toastVisible = false;
  Timer? _toastTimer;

  bool _seeAllOpen = false;
  late AnimationController _seeAllCtrl;

  // ── Notifications ──────────────────────────────────────────────────────────
  bool _notifPanelOpen = false;
  // 🆕 FIX: Initialize to 0 instead of hardcoded 3
  // Unread count is calculated dynamically from notification list
  int _unreadNotifCount = 0;

  // 🆕 Unread notifications list — synced with backend
  List<_NotifData> _notificationsList = [];

  late List<AnimationController> _navRiseCtrls;

  final ValueNotifier<_ClockState> _clockState = ValueNotifier<_ClockState>((
    greeting: 'greeting_morning',
    date: '',
  ));
  Timer? _clockTimer;

  // 🆕 Increments every time a signal changes — drives ValueListenableBuilder
  // on the Style & Prep cards so they re-render without setState rebuilding
  // the entire tree.
  final ValueNotifier<int> _cardContextVersion = ValueNotifier<int>(0);
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ValueNotifier<double> _keyboardHeight = ValueNotifier<double>(0.0);

  // ── Voice ──────────────────────────────────────────────────────────────────
  final AhviSpeechService _speech = AhviSpeechService.instance;
  bool _isListening = false;
  bool _speechAvailable = false;
  final Map<String, List<List<bool>>> _prepareExactChecksByTitle = {};
  final Map<String, List<List<String>>> _prepareExactItemsByTitle = {};
  final Map<String, List<TextEditingController>>
  _prepareExactAddControllersByTitle = {};
  // ── Dynamic recommendation engine ─────────────────────────────────────────
  // Tracks the last N intents the user triggered (most recent first).
  final List<String> _recentIntents = [];

  // ── Live context signals ───────────────────────────────────────────────────
  _WeatherSignal _weatherSignal = const _WeatherSignal();
  List<_CalendarEvent> _calendarEvents = [];
  _WardrobeSignal _wardrobeSignal = const _WardrobeSignal();
  _FitnessSignal _fitnessSignal = const _FitnessSignal();

  /// Records an intent tap for the recommendation engine.
  void _recordIntent(String intent) {
    _recentIntents.remove(intent);
    _recentIntents.insert(0, intent);
    if (_recentIntents.length > 5) _recentIntents.removeLast();
    _invalidateSuggestionCache();
  }

  void _invalidateSuggestionCache() {
    // Notify card widgets to re-evaluate their dynamic content.
    _cardContextVersion.value += 1;
  }

  /// Builds the current context snapshot for the recommendation engine.
  _RecommendationContext get _recommendationCtx {
    final now = DateTime.now();
    return _RecommendationContext(
      hour: now.hour,
      weekday: now.weekday,
      userName: _userName,
      recentIntents: List.unmodifiable(_recentIntents),
      weather: _weatherSignal,
      upcomingEvents: _calendarEvents,
      wardrobe: _wardrobeSignal,
      fitness: _fitnessSignal,
    );
  }

  // ── Signal fetchers ────────────────────────────────────────────────────────

  /// Fetches weather for the user's device locale via open-meteo (no API key).
  /// Retries once on transient network failure so a slow connection right
  /// at app-launch doesn't leave the chip stuck on "--°" for the session.
  Future<void> _fetchWeatherSignal({bool isRetryAttempt = false}) async {
    // Hyderabad default (matches app's primary market); swap for device GPS
    // via geolocator if/when that package is added to the project.
    const lat = 17.385;
    const lon = 78.486;
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,weather_code'
      '&timezone=auto',
    );

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = await res.transform(const Utf8Decoder()).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toDouble();
          // API migrated `weathercode` → `weather_code`; accept either key
          // so older/newer response shapes both work.
          final code =
              (current['weather_code'] as num?)?.toInt() ??
              (current['weathercode'] as num?)?.toInt() ??
              0;
          final condition = _wmoCodeToCondition(code);
          final desc = _wmoCodeToDescription(code);
          if (mounted) {
            setState(() {
              _weatherSignal = _WeatherSignal(
                tempCelsius: temp,
                condition: condition,
                description: desc,
              );
              _invalidateSuggestionCache();
            });
          }
        }
      } else {
        debugPrint('🌦️ _fetchWeatherSignal HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('🌦️ _fetchWeatherSignal error: $e');
      // One quiet retry — covers the common case of the very first request
      // racing the device's network interface coming up after cold start.
      if (!isRetryAttempt) {
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) await _fetchWeatherSignal(isRetryAttempt: true);
      }
    } finally {
      client?.close();
    }
  }

  static _WeatherCondition _wmoCodeToCondition(int code) {
    if (code == 0) return _WeatherCondition.clear;
    if (code <= 3) return _WeatherCondition.cloudy;
    if (code >= 51 && code <= 82) return _WeatherCondition.rainy;
    if (code >= 85)
      return _WeatherCondition.rainy; // snow/sleet → treat as rainy
    return _WeatherCondition.unknown;
  }

  static String _wmoCodeToDescription(int code) {
    if (code == 0) return 'clear sky';
    if (code == 1) return 'mainly clear';
    if (code == 2) return 'partly cloudy';
    if (code == 3) return 'overcast';
    if (code >= 51 && code <= 55) return 'drizzle';
    if (code >= 61 && code <= 65) return 'rain';
    if (code >= 71 && code <= 75) return 'snow';
    if (code >= 80 && code <= 82) return 'rain showers';
    if (code >= 95) return 'thunderstorm';
    return '';
  }

  // ── Calendar ───────────────────────────────────────────────────────────────

  /// Fetches today's calendar events from BackendService and maps them to
  /// [_CalendarEvent] objects the recommendation engine can score.
  Future<void> _fetchCalendarSignal() async {
    try {
      final backend = Provider.of<BackendService>(context, listen: false);
      final raw = await backend
          .getTodayCalendarEvents(surface: CalendarListSurface.homeToday)
          .timeout(const Duration(seconds: 8), onTimeout: () => []);

      final events = <_CalendarEvent>[];
      for (final event in raw) {
        final record = CalendarEventRecord.tryParse(
          event,
          onSkipped: (eventId, field) => debugPrint(
            'AHVI_CALENDAR_PARSE_SKIPPED event_id=$eventId field=$field',
          ),
        );
        if (record == null) continue;
        // Map backend `type` field to our internal enum.
        final rawType = record.type.toLowerCase();
        final _EventType type;
        if (rawType.contains('meet') ||
            rawType.contains('work') ||
            rawType.contains('call')) {
          type = _EventType.meeting;
        } else if (rawType.contains('travel') ||
            rawType.contains('flight') ||
            rawType.contains('trip')) {
          type = _EventType.travel;
        } else if (rawType.contains('dinner') ||
            rawType.contains('lunch') ||
            rawType.contains('brunch')) {
          type = _EventType.dinner;
        } else if (rawType.contains('workout') ||
            rawType.contains('gym') ||
            rawType.contains('fitness')) {
          type = _EventType.workout;
        } else if (rawType.contains('party') ||
            rawType.contains('wedding') ||
            rawType.contains('occasion') ||
            rawType.contains('event') ||
            rawType.contains('celebrat')) {
          type = _EventType.occasion;
        } else {
          type = _EventType.other;
        }

        events.add(
          _CalendarEvent(
            title: record.title,
            startsAt: record.startTime,
            type: type,
          ),
        );
      }

      // Sort chronologically so nextMeeting / nextOccasion pick the soonest.
      events.sort((a, b) => a.startsAt.compareTo(b.startsAt));

      if (mounted) {
        setState(() {
          _calendarEvents = events;
          _invalidateSuggestionCache();
        });
      }
    } catch (e) {
      debugPrint('📅 Calendar fetch error: $e');
      // Leave _calendarEvents unchanged — app continues normally
    }
  }

  void _onCalendarRefresh() {
    if (mounted) _fetchCalendarSignal();
  }

  // ── Wardrobe ───────────────────────────────────────────────────────────────

  /// Fetches wardrobe items from AppwriteService and distils them into a
  /// lightweight [_WardrobeSignal] for the recommendation engine.
  Future<void> _fetchWardrobeSignal() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);

      // getWardrobeItems() uses an in-memory cache so this is cheap after
      // the first load.
      final items = await appwrite.getWardrobeItems();

      if (items.isEmpty) return;

      final totalItems = items.length;

      // Items that have never been worn: no 'wornAt', 'last_worn', or 'worn_count'.
      final unwornItems = items.where((item) {
        final wornAt = item['wornAt'] ?? item['last_worn'] ?? item['worn_at'];
        final wornCount = item['worn_count'] ?? item['wornCount'] ?? 0;
        return wornAt == null && (wornCount == 0);
      }).length;

      // Most recently worn item.
      String lastWornItemName = '';
      int daysSinceLastWorn = 0;
      final wornItems = items.where((item) {
        return item['wornAt'] != null ||
            item['last_worn'] != null ||
            item['worn_at'] != null;
      }).toList();

      if (wornItems.isNotEmpty) {
        wornItems.sort((a, b) {
          final aDate = _parseDate(
            a['wornAt'] ?? a['last_worn'] ?? a['worn_at'],
          );
          final bDate = _parseDate(
            b['wornAt'] ?? b['last_worn'] ?? b['worn_at'],
          );
          return bDate.compareTo(aDate); // most recent first
        });
        lastWornItemName = wornItems.first['name']?.toString() ?? '';
        final lastDate = _parseDate(
          wornItems.first['wornAt'] ??
              wornItems.first['last_worn'] ??
              wornItems.first['worn_at'],
        );
        daysSinceLastWorn = DateTime.now().difference(lastDate).inDays;
      } else {
        // Nothing worn yet — treat all as fresh.
        daysSinceLastWorn = 0;
      }

      // Dominant style tag — prefer user profile stylePreferences, then
      // derive from item occasions/categories.
      String favoriteStyle = '';
      final profile = appwrite.cachedUserProfileData;
      if (profile != null) {
        final prefs = profile['stylePreferences'];
        if (prefs is List && prefs.isNotEmpty) {
          favoriteStyle = prefs.first.toString().toLowerCase();
        }
      }
      if (favoriteStyle.isEmpty) {
        // Derive from most common occasion tag in wardrobe.
        final tagCounts = <String, int>{};
        for (final item in items) {
          final occ = item['occasions'];
          if (occ is List) {
            for (final o in occ) {
              final tag = o.toString().toLowerCase();
              tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
            }
          } else if (occ is String && occ.isNotEmpty) {
            tagCounts[occ.toLowerCase()] =
                (tagCounts[occ.toLowerCase()] ?? 0) + 1;
          }
        }
        if (tagCounts.isNotEmpty) {
          favoriteStyle =
              (tagCounts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .first
                  .key;
        }
      }

      if (mounted) {
        setState(() {
          _wardrobeSignal = _WardrobeSignal(
            totalItems: totalItems,
            unwornItems: unwornItems,
            lastWornItemName: lastWornItemName,
            daysSinceLastWorn: daysSinceLastWorn,
            favoriteStyle: favoriteStyle,
          );
          _invalidateSuggestionCache();
        });
      }
    } catch (e) {
      debugPrint('👗 _fetchWardrobeSignal error: $e');
    }
  }

  /// Parses a date from a dynamic value (String ISO-8601 or DateTime).
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime(2000);
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime(2000);
    }
  }

  // ── Fitness ────────────────────────────────────────────────────────────────

  /// Syncs fitness signal from two sources:
  ///   1. BackendService.getTodayWorkout() — real workout data.
  ///   2. HomeCardSummaryProvider — calorie/move summary strings (fast fallback).
  void _syncFitnessSignal() {
    // Kick off the async backend fetch in parallel; update state twice:
    // once immediately from the provider text, once when the network responds.
    _syncFitnessFromProvider();
    _syncFitnessFromBackend(); // fire-and-forget
  }

  /// Fast path — parses HomeCardSummaryProvider strings for immediate display.
  void _syncFitnessFromProvider() {
    try {
      final summary = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      );
      final moveText = summary.move.toLowerCase();
      final eatText = summary.eat.toLowerCase();

      // Streak: "3-day streak", "Day 5", "5 days"
      int streak = 0;
      final streakMatch = RegExp(r'(\d+)[- ]?day').firstMatch(moveText);
      if (streakMatch != null)
        streak = int.tryParse(streakMatch.group(1) ?? '') ?? 0;

      // Calorie goal: "1,840 / 2,000 kcal" or "1840/2000"
      bool calorieGoalMet = false;
      final calMatch = RegExp(
        r'(\d[\d,]+)\s*/\s*(\d[\d,]+)',
      ).firstMatch(eatText);
      if (calMatch != null) {
        final consumed =
            int.tryParse(calMatch.group(1)!.replaceAll(',', '')) ?? 0;
        final goal = int.tryParse(calMatch.group(2)!.replaceAll(',', '')) ?? 1;
        calorieGoalMet = consumed >= goal;
      }

      // Next workout label from move summary
      String nextWorkout = _extractWorkoutLabel(moveText);

      if (mounted) {
        setState(() {
          _fitnessSignal = _FitnessSignal(
            workoutStreakDays: streak,
            calorieGoalMet: calorieGoalMet,
            nextWorkoutLabel: nextWorkout,
            // waterGlassesToday unchanged until backend responds
            waterGlassesToday: _fitnessSignal.waterGlassesToday,
          );
          _invalidateSuggestionCache();
        });
      }
    } catch (_) {}
  }

  /// ✅ FIX: Preload home screen images asynchronously AFTER back-nav animation
  /// This prevents image loading from blocking the main thread during navigation
  void _preloadHomeImages() {
    try {
      final imagesToPreload = [
        // Style card outfit photos — ONLY the 2 gendered variants.
        // No generic/neutral fallback image anymore: whichever one
        // _userGender resolves to ('women' or 'men') is already warm
        // in the image cache by the time the card first paints, and if
        // gender can't be resolved yet, _userGender's own default
        // ('women') is used as the fallback — not a 3rd image.
        'assets/images/style_card_women.jpeg',
        'assets/images/style_card_men.jpeg',
        // Prep & Plan decorative backdrop — ONLY the 2 gendered variants,
        // same pattern as the Style card above (no generic/neutral 3rd asset).
        'assets/images/plan_card_women.jpg',
        'assets/images/plan_card_men.jpg',
      ];

      for (final asset in imagesToPreload) {
        precacheImage(AssetImage(asset), context).catchError((_) => null);
      }
    } catch (_) {}
  }

  /// Triggers a home-summary refresh via the provider. The provider's own
  /// single-flight and user+date cache guard prevent duplicate requests.
  void _refreshHomeSummary() {
    try {
      Provider.of<HomeCardSummaryProvider>(context, listen: false).refresh();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // On resume (e.g. returning from background on a new day), refresh the
    // home summary. The provider's cache key (user+date) ensures a fetch only
    // when the date has actually changed since the last successful load.
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshHomeSummary();
    }
  }

  /// Slow path — fetches today's workout from BackendService and updates the
  /// signal with richer data (streak, type, water).
  Future<void> _syncFitnessFromBackend() async {
    try {
      final backend = Provider.of<BackendService>(context, listen: false);
      final data = await backend.getTodayWorkout();

      if (data.isEmpty) return;

      // Backend response shape (from the API):
      //   { workout: { id, type, name, duration, streak, status, ... },
      //     nutrition: { calories_consumed, calories_goal, water_glasses, ... } }
      final workout = data['workout'] as Map<String, dynamic>? ?? {};
      final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};

      // Streak
      final streak =
          (workout['streak'] as num?)?.toInt() ??
          (data['streak'] as num?)?.toInt() ??
          _fitnessSignal.workoutStreakDays;

      // Workout label
      final workoutName =
          workout['name']?.toString() ??
          workout['type']?.toString() ??
          data['workout_type']?.toString() ??
          '';
      final nextWorkout = workoutName.isNotEmpty
          ? _extractWorkoutLabel(workoutName.toLowerCase())
          : _fitnessSignal.nextWorkoutLabel;

      // Calorie goal
      final consumed =
          (nutrition['calories_consumed'] as num?)?.toInt() ??
          (data['calories_consumed'] as num?)?.toInt() ??
          0;
      final goal =
          (nutrition['calories_goal'] as num?)?.toInt() ??
          (data['calories_goal'] as num?)?.toInt() ??
          0;
      final calorieGoalMet = goal > 0
          ? consumed >= goal
          : _fitnessSignal.calorieGoalMet;

      // Water glasses
      final water =
          (nutrition['water_glasses'] as num?)?.toInt() ??
          (data['water_glasses'] as num?)?.toInt() ??
          _fitnessSignal.waterGlassesToday;

      // Step goal
      final stepsDone = (data['steps'] as num?)?.toInt() ?? 0;
      final stepsGoal = (data['steps_goal'] as num?)?.toInt() ?? 8000;
      final stepGoalMet = stepsGoal > 0 && stepsDone >= stepsGoal;

      if (mounted) {
        setState(() {
          _fitnessSignal = _FitnessSignal(
            workoutStreakDays: streak,
            calorieGoalMet: calorieGoalMet,
            stepGoalMet: stepGoalMet,
            nextWorkoutLabel: nextWorkout,
            waterGlassesToday: water,
          );
          _invalidateSuggestionCache();
        });
      }
    } catch (e) {
      debugPrint('🏃 _syncFitnessFromBackend error: $e');
    }
  }

  /// 🆕 Fetch weather from Open Meteo API (improved version)
  Future<void> _fetchWeatherSignalImproved() async {
    try {
      final weather = await _WeatherService.fetchWeather();
      final temp = (weather['temperature'] as num?)?.toDouble() ?? 28.0;
      final rawIsDay = weather['is_day'];
      final isDay = rawIsDay is bool
          ? rawIsDay
          : (rawIsDay == null ? true : rawIsDay == 1);
      final description = _WeatherService.getWeatherDescription(
        weather['weather_code'] as int? ?? 0,
        isDay: isDay,
      );

      if (mounted) {
        setState(() {
          _weatherSignal = _WeatherSignal(
            tempCelsius: temp,
            description: description.toLowerCase(),
          );
          _invalidateSuggestionCache();
        });
      }
    } catch (e) {
      debugPrint('🌦️ Weather fetch error: $e');
      if (mounted) {
        setState(() {
          _weatherSignal = _WeatherSignal(
            tempCelsius: 28.0,
            description: 'partly cloudy',
          );
        });
      }
    }
  }

  /// Extracts a workout localization key from a free-text string.
  /// Returns key that should be localized with AppLocalizations.t(context, key)
  static String _extractWorkoutLabel(String text) {
    if (text.contains('leg')) return 'workout_leg_day';
    if (text.contains('chest')) return 'workout_chest_day';
    if (text.contains('back')) return 'workout_back_day';
    if (text.contains('arm') ||
        text.contains('bicep') ||
        text.contains('tricep'))
      return 'workout_arm_day';
    if (text.contains('cardio') || text.contains('run') || text.contains('jog'))
      return 'workout_cardio';
    if (text.contains('yoga')) return 'workout_yoga';
    if (text.contains('hiit')) return 'workout_hiit';
    if (text.contains('full body') || text.contains('fullbody'))
      return 'workout_full_body';
    if (text.contains('stretch') || text.contains('mobility'))
      return 'workout_mobility';
    if (text.contains('rest')) return '';
    return '';
  }

  /// 🆕 Get workout label from fitness signal or default
  String get _workoutLabel {
    final fit = _fitnessSignal;
    return fit.nextWorkoutLabel.isNotEmpty
        ? fit.nextWorkoutLabel
        : AppLocalizations.t(context, 'chip_mobility_default');
  }

  /// Public method called by external code to inject a calendar event
  /// (e.g. from a Calendar MCP response or onboarding flow).
  void injectCalendarEvent(_CalendarEvent event) {
    if (!mounted) return;
    setState(() {
      _calendarEvents.removeWhere((e) => e.title == event.title);
      _calendarEvents.add(event);
      _calendarEvents.sort((a, b) => a.startsAt.compareTo(b.startsAt));
      _invalidateSuggestionCache();
    });
  }

  final Map<String, List<bool>> _prepareExactOutfitSavedByTitle = {};
  final Map<String, bool> _prepareExactSavedByTitle = {};
  final Map<String, String> _boardIdByLabel = const {
    '🎉 Party Looks': 'party_looks',
    '💍 Occasion': 'occasion',
    '💼 Office Fit': 'office_fit',
    '✈️ Vacation': 'vacation',
    '✨ Everything Else': 'everything_else',
  };

  _OverlayState _overlayState = _OverlayState.idle;
  String? _activeIntent;
  String _chatPlaceholderKey = 'ask_me'; // ✅ JSON key: "ask_me"
  String get _chatPlaceholder =>
      AppLocalizations.t(context, _chatPlaceholderKey);
  bool _homeCollapsed = false;
  late AnimationController _homeCollapseCtrl;
  late AnimationController _overlayFadeCtrl;
  late AnimationController _thinkingCtrl;
  late AnimationController _tagsRevealCtrl;
  List<String> _overlaySuggestions = [];
  String _overlayBrandSub = '';

  // 🚀 STATE FIX: We now use a list to stack messages + tracking variables
  final List<_ResponseData> _responses = [];
  final List<Map<String, String>> _chatHistory = [];
  String _runningMemory = "";
  final ScrollController _overlayScrollCtrl = ScrollController();

  // Home five-card daily-summary carousel. The PageController lives inside
  // HomeRoutineCarousel (self-managed lifecycle), so nothing to hold here.

  List<String> _responseTags = [];
  bool _tagsRevealed = false;

  String _userName = '';
  Uint8List? _avatarBytes;
  // 🆕 Onboarding-driven gender ('women' | 'men') — selects which outfit
  // photo shows on the Style card. Defaults to 'women' until profile loads.
  String _userGender = 'women';

  Future<void> _savePrepareExactToBoard({
    required String boardId,
    required String title,
    required List<
      ({String name, String emoji, Color color, List<String> items})
    >
    sections,
    required List<List<String>> itemsState,
    required List<List<bool>> checksState,
    required List<bool> outfitSaved,
  }) async {
    final sectionPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < sections.length; i++) {
      sectionPayload.add({
        'name': sections[i].name,
        'emoji': sections[i].emoji,
        'color': sections[i].color.value,
        'items': List<String>.from(itemsState[i]),
        'checked': List<bool>.from(checksState[i]),
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🆕 LOCALIZATION HELPERS - Get translated strings easily
  // ──────────────────────────────────────────────────────────────────────────

  /// Get greeting based on current time of day
  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return AppLocalizations.t(context, 'home_greeting_morning');
    } else if (hour < 17) {
      return AppLocalizations.t(context, 'home_greeting_afternoon');
    } else {
      return AppLocalizations.t(context, 'home_greeting_evening');
    }
  }

  /// Get personalized greeting with user name
  String _getPersonalizedGreeting(String userName) {
    final greeting = _getTimeBasedGreeting();
    return '$greeting, $userName';
  }

  /// Get all navigation labels localized
  List<String> _getNavLabels() {
    return _homeNavKeys.map((key) => AppLocalizations.t(context, key)).toList();
  }

  /// Get hero title localized
  String _getHeroTitle() {
    return AppLocalizations.t(context, 'home_hero_title');
  }

  /// Get routine items with localized labels
  List<({String label, String desc})> _getRoutineItems() {
    return [
      (
        label: AppLocalizations.t(context, 'routine_wear'),
        desc: AppLocalizations.t(context, 'routine_wear_desc'),
      ),
      (
        label: AppLocalizations.t(context, 'routine_move'),
        desc: AppLocalizations.t(context, 'routine_move_desc'),
      ),
      (
        label: AppLocalizations.t(context, 'routine_eat'),
        desc: AppLocalizations.t(context, 'routine_eat_desc'),
      ),
      (
        label: AppLocalizations.t(context, 'routine_care'),
        desc: AppLocalizations.t(context, 'routine_care_desc'),
      ),
    ];
  }

  /// Get CTA button labels
  ({String gymOutfit, String planWorkout}) _getCtaLabels() {
    return (
      gymOutfit: AppLocalizations.t(context, 'cta_gym_outfit'),
      planWorkout: AppLocalizations.t(context, 'cta_plan_workout'),
    );
  }

  /// Get input field placeholder
  String _getAskPlaceholder() {
    return AppLocalizations.t(context, 'cta_ask_ahvi');
  }

  @override
  void initState() {
    super.initState();
    CalendarRefreshSignal.generation.addListener(_onCalendarRefresh);
    _initSpeech();
    // Keyboard height track చేయడానికి FocusNode listener
    _chatFocusNode.addListener(_onChatFocusChange);
    WidgetsBinding.instance.addObserver(this);

    _aurora1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    _aurora2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    _aurora3Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat(reverse: true);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _floatBadgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _heartPopCtrls = List.generate(
      4,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      ),
    );

    _seeAllCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _plusMenuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _navRiseCtrls = List.generate(
      5,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
        value: i == 0 ? 1.0 : 0.0,
      ),
    );

    _homeCollapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _overlayFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _thinkingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _tagsRevealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // 🔧 FIX: Defer _updateClock() to after frame completes
    // This ensures the localization inherited widget is fully initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateClock();
        _clockTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _updateClock(),
        );
      }
    });

    if (widget.loadContextSignals) _fetchUserProfile();

    // ── 🌦️📅👗🏃 Kick off all context signal fetches ─────────────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.loadContextSignals) return;
      _fetchWeatherSignalImproved(); // 🆕 Use improved weather fetch
      _fetchCalendarSignal();
      _fetchWardrobeSignal();
      _syncFitnessSignal();
      // Single guarded initial home-summary fetch. initState runs once per
      // mount and the provider's user+date cache guard dedupes; resume
      // (didChangeAppLifecycleState) and explicit refreshes cover the rest.
      _refreshHomeSummary();
    });

    // 🔧 FIX: Home tab active glow — first frame లో animate చేయి
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
      }
    });

    // 🆕 Load notifications on app start
    _loadNotifications();
  }

  /// 🆕 Load notifications from backend and update unread count dynamically
  Future<void> _loadNotifications() async {
    try {
      // TODO: Replace with actual backend API call to fetch notifications
      // For now, this demonstrates the pattern
      // Example:
      // final response = await backendService.fetchNotifications();
      // _notificationsList = response.map(_NotifData.fromJson).toList();

      // Currently using empty list (no notifications by default)
      _notificationsList = [];

      // 🆕 Update unread count based on actual notifications
      _updateUnreadNotifCount();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading notifications: $e');
    }
  }

  /// 🆕 Calculate and update unread notification count
  void _updateUnreadNotifCount() {
    _unreadNotifCount = _notificationsList
        .where((notif) => notif.unread)
        .length;
  }

  Future<void> _fetchUserProfile() async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final profileCtrl = Provider.of<profile.ProfileController>(
      context,
      listen: false,
    );
    final user = await appwrite.getCurrentUser();

    if (user != null && mounted) {
      // ProfileController లో name ఉంటే దాన్ని వాడు (onboarding లో enter చేసిన name)
      // లేకపోతే Appwrite user.name వాడు
      final profileName = profileCtrl.state.name;
      final rawName = (profileName != null && profileName.isNotEmpty)
          ? profileName
          : user.name;

      final firstName = rawName.isNotEmpty
          ? rawName.split(' ').first
          : AppLocalizations.t(context, 'default_stylist_name');

      // avatarPath లేనప్పుడు Appwrite fallback avatar తెచ్చుకో
      Uint8List? avatarBytes;
      try {
        avatarBytes = await appwrite.getUserAvatar(rawName);
      } catch (_) {}

      // 🆕 Best-effort gender read (drives which outfit photo shows on the
      // Style card). Uses dynamic access so this keeps compiling even if
      // ProfileState doesn't expose one of these field names.
      final resolvedGender = _resolveGenderFromProfile(profileCtrl.state);

      if (mounted) {
        setState(() {
          _userName = firstName;
          _avatarBytes = avatarBytes;
          _userGender = resolvedGender;
          _invalidateSuggestionCache(); // name changed → rescore
        });
      }
    }
  }

  /// Reads the onboarding gender preference from [profile.ProfileState.gender]
  /// (set in onboarding1.dart via `ProfileController.updateBasics(gender: ...)`
  /// and now editable on the profile screen too) and maps it to the 'women' /
  /// 'men' bucket used to pick the Style card outfit photo.
  ///
  /// 🔧 Previously this used a dynamic multi-field-name guessing hack because
  /// it wasn't certain ProfileState exposed `gender` — it does, so we read it
  /// directly now.
  String _resolveGenderFromProfile(profile.ProfileState? state) {
    if (state == null) return _userGender;
    final v = state.gender.toLowerCase();
    if (v.contains('women') || v.contains('female') || v == 'w' || v == 'f') {
      return 'women';
    }
    if (v.contains('men') || v.contains('male') || v == 'm') {
      return 'men';
    }
    // 'others' (or anything unrecognized) — no 3rd generic asset by design,
    // so keep whatever gender was already showing.
    return _userGender;
  }

  void _updateClock() {
    if (!mounted) return;
    final now = DateTime.now();
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    // 🆕 Greeting key — translated in _buildGreetingBlock()
    String greetingKey;
    if (now.hour >= 5 && now.hour < 12) {
      greetingKey = 'greeting_morning';
    } else if (now.hour >= 12 && now.hour < 17) {
      greetingKey = 'greeting_afternoon';
    } else if (now.hour >= 17 && now.hour < 21) {
      greetingKey = 'greeting_evening';
    } else {
      greetingKey = 'greeting_night';
    }
    _clockState.value = (
      greeting: greetingKey,
      date:
          '${dayNames[now.weekday % 7]}, ${now.day} ${monthNames[now.month - 1]}',
    );
    // Invalidate suggestion cache — hour/weekday may have changed
    _invalidateSuggestionCache();
  }

  void _startThinkingAnimation() {
    if (!_thinkingCtrl.isAnimating) {
      _thinkingCtrl.repeat();
    }
  }

  void _stopThinkingAnimation() {
    if (_thinkingCtrl.isAnimating) {
      _thinkingCtrl
        ..stop()
        ..value = 0.0;
    }
  }

  // ── Voice methods ──────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.ensureReady();
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    _speechAvailable = await _speech.ensureReady();
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone access is unavailable. You can still type your message.',
            ),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _isListening = true);
    await _speech.start(
      onText: (text) {
        if (!mounted) return;
        setState(() {
          _chatController.text = text;
          _chatController.selection = TextSelection.collapsed(
            offset: text.length,
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
  }

  void _onChatFocusChange() {
    if (!mounted) return;
    if (!_chatFocusNode.hasFocus) {
      _keyboardHeight.value = 0.0;
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // ValueNotifier మాత్రమే update చేయి — setState() లేదు.
    // Prompt bar Builder లో MediaQuery.of(ctx).viewInsets directly read అవుతుంది.
    // setState() వేస్తే logo కూడా rebuild అయి jump అవుతుంది.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final kbH = MediaQuery.of(context).viewInsets.bottom;
      if (_keyboardHeight.value != kbH) {
        _keyboardHeight.value = kbH;
      }
    });
  }

  void dispose() {
    CalendarRefreshSignal.generation.removeListener(_onCalendarRefresh);
    _chatFocusNode.removeListener(_onChatFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardHeight.dispose();
    _speech.cancel();
    _aurora1Ctrl.dispose();
    _aurora2Ctrl.dispose();
    _aurora3Ctrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    _floatBadgeCtrl.dispose();
    _breatheCtrl.dispose();
    for (final c in _heartPopCtrls) {
      c.dispose();
    }
    _seeAllCtrl.dispose();
    _plusMenuCtrl.dispose();
    for (final c in _navRiseCtrls) {
      c.dispose();
    }
    _homeCollapseCtrl.dispose();
    _overlayFadeCtrl.dispose();
    _thinkingCtrl.dispose();
    _tagsRevealCtrl.dispose();
    _toastTimer?.cancel();
    _clockTimer?.cancel();
    _clockState.dispose();
    _cardContextVersion.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    for (final ctrls in _prepareExactAddControllersByTitle.values) {
      for (final c in ctrls) {
        c.dispose();
      }
    }
    _overlayScrollCtrl.dispose();
    super.dispose();
  }

  void _showComingSoon() {
    setState(() => _toastVisible = true);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  // 🚀 FIXED: Chat Navigation logic for the Bottom Nav Bar
  void _handleNavTap(int idx) {
    if (idx == 0) {
      // Home tab — already here, just ensure active
      if (_activeNavIdx != 0) {
        _navRiseCtrls[_activeNavIdx].animateTo(
          0.0,
          curve: const Cubic(0.4, 0.0, 0.2, 1.0),
        );
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
        setState(() => _activeNavIdx = 0);
      } else {
        // 🔧 FIX: Already on home tab — rise animation ensure చేయి
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
      }
      if (widget.onShellNavTap != null) widget.onShellNavTap!(0);
      return;
    }

    // Highlight the tapped tab immediately before navigating
    void _activateTab(int i) {
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[i].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = i);
    }

    if (idx == 1) {
      _activateTab(1);
      showAhviStylistChatSheet(context, moduleContext: 'style');
      return;
    }
    if (idx == 2) {
      // 🔧 FIX: Shell కి delegate చేసే ముందు local tab highlight చేయి
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[2].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = 2);
      if (widget.onShellNavTap != null) {
        widget.onShellNavTap!(2);
        return;
      }
      _openNavScreen(const WardrobeScreen());
      return;
    }
    if (idx == 3) {
      // 🔧 FIX: Shell కి delegate చేసే ముందు local tab highlight చేయి
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[3].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = 3);
      if (widget.onShellNavTap != null) {
        widget.onShellNavTap!(3);
        return;
      }
      _openNavScreen(const BoardsScreen());
      return;
    }
    if (idx == 4) {
      _showComingSoon();
      return;
    }
    if (idx == _activeNavIdx) return;

    _navRiseCtrls[_activeNavIdx].animateTo(
      0.0,
      curve: const Cubic(0.4, 0.0, 0.2, 1.0),
    );
    _navRiseCtrls[idx].animateTo(
      1.0,
      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
    );
    setState(() => _activeNavIdx = idx);
  }

  void _openPlusMenu(BuildContext ctx) {
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(ctx, rootNavigator: true);
    showAhviLensSheet(
      ctx,
      t: _t,
      // null -> showAhviLensSheet's own default (_runFindSimilarFlow), the
      // same canonical gallery-pick + backend search flow Style Me's "+"
      // already uses. Build 2012 had this overridden with a Coming Soon
      // stub instead of reusing it.
      onVisualSearch: null,
      onFindSimilar: null,
      onAddToWardrobe: () => showAddToWardrobeModal(navigator.context),
    );
  }

  void _closePlusMenu() {
    // No-op: lens sheet manages its own dismiss
  }

  void _openNavScreen(Widget page) {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 350),
            reverseTransitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (context, animation, secondary) => page,
            transitionsBuilder: (context, animation, secondary, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: const Cubic(0.22, 1.0, 0.36, 1.0),
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        )
        .then((_) {
          // Back వచ్చినప్పుడు Home tab active గా reset చేయి
          if (!mounted) return;
          final prevIdx = _activeNavIdx;
          if (prevIdx != 0) {
            _navRiseCtrls[prevIdx].animateTo(
              0.0,
              curve: const Cubic(0.4, 0.0, 0.2, 1.0),
            );
          }
          _navRiseCtrls[0].animateTo(
            1.0,
            curve: const Cubic(0.34, 1.56, 0.64, 1.0),
          );
          setState(() => _activeNavIdx = 0);
          // 🔧 FIX: Shell కి కూడా Home index తెలియజేయి — nav bar తిరిగి కనపడుతుంది
          if (widget.onShellNavTap != null) widget.onShellNavTap!(0);
        });
  }

  void _openModuleChat(String moduleKey) {
    _recordIntent(moduleKey); // 🆕 track for dynamic recommendations
    // Each card కి తన specific module తో chat open అవ్వాలి
    final String module;
    final String? initialPrompt;

    switch (moduleKey) {
      case 'style':
        module = 'style';
        initialPrompt = null; // Style module — default style chat
        break;
      case 'organize':
        module = 'organize';
        initialPrompt =
            null; // Organise module — wardrobe/outfit organisation chat
        break;
      case 'plan':
        module = 'prepare';
        initialPrompt =
            null; // Plan/Prepare module — event & trip planning chat
        break;
      default:
        module = moduleKey;
        initialPrompt = null;
    }

    showAhviStylistChatSheet(
      context,
      moduleContext: module,
      initialPrompt: initialPrompt,
    );
  }

  void _openChatWithPrompt(String prompt) {
    final text = prompt.trim();
    final module = (_activeIntent ?? 'style').trim();
    // ChatScreen కాదు — AhVi Stylist Chat sheet open చేయాలి
    showAhviStylistChatSheet(
      context,
      moduleContext: module,
      initialPrompt: text.isEmpty ? null : text,
    );
  }

  void _openPickSheet(String name, String tag) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _bgPrimary.withOpacity(0.30),
      builder: (sheetContext) => _buildPickSheet(
        name: name,
        tag: tag,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  void _openSeeAll() {
    setState(() => _seeAllOpen = true);
    _seeAllCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 400),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
  }

  void _closeSeeAll() {
    _seeAllCtrl
        .animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: const Cubic(0.4, 0.0, 1.0, 1.0),
        )
        .then((_) {
          if (mounted) setState(() => _seeAllOpen = false);
        });
  }

  void _toggleLike(int cardIdx) {
    setState(() => _likedState[cardIdx] = !_likedState[cardIdx]);
    _heartPopCtrls[cardIdx]
      ..reset()
      ..forward();
  }

  void _triggerIntent(String intent) {
    if (_overlayState != _OverlayState.idle) return;
    _recordIntent(intent); // 🆕 track for dynamic recommendations
    _activeIntent = intent;
    final cfg = _intentConfig[intent]!;
    _setPlaceholder(intent);
    setState(() {
      _homeCollapsed = true;
      _overlayBrandSub = cfg.brandSub;
    });
    _homeCollapseCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _stopThinkingAnimation();
        _overlayState = _OverlayState.suggestions;
        _overlaySuggestions = cfg.suggestions;
        // Isolate per-intent chat state — a Diet message must not leak into
        // a later Prepare/Style overlay session.
        _responses.clear();
        _chatHistory.clear();
        _runningMemory = '';
        _tagsRevealed = false;
      });
      _overlayFadeCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 380),
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      );
    });
  }

  void _submitQuery(String query) {
    // AhVi Stylist Chat sheet తెరుచుకుంటుంది
    _openChatWithPrompt(query);
  }

  // 🚀 FIXED FUNCTION: REAL API CALL WITH HISTORY & MEMORY
  Future<void> _handleQuery(String question, String intent) async {
    if (_overlayState == _OverlayState.thinking) return;

    final cfg = _intentConfig[intent] ?? _intentConfig['chat']!;

    setState(() {
      _startThinkingAnimation();
      _overlayState = _OverlayState.thinking;
      _overlaySuggestions = [];
      _responseTags = cfg.responseTags;
      _tagsRevealed = false;
      // We DO NOT clear _responses here so the old messages stay on screen!
    });

    _ResponseData? resp;

    final isPrepareQuickChip =
        intent == 'prepare' && _prepareChips.any((chip) => chip.$2 == question);
    if (isPrepareQuickChip) {
      resp = _buildPrepareChipResponse(question);
    } else {
      try {
        final backend = Provider.of<BackendService>(context, listen: false);

        // Grab the history payload we've been secretly storing
        final historyPayload = List<Map<String, String>>.from(_chatHistory);

        final apiResult = await backend.sendChatQuery(
          question,
          'user_$_userName',
          historyPayload,
          _runningMemory,
        );

        // Store user's question into history
        _chatHistory.add({"role": "user", "content": question});

        if (apiResult['updated_memory'] != null) {
          _runningMemory = apiResult['updated_memory'];
        }

        String aiText = "Could not parse response.";

        if (apiResult.containsKey('message') && apiResult['message'] != null) {
          aiText = apiResult['message']['content']?.toString() ?? "No content";
        } else if (apiResult.containsKey('error')) {
          aiText = apiResult['error']?.toString() ?? "Unknown error occurred";
        }

        // Store AHVI's response into history
        _chatHistory.add({"role": "assistant", "content": aiText});

        // Cleanup tags perfectly
        aiText = aiText.replaceAll(
          RegExp(r'\[CHIPS:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.replaceAll(
          RegExp(r'\[STYLE_BOARD:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.replaceAll(
          RegExp(r'\[PACK_LIST:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.trim();

        if (aiText.length > 1500) {
          aiText =
              '${aiText.substring(0, 1500)}... \n\n[Text truncated to prevent UI crash]';
        }

        if (apiResult.containsKey('chips') &&
            apiResult['chips'] != null &&
            apiResult['chips'] is List) {
          final List<dynamic> rawChips = apiResult['chips'];
          if (rawChips.isNotEmpty) {
            _responseTags = rawChips.map((e) => e.toString()).toList();
          }
        }

        resp = _ResponseData(type: 'text', question: question, intro: aiText);
      } catch (e) {
        String errorMsg = e.toString();
        if (errorMsg.length > 150) {
          errorMsg = '${errorMsg.substring(0, 150)}... [Error Truncated]';
        }

        resp = _ResponseData(
          type: 'text',
          question: question,
          intro: "Backend Connection Failed.\n\n$errorMsg",
        );
      }
    }

    if (!mounted) return;

    setState(() {
      _stopThinkingAnimation();
      _overlayState = _OverlayState.response;
      _responses.add(resp!); // 🚀 Add the new message to the list!
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_overlayScrollCtrl.hasClients) {
        _overlayScrollCtrl.animateTo(
          _overlayScrollCtrl.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    const int tagDelay = 150;

    Future.delayed(Duration(milliseconds: tagDelay), () {
      if (!mounted) return;
      setState(() => _tagsRevealed = true);
      _tagsRevealCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      );
    });
  }

  void _dismissOverlay() {
    _overlayFadeCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: const Cubic(0.4, 0.0, 1.0, 1.0),
    );
    _homeCollapseCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 500),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
    setState(() {
      _stopThinkingAnimation();
      _overlayState = _OverlayState.idle;
      _activeIntent = null;
      _homeCollapsed = false;
      _overlaySuggestions = [];
      _responses.clear();
      _tagsRevealed = false;
      _chatPlaceholderKey = 'ask_me'; // ✅
    });
  }

  void _setPlaceholder(String intent) {
    // 🆕 Key store చేస్తున్నాం — getter లో translate అవుతుంది
    setState(() => _chatPlaceholderKey = 'placeholder_$intent');
  }

  // Explicit Planner chip → canonical module chat. Bypasses the local
  // generic-prepare overlay (prepare_exact / /api/text) entirely so the
  // selected prompt is submitted as a real /api/module-chat user request.
  void _handlePrepareChipSend(String actionId) {
    final route = plannerRouteFor(actionId);
    _recordIntent('prepare');
    showAhviStylistChatSheet(
      context,
      moduleContext: route.module,
      initialPrompt: route.prompt,
    );
  }

  _ResponseData _buildPrepareChipResponse(String question) {
    return _ResponseData(type: 'prepare_exact', question: question, intro: '');
  }

  bool get _hasTransientUi =>
      _seeAllOpen || _overlayState != _OverlayState.idle;

  void _handleBackNavigation() {
    if (_seeAllOpen) {
      _closeSeeAll();
      return;
    }
    if (_overlayState != _OverlayState.idle) {
      _dismissOverlay();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AhviTransientBackScope(
      hasTransientUi: _hasTransientUi,
      onDismissTransientUi: _handleBackNavigation,
      child: Scaffold(
        backgroundColor: _bgPrimary,
        resizeToAvoidBottomInset: false,
        body: _buildPhoneScreen(),
      ),
    );
  }

  Widget _buildPhoneScreen() {
    return Container(
      decoration: BoxDecoration(color: _bgPrimary),
      child: Stack(
        children: [
          _buildAuroraLayer(),

          AnimatedBuilder(
            animation: _homeCollapseCtrl,
            builder: (context, child) {
              final curve = CurvedAnimation(
                parent: _homeCollapseCtrl,
                curve: const Cubic(0.16, 1.0, 0.3, 1.0),
                reverseCurve: const Cubic(0.4, 0.0, 1.0, 1.0),
              );
              final t = curve.value;
              return Transform.translate(
                offset: Offset(0, -48 * t),
                child: Transform.scale(
                  scale: 1.0 - 0.02 * t,
                  child: Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: IgnorePointer(
                      ignoring: _homeCollapsed,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: SafeArea(
              top: true,
              bottom: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenH = constraints.maxHeight;

                  // Placeholder height — must exactly match AhviHeader's real
                  // rendered height, not a separately-guessed formula.
                  // AhviHeader = SafeArea.top (statusBarH) + a FIXED 33px
                  // content SizedBox. Its internal topPad/botPad/logoSize
                  // vars are computed but never applied to its layout, so
                  // they must NOT be added here either — doing so previously
                  // over-reserved 9-19px of dead space under the header,
                  // pushing the greeting block down and shrinking heroH.
                  const double headerContentH = 33.0;
                  final double statusBarH = MediaQuery.paddingOf(context).top;
                  final double topBarPlaceholderH = statusBarH + headerContentH;

                  // 🆕 RESPONSIVE DESIGN - Adapt to all screen sizes
                  // Small phones: 280-360dp (minimal padding, compact spacing)
                  // Standard: 360-480dp (normal padding)
                  // Large: 480-640dp (increased spacing, larger cards)
                  // Tablets: 640+dp (centered, max width)
                  final screenW = constraints.maxWidth;
                  // 🆕 Single shared source of truth — see _responsiveGutter
                  // above. The fixed logo bar (_buildFixedLogoBar) reads the
                  // exact same function, so the header and body content can
                  // never drift out of alignment again.
                  final gutter = _responsiveGutter(screenW);
                  final double horizontalPad = gutter.horizontalPad;
                  final double maxContentWidth = gutter.maxContentWidth;
                  final double cardSpacing;
                  final double topSpacing;

                  // Fixed page-spacing values (consistent across all screen sizes):
                  //   Chips → Hero: 10px ✏️ Reduced from 12px, Hero → Routine / Routine → Prep: 8px ✏️ Reduced from 10px
                  // 🔧 FIX: Responsive spacing for small screens
                  cardSpacing = screenW < 340 ? 6.0 : 8.0;
                  topSpacing = screenW < 340 ? 8.0 : 10.0;

                  // ── Bottom reserve: chat bar + nav bar + safe bottom ──────────
                  // Now ACTUALLY applied (previously computed but unused) as the
                  // Prep & Plan card's bottom clearance below, so the card's
                  // visible area always stops above the floating prompt bar —
                  // on every screen size, with zero RenderFlex overflow risk,
                  // since it's applied inside an Expanded (which can never
                  // request more space than its parent has to give).
                  final safeBottom = MediaQuery.paddingOf(context).bottom;
                  // Prompt bar sits at bottom: navBarTotalH (safeBottom+88).
                  // We only need to clear: navBarTotalH + promptBarH + gap.
                  // Do NOT add safeBottom again — it's already baked into navBarTotalH.
                  // ✏️ Bumped +8 (62→70) to reserve space for the taller prompt
                  // bar — actual bar height lives in AhviChatPromptBar
                  // (widgets/ahvi_chat_prompt_bar.dart), not in this file.
                  const promptBarH = 70.0;
                  // ✏️ Nav bar sits at safeB+6, is now 78px tall (pillH 64 +
                  // maxBulge 14 — bumped from 58px so icons feel less
                  // cramped), so its top edge sits at safeB+84. A consistent
                  // 4px gap above it puts navBarTotalH at safeB+88.
                  // ✅ FIX 1: navBarTotalH reduced by 1px (88→87).
                  // ✅ FIX 3: tightened by another 1px (87→86) — Nav Bar ↔
                  // Prompt Bar gap is now 1px tighter than before.
                  final double navBarTotalH = 86.0;
                  final double screenHFull = MediaQuery.of(context).size.height;
                  final double promptExtraLift = screenHFull >= 760
                      ? 8.0
                      : screenHFull >= 680
                      ? 6.0
                      : 0.0;
                  // ✅ FIX 2: breathingGap reduced from 6→4 (saves 2px between
                  // Prep & Plan card and Prompt Bar).
                  // ✅ FIX 4: tightened by another 3px (4→1 → 0) — Prep & Plan ↔
                  // Prompt Bar gap is now 4px tighter than before (no gap).
                  const breathingGap = 0.0;
                  // Combined, FIX 3 + FIX 4 recover 4px of vertical space
                  // (1px + 3px) versus the previous layout. That whole 4px is
                  // routed entirely into the Routine Cards section below
                  // (see recoveredSpaceForRoutine) instead of being re-split
                  // across Hero + Routine by flex.
                  const recoveredSpaceForRoutine = 4.0;

                  // 🔧 FIX: Responsive bottom reserve for small screens
                  final bottomReserved = screenW < 340
                      ? (safeBottom + 72.0) // Reduced for tiny phones
                      : screenW < 380
                      ? (safeBottom +
                            navBarTotalH +
                            promptBarH +
                            promptExtraLift +
                            breathingGap -
                            3.0)
                      : (safeBottom +
                            navBarTotalH +
                            promptBarH +
                            promptExtraLift +
                            breathingGap -
                            1.0);

                  return SizedBox(
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: horizontalPad,
                        right: horizontalPad,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        // Must be max so Expanded can fill remaining height.
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // ── FIXED: logo bar placeholder ────────────────────
                          SizedBox(height: topBarPlaceholderH),

                          // ── FIXED: Date · Greeting · Mobility/Temp/Meeting chips ──
                          // These three elements NEVER scroll.
                          ValueListenableBuilder<int>(
                            valueListenable: _cardContextVersion,
                            builder: (context, _, __) => _buildGreetingBlock(),
                          ),
                          SizedBox(height: topSpacing),

                          // ── CARDS LAYOUT — distribute remaining height ────────
                          // Expanded takes all SafeArea height minus topBar + greeting.
                          // The inner LayoutBuilder distributes that to the 3 cards.
                          // bottomReserved padding keeps the last card above the prompt bar.
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: bottomReserved),
                              child: LayoutBuilder(
                                builder: (context, cardConstraints) {
                                  final availableH = cardConstraints.maxHeight;
                                  // ── PREP & PLAN: fixed height (it hosts a designed,
                                  // pre-cropped weekly image, so it shouldn't stretch
                                  // or shrink like the other two). Still screen-size
                                  // aware via the existing proportional+clamp formula,
                                  // just bumped +17px (15–20px per spec) on top of it.
                                  // ── PREP & PLAN: Reduced by ~17px vs previous formula ──
                                  // The saved height flows to Routine cards (flex 38 vs 35)
                                  // which eliminates the 1px bottom overflow on all screens.
                                  final prepH = (availableH * 0.22).clamp(
                                    95.0,
                                    120.0,
                                  );

                                  // ── HERO + ROUTINE: guaranteed-minimum allocation ───────
                                  // Strategy: routine cards always get at least routineMinH
                                  // (stepper 26 + cards 90 + internal gaps ≈ 118px).
                                  // Hero gets whatever's left, with its own floor of 160px
                                  // so it never collapses to unreadable on short phones.
                                  // On taller screens (>400px flexible) the natural 62/38
                                  // split applies unchanged — minimum floors only kick in
                                  // on compact devices where the math would shrink cards.
                                  const routineMinH = 118.0;
                                  const heroMinH = 160.0;
                                  final flexibleH =
                                      availableH - prepH - (cardSpacing * 2);
                                  final naturalHeroH = math.max(
                                    0.0,
                                    (flexibleH - recoveredSpaceForRoutine) *
                                        0.62,
                                  );
                                  final naturalRoutineH = math.max(
                                    0.0,
                                    flexibleH -
                                        naturalHeroH -
                                        recoveredSpaceForRoutine,
                                  );
                                  // If the natural split gives routine less than its minimum,
                                  // pin routine at its min and give hero the rest (floored).
                                  final heroH = naturalRoutineH < routineMinH
                                      ? math.max(
                                          heroMinH,
                                          flexibleH -
                                              routineMinH -
                                              recoveredSpaceForRoutine,
                                        )
                                      : naturalHeroH;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      // ── HERO / STYLE CARD ──────────────────────────────
                                      SizedBox(
                                        height: heroH,
                                        width: double.infinity,
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: _cardContextVersion,
                                          builder: (context, _, __) =>
                                              _buildHeroCard(),
                                        ),
                                      ),
                                      SizedBox(height: cardSpacing),

                                      // ── ROUTINE CARDS ───────────────────────────────────
                                      // Expanded absorbs all remaining space, which now
                                      // includes the full 4px recovered above.
                                      Expanded(
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: _cardContextVersion,
                                          builder: (context, _, __) =>
                                              _buildRoutineCardsSection(),
                                        ),
                                      ),
                                      SizedBox(height: cardSpacing),

                                      // ── PREP & PLAN CARD ────────────────────────────────
                                      SizedBox(
                                        height: prepH,
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: _cardContextVersion,
                                          builder: (context, _, __) =>
                                              _buildPrepPlanCard(
                                                screenH: screenH,
                                              ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Fixed AHVI Logo — Chat screen లాగే Positioned గా ఉంది ──
          // top: 0, SafeArea(bottom: false) తో — Chat _ChatLogoHeader తో
          // exact match అవుతుంది: status bar + topPad + logoFontSize + botPad
          Positioned(top: 0, left: 0, right: 0, child: _buildFixedLogoBar()),

          if (_overlayState != _OverlayState.idle) _buildAiOverlay(),

          if (_activeIntent == 'prepare' &&
              (_overlayState == _OverlayState.suggestions ||
                  _overlayState == _OverlayState.response))
            Builder(
              builder: (context) {
                final keyboardH = MediaQuery.of(context).viewInsets.bottom;
                final chipsBottom = keyboardH > 0
                    ? keyboardH + 60
                    : (MediaQuery.of(context).size.height * 0.23).clamp(
                        160.0,
                        210.0,
                      );
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: chipsBottom,
                  child: _buildPrepareBottomQuickChips(),
                );
              },
            ),

          // Plus menu replaced by AhviLensSheet (opened via onPlusTap)

          // ── Floating Prompt Bar ─────────────────────────────────────────────
          // Nav bar fixed గా ఉంటుంది — keyboard వచ్చినా move అవ్వదు
          // Prompt bar మాత్రమే keyboard పైకి లిఫ్ట్ అవుతుంది
          Builder(
            builder: (ctx) {
              // Read viewInsets directly — no ValueNotifier needed,
              // didChangeMetrics triggers a rebuild via setState anyway.
              final kbH = MediaQuery.of(ctx).viewInsets.bottom;
              final safeB = MediaQuery.paddingOf(ctx).bottom;
              final screenHPrompt = MediaQuery.of(ctx).size.height;
              // ✏️ Nav bar sits at safeB+6, is now 78px tall (pillH 64 +
              // maxBulge 14, up from 58px) — top edge at safeB+84. A
              // consistent 4px gap above it puts navBarTotalH at safeB+88.
              // ✅ FIX 1: matches bottomReserved — prompt bar 1px closer to nav bar.
              // ✅ FIX 3: matches bottomReserved — tightened another 1px (87→86).
              final navBarTotalH = safeB + 86.0;
              // ✏️ Responsive keyboard-open gap: 8px on shorter screens, 10px
              // on taller ones (was a fixed 8px).
              final double promptKeyboardGap = screenHPrompt < 700 ? 8.0 : 10.0;
              // ✏️ Extra lift so the prompt bar sits 6–8px higher than its
              // resting spot when the screen has room to spare — the 4px
              // gap above the nav bar is always preserved as a floor, this
              // only ever adds MORE breathing room on taller devices.
              final double promptExtraLift = screenHPrompt >= 760
                  ? 8.0
                  : screenHPrompt >= 680
                  ? 6.0
                  : 0.0;
              final promptBottom = kbH > 0
                  ? kbH + promptKeyboardGap
                  : navBarTotalH + promptExtraLift;
              return Positioned(
                left: 20,
                right: 20,
                bottom: promptBottom,
                // Wrap in MediaQuery with zeroed viewInsets so Flutter does NOT
                // call showOnScreen / scroll-to-visible when the TextField gets
                // focus — that was causing the whole page to jump to the top.
                child: MediaQuery(
                  data: MediaQuery.of(
                    ctx,
                  ).copyWith(viewInsets: EdgeInsets.zero),
                  child: _buildChatWrap(),
                ),
              );
            },
          ),

          // Only show nav bar when NOT inside a Shell (Shell has its own nav bar)
          // 🔧 FIX: Keyboard open అయినా nav bar same position లో ఉండాలి — hide చేయకూడదు
          if (widget.onShellNavTap == null)
            Builder(
              builder: (ctx) {
                final safeB = MediaQuery.paddingOf(ctx).bottom;
                return Positioned(
                  left: 16,
                  right: 16,
                  bottom: safeB + 6,
                  child: _buildBottomNav(),
                );
              },
            ),

          if (_seeAllOpen) _buildSeeAllPanel(),

          if (_notifPanelOpen) _buildNotificationPanel(),

          _buildComingSoonToast(),
        ],
      ),
    );
  }

  Widget _buildAuroraLayer() {
    // 🔧 FIX: RepaintBoundary తీసేశాం + colors ని builder లోపల
    // fresh గా read చేస్తున్నాం — palette switch అయినప్పుడు correct colors వస్తాయి
    return Positioned.fill(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _aurora1Ctrl,
            _aurora2Ctrl,
            _aurora3Ctrl,
          ]),
          builder: (context, _) {
            final t1 = _aurora1Ctrl.value;
            final t2 = _aurora2Ctrl.value;
            final t3 = _aurora3Ctrl.value;
            final tok = context.themeTokens;
            final c1 = tok.accent.primary;
            final c2 = tok.accent.secondary;
            final c3 = tok.accent.tertiary;
            return Stack(
              children: [
                Positioned(
                  top: -100 + (t1 * 90),
                  left: -80 + (t1 * 60),
                  child: _auroraOrb(340, 340, c1.withOpacity(0.30)),
                ),
                Positioned(
                  bottom: -60 + (t2 * 60),
                  right: -60 + (t2 * 30),
                  child: _auroraOrb(300, 300, c2.withOpacity(0.34)),
                ),
                Positioned(
                  top: 300 + (t3 * -60),
                  left: -40 + (t3 * 100),
                  child: _auroraOrb(220, 220, c3.withOpacity(0.22)),
                ),
                Positioned(
                  top: 140 + (t1 * 80),
                  right: -30,
                  child: _auroraOrb(180, 180, c1.withOpacity(0.18)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _auroraOrb(double w, double h, Color color) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }

  // ── RESPONSIVE UTILITIES ──────────────────────────────────────────────
  /// Responsive text sizing utility that scales based on screen width
  /// Prevents text from becoming too small or too large across devices
  double _responsiveTextSize({
    required double baseSize,
    required double screenWidth,
    double? minSize,
    double? maxSize,
  }) {
    final scaled = baseSize * (screenWidth / 360.0);
    return scaled.clamp(
      minSize ?? (baseSize * 0.8),
      maxSize ?? (baseSize * 1.2),
    );
  }

  /// Get minimum horizontal padding based on screen width
  EdgeInsets _responsivePadding(double screenWidth) {
    if (screenWidth < 340) {
      return const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);
    } else if (screenWidth < 400) {
      return const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0);
    } else {
      return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0);
    }
  }

  Widget _buildTopBar() {
    final screenH = MediaQuery.of(context).size.height;
    final double topPad = screenH < 700 ? 12.0 : 16.0;
    final double botPad = screenH < 700 ? 4.0 : 6.0;
    final double logoFontSize = screenH < 700 ? 26.0 : 30.0;
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: botPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AhviHomeText(
            color: _textHeading,
            fontSize: logoFontSize,
            letterSpacing: 3.2,
            fontWeight: FontWeight.w400,
          ),
          _buildProfileAvatar(),
        ],
      ),
    );
  }

  // ── Fixed logo bar — stays put regardless of home collapse animation ──
  Widget _buildFixedLogoBar() {
    // Delegated to AhviHeader — same spacing on all screens, keyboard-safe
    final screenW = MediaQuery.of(context).size.width;
    // 🔧 FIX: previously AhviHeader used its own hardcoded 20px inset here,
    // while the body content below used the responsive `horizontalPad` from
    // _responsiveGutter (8/10/16/20, or centered on tablets). That mismatch
    // is exactly why the logo looked misaligned relative to the greeting
    // text and cards. Reading the same shared helper guarantees the logo's
    // left edge always matches the content's left edge.
    final horizontalPad = _responsiveGutter(screenW).horizontalPad;
    return AhviHeader(
      frosted: false,
      horizontalPadding: horizontalPad,
      right: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNotificationButton(),
          SizedBox(
            width: screenW < 360 ? 8 : 10,
          ), // 🔧 Reduce gap on tiny phones
          _buildProfileAvatar(),
        ],
      ),
    );
  }

  // ── Notification bell button ───────────────────────────────────────────────
  Widget _buildNotificationButton() {
    // 🔧 FIXED: Always 48x48px on every device — matches profile avatar size
    const double iconButtonSize = 33.0;
    const double iconSize = 20.0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _notifPanelOpen = true;
          _unreadNotifCount = 0; // mark as read when opened
        });
      },
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: iconButtonSize, // 🔧 FIXED: 48px on all screen sizes
          height: iconButtonSize, // 🔧 FIXED: 48px on all screen sizes
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: iconButtonSize,
                height: iconButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surface,
                  border: Border.all(
                    color: _border.withOpacity(0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  size: iconSize, // 🔧 FIXED: 24px on all screen sizes
                  color: _textHeading,
                ),
              ),
              // Unread badge
              if (_unreadNotifCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 16, // 🔧 FIXED: proportional to 40px button
                    height: 16, // 🔧 FIXED: proportional to 40px button
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_accent, _accentTertiary],
                      ),
                      border: Border.all(
                        color: _bgPrimary,
                        width:
                            1.5, // 🔧 FIXED: thinner border for smaller badge
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8, // 🔧 FIXED: proportional to 16px badge
                          fontWeight: FontWeight.w800,
                          height: 1,
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

  Widget _buildProfileAvatar() {
    // 🔧 FIXED: Always 48x48px on every device — matches notification bell size
    const double avatarSize = 33.0;

    // ✅ FIX: ProfileController ని watch చేసి avatarPath directly వాడు
    // profile లో photo మారినప్పుడు ఇక్కడ automatically rebuild అవుతుంది
    final profileState = context.watch<profile.ProfileController>().state;
    final avatarPath = profileState.avatarPath;
    // ✅ FIX: was hardcoded 'P' — now derives the fallback initial from the
    // real signed-in user's name (profile name, else the greeting name we
    // already fetched, else a generic default) so it's never someone else's
    // initial.
    final String _fallbackName =
        profileState.name.isNotEmpty && profileState.name != 'New User'
        ? profileState.name
        : (_userName.isNotEmpty
              ? _userName
              : AppLocalizations.t(context, 'default_user_name'));
    final String _avatarInitial = _fallbackName[0].toUpperCase();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context)
            .push(
              PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 350),
                reverseTransitionDuration: const Duration(milliseconds: 350),
                pageBuilder: (context, animation, secondary) =>
                    const profile.ProfileScreen(),
                transitionsBuilder: (context, animation, secondary, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
              ),
            )
            .then((_) {
              // userName refresh కోసం మాత్రమే
              if (mounted) _fetchUserProfile();
            });
      },
      // ✅ FIX: Align gives its child loose constraints (rather than the tight
      // ones a parent Row/Header might otherwise impose), so this avatar is
      // always laid out at its own natural size — guaranteeing a
      // perfect circle instead of the stretched oval seen before.
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: avatarSize, // 🔧 FIXED: 48px on all screen sizes
          height: avatarSize, // 🔧 FIXED: 48px on all screen sizes
          child: Container(
            width: avatarSize, // 🔧 FIXED: matches SizedBox size
            height: avatarSize, // 🔧 FIXED: matches SizedBox size
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.88),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: avatarPath != null && avatarPath.isNotEmpty
                  ? Image.file(
                      File(avatarPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _accent,
                        child: const Icon(
                          Icons.person_rounded,
                          size: 20, // 🔧 FIXED: proportional to 40px avatar
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_accent, _accentSecondary],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _avatarInitial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize:
                                16, // 🔧 FIXED: proportional to 40px avatar
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
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

  Widget _buildGreetingBlock() {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final double heightBasedSize = screenH < 700 ? 20.0 : 24.0;
    // 🔧 IMPROVED: More aggressive scaling on very small screens
    // Prevents text overflow on narrow phones (< 340px)
    final double greetFontSize = screenW < 340
        ? (heightBasedSize * (screenW / 360.0)).clamp(16.0, 22.0)
        : (heightBasedSize * (screenW / 360.0)).clamp(18.0, 24.0);
    return Padding(
      padding: EdgeInsets
          .zero, // Chips → Hero gap now fully controlled by `topSpacing` below
      child: ValueListenableBuilder<_ClockState>(
        valueListenable: _clockState,
        builder: (context, clock, _) {
          // 🆕 greeting key ని translate చేస్తున్నాం
          final greetingText = AppLocalizations.t(context, clock.greeting);

          // ProfileController నుండి name చదువు — onboarding లో enter చేసిన name వస్తుంది
          final profileName =
              context.watch<profile.ProfileController>().state.name ?? '';
          final displayName = profileName.isNotEmpty
              ? profileName.split(' ').first
              : _userName;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clock.date.isEmpty
                    ? AppLocalizations.t(context, 'date_example')
                    : clock.date,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(
                height: 0.0,
              ), // ✏️ Reduced from 4.0 — tightens date→greeting gap
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: greetFontSize,
                    fontWeight: FontWeight.w500,
                    color: _textHeading,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                  children: [
                    if (displayName.isNotEmpty) ...[
                      TextSpan(text: '$greetingText, '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _GradientText(
                          '$displayName.',
                          fontSize: greetFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else
                      TextSpan(text: '$greetingText.'),
                  ],
                ),
                textAlign: TextAlign.left,
                softWrap: true, // 🔧 NEW: Allows wrapping if needed
                maxLines: 2, // 🔧 NEW: Allow max 2 lines for long names
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(
                height: 6.0,
              ), // ✏️ Reduced from 12.0 → 6.0 (greeting→chips gap)
              _buildContextInfoChips(),
            ],
          );
        },
      ),
    );
  }

  /// Builds the 3 context chips: Mobility day | 27° | No meetings
  Widget _buildContextInfoChips() {
    final screenW = MediaQuery.of(context).size.width;
    // 🆕 Continuous responsive scale factor (1.0 = 360dp baseline), matching
    // the same proportional approach used by the style/hero card, Prep & Plan
    // card, and routine cards — instead of one fixed pixel size for every
    // phone screen.
    final chipScale = (screenW / 360.0).clamp(0.85, 1.30);
    final chipIconSize = 14.0 * chipScale;
    final chipFontSize = 12.0 * chipScale;
    final chipPadH = 11.0 * chipScale;
    final chipPadV = 4.0 * chipScale;
    final chipIconGap = 5.0 * chipScale;
    // 🔧 IMPROVED: Reduce gap on small screens to fit more items
    final chipGap = screenW < 340 ? 6.0 * chipScale : 8.0 * chipScale;

    // Derive labels from live signals
    final w = _weatherSignal;
    final tempLabel = w.tempCelsius != null
        ? '${w.tempCelsius!.round()}°'
        : '--°';
    final weatherDesc = w.description.isNotEmpty ? w.description : 'clear';

    // Workout type chip label
    final fit = _fitnessSignal;
    String mobilityLabel = AppLocalizations.t(context, 'chip_mobility_default');
    if (fit.nextWorkoutLabel.isNotEmpty) {
      mobilityLabel = fit.nextWorkoutLabel;
    }

    // Calendar chip label
    final ctx = _recommendationCtx;
    final meeting = ctx.nextMeeting;
    String calLabel = AppLocalizations.t(context, 'chip_no_meetings');
    if (meeting != null && meeting.isToday) {
      final hoursLeft = meeting.hoursUntil;
      calLabel = hoursLeft > 0
          ? '${meeting.title} in ${hoursLeft}h'
          : meeting.title;
    } else if (_calendarEvents.isNotEmpty) {
      calLabel = _calendarEvents.first.title;
    }

    Widget chip({
      required IconData icon,
      required String label,
      required Color iconColor,
      required VoidCallback onTap,
    }) {
      // Cap label length so chips never break layout on very small screens
      final maxLabelChars = screenW < 360 ? 12 : 18;
      final displayLabel = label.length > maxLabelChars
          ? '${label.substring(0, maxLabelChars)}…'
          : label;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            // 🔧 IMPROVED: More aggressive clamping for very small screens
            maxWidth: screenW < 340
                ? (screenW * 0.45).clamp(75.0, 140.0)
                : (screenW * 0.38).clamp(90.0, 160.0),
          ),
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.90),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
            boxShadow: [BoxShadow(color: _shadowLight, blurRadius: 6)],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: chipPadH,
            vertical: chipPadV,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: chipIconSize, color: iconColor),
              SizedBox(width: chipIconGap),
              Flexible(
                child: Text(
                  displayLabel,
                  style: TextStyle(
                    color: _textHeading,
                    fontSize: chipFontSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ✅ Dropdown arrow removed - no more dropdowns
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // ✅ MOBILITY CHIP - Synced with Workout screen
          chip(
            icon: Icons.directions_run_rounded,
            label: mobilityLabel,
            iconColor: const Color(0xFF5BBF8A),
            onTap: () {
              // Navigate to Workout screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WorkoutStudioScreen(fromHome: true),
                ),
              );
            },
          ),
          SizedBox(width: chipGap),

          // ✅ WEATHER CHIP - Synced with Meteo API (Display only, no modal)
          chip(
            icon: Icons.wb_sunny_outlined,
            label: tempLabel,
            iconColor: const Color(0xFFE8895A),
            onTap: () {
              // Weather chip is now informational only - no modal
            },
          ),
          SizedBox(width: chipGap),

          // ✅ MEETINGS CHIP - Synced with Calendar screen
          chip(
            icon: Icons.calendar_today_outlined,
            label: calLabel,
            iconColor: _accent,
            onTap: () {
              // Navigate to Calendar screen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BoardsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChipsRow() {
    final screenW = MediaQuery.of(context).size.width;
    final chipFontSize = screenW < 360 ? 11.0 : 12.0;
    final chipHPad = screenW < 360 ? 10.0 : 14.0;
    // 🆕 Chips localized
    final chips = [
      (
        '✦',
        AppLocalizations.t(context, 'chip_outfit_idea'),
        AppLocalizations.t(context, 'chip_prompt_outfit'),
      ),
      (
        '◎',
        AppLocalizations.t(context, 'chip_daily_plan'),
        AppLocalizations.t(context, 'chip_prompt_daily_plan'),
      ),
      (
        '⊹',
        AppLocalizations.t(context, 'chip_workout'),
        AppLocalizations.t(context, 'chip_prompt_workout'),
      ),
      (
        '◈',
        AppLocalizations.t(context, 'chip_meal_plan'),
        AppLocalizations.t(context, 'chip_prompt_meal_plan'),
      ),
      (
        '◷',
        AppLocalizations.t(context, 'chip_schedule'),
        AppLocalizations.t(context, 'chip_prompt_schedule'),
      ),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: chips.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return _AnimatedPressable(
            liftY: -2.0,
            scalePressed: 0.95,
            onTap: () => _openChatWithPrompt(chips[i].$3),
            child: Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(color: _shadowMedium, blurRadius: 8),
                  BoxShadow(color: _accent.withOpacity(0.06), blurRadius: 8),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: chipHPad, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (b) => _accentGradient.createShader(b),
                    child: Text(
                      chips[i].$1,
                      style: TextStyle(color: _textHeading, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    chips[i].$2,
                    style: TextStyle(
                      color: _textSub,
                      fontSize: chipFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.01,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrepareBottomQuickChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        itemCount: _prepareChipKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          // 🆕 label localized, prompt English గా పంపుతున్నాం
          return _PrepareQuickChip(
            label: AppLocalizations.t(context, _prepareChipKeys[i].$1),
            onSend: () => _handlePrepareChipSend(_prepareChipKeys[i].$1),
            accent: _accent,
            accentSecondary: _accentSecondary,
            panel: _panel,
            border: _border,
            activeText: _textHeading,
            textMuted: _textMuted,
          );
        },
      ),
    );
  }

  /// Returns a context-aware headline + subtitle for the hero card,
  /// driven by upcoming occasions, weather, and time of day.
  /// 🆕 Now uses localization for hero titles
  ({String headline, String emoji}) _heroHeadlineContent(
    _RecommendationContext ctx,
  ) {
    // 🆕 Get localized hero title for morning greeting
    final localizedHeroTitle = AppLocalizations.t(context, 'home_hero_title');
    final w = ctx.weather;

    // 📅 Occasion takes top priority — overrides everything else.
    if (ctx.hasSoonOccasion) {
      final e = ctx.nextOccasion!;
      return (
        headline:
            '${e.title} In ${e.hoursUntil}h — ${AppLocalizations.t(context, 'hero_occasion_suffix')}',
        emoji: '🎉',
      );
    }
    if (ctx.hasSoonMeeting) {
      final e = ctx.nextMeeting!;
      return (
        headline:
            '${e.title} In ${e.hoursUntil}h — ${AppLocalizations.t(context, 'hero_meeting_suffix')}',
        emoji: '💼',
      );
    }

    // 🌦️ Weather-driven
    if (w.isRainy) {
      return (
        headline: AppLocalizations.t(context, 'hero_rainy'),
        emoji: '🌧️',
      );
    }
    if (w.isCold && w.tempLabel.isNotEmpty) {
      return (
        headline:
            '${w.tempLabel} ${AppLocalizations.t(context, 'hero_cold_suffix')}',
        emoji: '❄️',
      );
    }
    if (w.isHot && w.tempLabel.isNotEmpty) {
      return (
        headline:
            '${w.tempLabel} ${AppLocalizations.t(context, 'hero_hot_suffix')}',
        emoji: '☀️',
      );
    }

    // 🕒 Time-of-day fallback
    if (ctx.isMorning) {
      // 🆕 Use localized hero title which includes emoji: "Your Effortlessly Put-Together Day ✨"
      return (headline: localizedHeroTitle, emoji: '');
    }
    if (ctx.isAfternoon) {
      return (
        headline: AppLocalizations.t(context, 'hero_afternoon'),
        emoji: '🔥',
      );
    }
    if (ctx.isEvening) {
      return (
        headline: AppLocalizations.t(context, 'hero_evening'),
        emoji: '🌆',
      );
    }
    return (headline: AppLocalizations.t(context, 'hero_night'), emoji: '🌙');
  }

  // Style card outfit index for Next button
  int _styleCardOutfitIndex = 0;

  // 🆕 IMPROVED HERO CARD - 50% Image | 50% Text Split (No Fade Overlay)
  Widget _buildHeroCard() {
    final cardBg = _surface;
    final ctx = _recommendationCtx;
    final w = ctx.weather;

    // 🔧 FIX: The style image was going stale / ignoring the user's actual
    // profile because gender was only ever read ONCE, in initState via
    // _fetchUserProfile(), using Provider.of(..., listen: false) — a
    // one-time snapshot. If the profile hadn't finished loading yet at that
    // exact moment (a common cold-start race), or if the user later changes
    // their style/gender preference in their profile, `_userGender` never
    // updated — it just kept showing whatever it resolved to on that first
    // frame (or the hardcoded 'women' default).
    //
    // Fix: watch ProfileController here (same pattern _buildProfileAvatar
    // already uses for the avatar photo) so this card rebuilds and
    // re-resolves gender live, every time the profile actually changes —
    // not just once at app start. _userGender is kept only as a fallback
    // for the brief window before the provider has emitted its first value.
    final liveProfileState = context.watch<profile.ProfileController>().state;
    final resolvedGender = _resolveGenderFromProfile(liveProfileState);

    // ✅ Only 2 images total — no generic/neutral fallback asset. If gender
    // still can't be resolved, this naturally falls back to one of the 2
    // gendered photos instead of a 3rd generic image.
    final genderedAssetPath = resolvedGender == 'men'
        ? 'assets/images/style_card_men.jpeg'
        : 'assets/images/style_card_women.jpeg';

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breatheCtrl,
        builder: (context, _) {
          final breatheOpacity = 0.08 + 0.06 * _breatheCtrl.value;
          final screenW = MediaQuery.of(context).size.width;
          final screenH = MediaQuery.of(context).size.height;

          // ── RESPONSIVE SIZING ──────────────────────────────────────────
          // cardHeight is driven by the parent SizedBox; use double.infinity
          // so the card fills whatever height the parent provides.
          // Internal sizes derived from screenW (not screenH) for consistency.
          final cardHeight = double.infinity;

          // Responsive padding based on screen width
          // ✏️ Left/right padding reduced by 4px per spec (was 12/16/20).
          final horPadding = screenW < 360
              ? 8.0
              : screenW < 640
              ? 12.0
              : 16.0;
          final vertPadding = screenW < 360
              ? 12.0
              : screenW < 640
              ? 14.0
              : 16.0;
          // 🆕 Text font sizes are now derived inside a LayoutBuilder around the
          // text panel itself (see the flex:55 Expanded below) so they scale
          // off the card's own available width/height instead of just the
          // global screen width — keeps the heading, labels, descriptions and
          // CTA proportional to the card size on every device.

          return Container(
            width: double.infinity,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: cardBg,
              border: Border.all(color: _border.withOpacity(0.45), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _shadowStrong,
                  blurRadius: 32,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: _accent.withOpacity(breatheOpacity),
                  blurRadius: 20,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // ── 45% LEFT SIDE: OUTFIT IMAGE (BALANCED) ──────────────────────────────
                // 🆕 UPDATED to 45% for better balance with expanded text
                Expanded(
                  flex: 45,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28),
                    ),
                    // 🔧 FIX: style_card_men/women.jpeg are tall portrait photos
                    // (971×~1620, aspect ≈0.60) but this panel is roughly square
                    // to wide on most phones. BoxFit.cover previously scaled the
                    // image up to fill the panel's width, pushing the height well
                    // past the panel — and with alignment: topCenter, ALL of that
                    // overflow was cropped off the bottom, which is exactly where
                    // the shoes sit in both photos. Same two-layer approach as the
                    // plan_card panel below: a blurred BoxFit.cover copy fills the
                    // panel edge-to-edge with no gaps (purely decorative, so
                    // cropping it is invisible), and the sharp photo sits on top
                    // at BoxFit.contain, which never crops — the full outfit,
                    // head to shoe, is always visible on every screen size.
                    //
                    // 🆕 FIX: Extract dominant color from the image and use that
                    // to fill empty space, creating seamless blend with the outfit.
                    child: _buildImageWithDominantColorBackground(
                      genderedAssetPath,
                    ),
                  ),
                ),

                // ── 55% RIGHT SIDE: TEXT CONTENT (PREMIUM) ──────────────────────────────
                // 🆕 INCREASED to 55% for prominent text display
                Expanded(
                  flex: 55,
                  child: Padding(
                    // 🆕 OPTIMIZED: Balanced padding for spacious feel
                    padding: EdgeInsets.only(
                      left: horPadding * 0.75,
                      right: horPadding * 0.75,
                      top: vertPadding,
                      bottom: vertPadding,
                    ),
                    // 🆕 LayoutBuilder gives us the *actual* text panel width so
                    // every font/spacing value below scales off the card's own
                    // available space (not just a global screen-width bucket).
                    // FittedBox(scaleDown) further downstream still guarantees
                    // zero overflow even if a very long localized string comes in.
                    child: LayoutBuilder(
                      builder: (context, textConstraints) {
                        final panelW = textConstraints.maxWidth;
                        // 165dp is the panel width on a baseline 360dp phone
                        // (55% flex minus padding) — used as the 1.0 reference.
                        final sizeScale = (panelW / 165.0).clamp(0.72, 1.35);
                        final titleFontSize = (16.0 * sizeScale).clamp(
                          11.0,
                          20.0,
                        );
                        final bulletLabelSize = (12.0 * sizeScale).clamp(
                          9.5,
                          15.0,
                        );
                        final bulletDescSize = (10.0 * sizeScale).clamp(
                          8.0,
                          13.0,
                        );
                        final bulletSpacing = (7.0 * sizeScale).clamp(
                          5.0,
                          10.0,
                        );
                        final ctaFontSize = (12.0 * sizeScale).clamp(
                          10.0,
                          14.0,
                        );
                        final ctaIconSize = (11.0 * sizeScale).clamp(9.0, 13.0);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 🔧 FIX: title + bullets used to be a fixed-size Column that
                            // could be taller than the space actually left inside this
                            // fixed-height card once the "Style Me" button below also
                            // claimed its share — that produced a bottom overflow. Wrapping
                            // it in Expanded + FittedBox(scaleDown) lets it take exactly the
                            // remaining space above the button, shrinking uniformly only if
                            // it doesn't fit, and never overflowing.
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${AppLocalizations.t(context, 'hero_card_title_main')}\n${AppLocalizations.t(context, 'hero_card_title_subtitle')}',
                                      style: TextStyle(
                                        color: _textHeading,
                                        fontSize: titleFontSize,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    SizedBox(height: bulletSpacing + 2),
                                    // 🆕 Dynamic bullet points from context with responsive sizing
                                    _buildStyleCardBullet(
                                      icon: Icons.eco_outlined,
                                      color: const Color(0xFF6B9AD4),
                                      label: _workoutLabel,
                                      desc: AppLocalizations.t(
                                        context,
                                        'hero_card_bullet_wear',
                                      ),
                                      labelFontSize: bulletLabelSize,
                                      descFontSize: bulletDescSize,
                                    ),
                                    SizedBox(height: bulletSpacing),
                                    _buildStyleCardBullet(
                                      icon: Icons.cloud_outlined,
                                      color: const Color(0xFF7BBFDA),
                                      // 🆕 FIX: Only show temperature, don't append translation key
                                      // Weather description is shown in the desc field below
                                      label:
                                          w.tempCelsius != null &&
                                              w.tempCelsius! > 0
                                          ? '${w.tempCelsius!.toStringAsFixed(0)}°'
                                          : '28°',
                                      desc: AppLocalizations.t(
                                        context,
                                        'hero_card_bullet_weather',
                                      ),
                                      labelFontSize: bulletLabelSize,
                                      descFontSize: bulletDescSize,
                                    ),
                                    SizedBox(height: bulletSpacing),
                                    _buildStyleCardBullet(
                                      icon: Icons.favorite_border_rounded,
                                      color: const Color(0xFFD4A0C8),
                                      label:
                                          'You tend to love ${_wardrobeSignal.favoriteStyle}',
                                      desc: AppLocalizations.t(
                                        context,
                                        'hero_card_bullet_style',
                                      ),
                                      labelFontSize: bulletLabelSize,
                                      descFontSize: bulletDescSize,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(
                              height: 8,
                            ), // 🆕 More space before button
                            _AnimatedPressable(
                              liftY: -3.0,
                              scalePressed: 0.93,
                              onTap: () => _openModuleChat('style'),
                              child: Container(
                                key: const ValueKey('home-style-me-cta'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  // 🆕 ENHANCED: Stronger gradient for better visibility
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [_accent, _accentSecondary],
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accent.withOpacity(0.45),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                    BoxShadow(
                                      color: _accent.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      AppLocalizations.t(
                                        context,
                                        'cta_style_me',
                                      ),
                                      style: TextStyle(
                                        color: _onAccent,
                                        fontSize: ctaFontSize,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // 🆕 Animated arrow for better UX
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      color: _onAccent,
                                      size: ctaIconSize,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 🆕 Helper widget to display image with dominant color background
  /// Extracts the dominant color from the image and uses it to fill empty space
  /// around the portrait image, creating a seamless blend
  Widget _buildImageWithDominantColorBackground(String imagePath) {
    // 🆕 Use fixed background color for style card image area
    final backgroundColor = const Color(0xFFE6ECFC);

    return Container(
      // 🎨 Fixed background color fills entire image area
      // This creates seamless background when image uses BoxFit.contain
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Sharp image with BoxFit.contain — full outfit always visible
          // (never cropped). ShaderMask fades top/bottom edges so the
          // transition to the background color is smooth and seamless.
          Center(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, 0.12, 0.88, 1.0],
              ).createShader(rect),
              child: Image.asset(
                imagePath,
                fit: BoxFit
                    .contain, // ← Never crops — full outfit always visible
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🆕 Helper widget for style card bullets
  Widget _buildStyleCardBullet({
    required IconData icon,
    required Color color,
    required String label,
    required String desc,
    double labelFontSize = 11.0,
    double descFontSize = 9.5,
  }) {
    // 🆕 RESPONSIVE ICON SIZE
    final screenW = MediaQuery.of(context).size.width;
    final iconBubbleSize = screenW < 360 ? 20.0 : 24.0;
    final iconSize = screenW < 360 ? 10.0 : 12.0;
    final spacing = screenW < 360 ? 8.0 : 10.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: iconBubbleSize,
          height: iconBubbleSize,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: iconSize, color: color),
        ),
        SizedBox(width: spacing),
        // 🔧 FIX: Removed Expanded — this Row receives unbounded width from
        // FittedBox (FittedBox always passes unconstrained constraints to its
        // child). Expanded inside a Row with unbounded width throws:
        //   "RenderFlex children have non-zero flex but incoming width is unbounded"
        // Inside FittedBox, text should take its natural (intrinsic) width;
        // FittedBox itself then scales the whole Column down to fit the card.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _textHeading,
                fontSize: labelFontSize,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              desc,
              style: TextStyle(
                color: _textMuted,
                fontSize: descFontSize,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Routine cards section: Wear / Move / Eat / Care / Medicine ───────────

  Widget _buildRoutineCardsSection() {
    // Repaint all five cards whenever the merged summary provider notifies
    // (Care/Medicine/etc push updates through it).
    context.watch<HomeCardSummaryProvider>();

    // 🆕 DYNAMIC DATA FROM PROVIDERS & SERVICES
    // Each routine syncs with real app data
    final routines =
        <
          ({
            IconData icon,
            Color color,
            String label,
            String desc,
            String status,
            bool done,
            Widget page,
          })
        >[
          (
            // 🔧 FIX: Icons.checkroom_outlined was rendering as the same running-
            // figure glyph as the "Move" card below (icon font/tree-shaking
            // mismatch). Icons.dry_cleaning_outlined is the same hanger icon
            // already used (and confirmed working) for the Wardrobe nav tab.
            icon: Icons.dry_cleaning_outlined,
            color: const Color(0xFF6B8FD4),
            label: AppLocalizations.t(context, 'routine_wear'),
            // 🔄 DYNAMIC: From DailyWearScreen/Wardrobe
            desc: _getDailyWearDescription(),
            status: _getDailyWearStatus(),
            done: _isDailyWearDone(),
            page: DailyWearScreen(),
          ),
          (
            icon: Icons.directions_run_rounded,
            color: const Color(0xFF5BBF8A),
            label: AppLocalizations.t(context, 'routine_move'),
            // 🔄 DYNAMIC: From WorkoutStudioScreen/Fitness
            desc: _getWorkoutDescription(),
            status: _getWorkoutStatus(),
            done: _isWorkoutDone(),
            page: WorkoutStudioScreen(fromHome: true),
          ),
          (
            icon: Icons.restaurant_outlined,
            color: const Color(0xFFE8895A),
            label: AppLocalizations.t(context, 'routine_eat'),
            // 🔄 DYNAMIC: From MainScreen/Diet
            desc: _getMealDescription(),
            status: _getMealStatus(),
            done: _isMealDone(),
            page: MainScreen(fromHome: true),
          ),
          (
            icon: Icons.spa_outlined,
            color: const Color(0xFFB07FD4),
            label: AppLocalizations.t(context, 'routine_care'),
            // 🔄 DYNAMIC: From SkincareScreen
            desc: _getSkincareDescription(),
            status: _getSkincareStatus(),
            done: _isSkincareDone(),
            page: SkincareScreen(),
          ),
          (
            icon: Icons.medication_outlined,
            color: const Color(0xFFE88A8A),
            label: AppLocalizations.t(context, 'routine_medicine'),
            // 🔄 DYNAMIC: From MediTrackScreen
            desc: _getMedicineDescription(),
            status: _getMedicineStatus(),
            done: _isMedicineDone(),
            page: MediTrackScreen(fromHome: true),
          ),
        ];

    final palette = HomeRoutinePalette(
      accent: _accent,
      border: _border,
      cardColor: _bgSecondary.withOpacity(0.7),
      textHeading: _textHeading,
      textMuted: _textMuted,
      onAccent: _onAccent,
    );

    final cards = <HomeRoutineCardData>[
      for (int i = 0; i < routines.length; i++)
        () {
          final r = routines[i];
          final overdue =
              r.page is MediTrackScreen && r.status.toLowerCase().contains('overdue');
          return HomeRoutineCardData(
            icon: r.icon,
            color: r.color,
            label: r.label,
            primary: r.desc,
            context: r.status,
            stateLabel: '',
            cta: r.label,
            done: r.done,
            overdue: overdue,
            onOpen: () {
              if (r.page is MediTrackScreen) {
                debugPrint('AHVI_MEDI_NAV source=home_routine');
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => r.page),
              );
            },
          );
        }(),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border.withOpacity(0.50), width: 1),
        boxShadow: [
          BoxShadow(
            color: _shadowLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: HomeRoutineCarousel(
        cards: cards,
        palette: palette,
      ),
    );
  }

  // ── Prep & Plan card ──────────────────────────────────────────────────────

  // 🆕 IMPROVED PREP & PLAN CARD - 30% Text | 70% Image (No Fade Effects)
  Widget _buildPrepPlanCard({double? screenH}) {
    final content = _prepCardContent();
    final accentColor = context.themeTokens.accent.primary;
    final accentTertiary = context.themeTokens.accent.tertiary;

    // 🆕 Gender-aware backdrop photo — same live-resolution pattern as the
    // Style/Hero card (_buildHeroCard): watch ProfileController so this card
    // rebuilds and re-resolves gender any time the profile actually changes,
    // not just once at app start. Only 2 images total, no generic/neutral
    // fallback — whichever gender _resolveGenderFromProfile lands on is
    // used, defaulting to 'women' via _userGender until the profile loads.
    final liveProfileState = context.watch<profile.ProfileController>().state;
    final resolvedGender = _resolveGenderFromProfile(liveProfileState);
    final genderedPrepPlanAsset = resolvedGender == 'men'
        ? 'assets/images/plan_card_men.jpg'
        : 'assets/images/plan_card_women.jpg';

    // 🆕 FIX: The card is no longer wrapped in a card-wide _CardPressable/
    // onTap. Previously the entire card navigated to chat on tap, which
    // conflicted with (and made redundant/confusing) the dedicated "Plan
    // Week" CTA button below, which has its own onTap. Now only that button
    // opens the chat sheet — tapping elsewhere on the card does nothing.
    return Container(
      width: double.infinity,
      // Fill parent height — the parent is an Expanded widget so this
      // stretches the card to consume whatever space is left above the
      // prompt bar, eliminating the dead gap visible in the screenshot.
      height: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: _shadowLight,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(color: accentColor.withOpacity(0.06), blurRadius: 12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        // .stretch forces both the text column and the image to fill the
        // card's full height on every screen size.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 35% LEFT: TEXT CONTENT ────────────────────────────────────
          Expanded(
            flex: 35,
            child: LayoutBuilder(
              builder: (context, cc) {
                final colW = cc.maxWidth;
                final hPad = colW < 90 ? 8.0 : 10.0;
                return Padding(
                  padding: EdgeInsets.only(
                    left: hPad,
                    right: 4,
                    top: 7,
                    bottom: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Text block yields first on a short card — the CTA
                      // button below stays fully visible, never overflows.
                      Flexible(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              AppLocalizations.t(context, 'prep_card_title'),
                              style: TextStyle(
                                color: _textHeading,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            AppLocalizations.t(context, 'prep_card_subtitle'),
                            style: TextStyle(
                              color: _textMuted,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          // Flexible + LayoutBuilder — on a short card this
                          // hides cleanly once there's no room for even one
                          // full line, instead of painting a clipped sliver.
                          Flexible(
                            child: LayoutBuilder(
                              builder: (context, descConstraints) {
                                const oneLineHeight = 9.0 * 1.15;
                                if (descConstraints.maxHeight <
                                    oneLineHeight) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  AppLocalizations.t(context, 'prep_card_desc'),
                                  style: TextStyle(
                                    // 🆕 Blended a bit toward _textHeading (from plain
                                    // _textMuted) + bumped size/weight so the subtitle
                                    // is clearly legible instead of fading into the
                                    // background, while staying visually secondary
                                    // to the "Prep & Plan" title above it.
                                    color: Color.lerp(
                                      _textMuted,
                                      _textHeading,
                                      0.35,
                                    ),
                                    fontSize:
                                        9.0, // 🔧 Reduced from 9.5 to fit better
                                    fontWeight: FontWeight.w500,
                                    height:
                                        1.15, // 🔧 Reduced line height from 1.2
                                  ),
                                  // 🔧 FIX: Back to maxLines: 2 to prevent overflow
                                  // This shows key info without bottom overflow
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                );
                              },
                            ),
                          ),
                        ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        enabled: true,
                        label: 'Prepare and plan: ${content.cta}',
                        child: _AnimatedPressable(
                          liftY: -2.0,
                          scalePressed: 0.95,
                          // "Prep & Plan" opens the planner module with a
                          // clean composer — no seeded/auto-sent message, so
                          // the user's first typed request is the real one.
                          // The adaptive meal/workout/weekly recommendation
                          // still rides along as non-routing context_hint so
                          // backend routing is decided by the explicit
                          // module, never by keywords in the recommendation
                          // text (which would deflect to Diet/Fitness/Calendar).
                          onTap: () {
                            final req = prepPlanCardRequest(content.prompt);
                            showAhviStylistChatSheet(
                              context,
                              moduleContext: req.module,
                              contextData: req.context,
                            );
                          },
                          child: Container(
                            key: const ValueKey('home-prepare-cta'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [accentColor, accentTertiary],
                              ),
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.38),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    AppLocalizations.t(
                                      context,
                                      'prep_card_cta',
                                    ),
                                    style: TextStyle(
                                      color: _onAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 1),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: _onAccent,
                                  size: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 🆕 Explicit, balanced gap between the text column and the
          // weekly preview image (replaces the old implicit gap that was
          // just the leftover of two separate paddings on either side).
          const SizedBox(width: 8),

          // ── 65% RIGHT: OUTFIT/MEAL GRID PREVIEW OVER BACKDROP PHOTO ──────
          Expanded(
            flex: 65,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              // ═══════════════════════════════════════════════════════════════
              // 🔧 FIX: FULLY-VISIBLE IMAGE ON EVERY ASPECT RATIO
              // ═══════════════════════════════════════════════════════════════
              //
              // PROBLEM (previous approach):
              // ─────────────────────────────────────────────────────────────
              // This panel's own aspect ratio swings from ~1.8:1 on small
              // phones to ~4.3:1 on tablets, but the old code rendered a
              // single fixed-ratio (2.35:1) source image with
              // BoxFit.cover. BoxFit.cover always fills the box completely
              // by cropping whichever dimension overflows — so devices
              // near 2.35:1 looked fine, but anything far from that ratio
              // (small phones, tablets) cropped a real, visible chunk off
              // the sides or top/bottom. That's why the weekly plan photo
              // showed complete on some devices and clipped on others.
              //
              // FIX:
              // ─────────────────────────────────────────────────────────────
              // Two-layer Stack:
              //   1. A blurred copy of the image with BoxFit.cover fills
              //      the whole panel edge-to-edge on every aspect ratio —
              //      there is never a gap, on any device. It's blurred
              //      and decorative only, so cropping it is invisible.
              //   2. The real, sharp image sits on top with
              //      BoxFit.contain, which — unlike cover — NEVER crops:
              //      it scales the whole image down to fit within the
              //      panel and centers it. The complete weekly plan is
              //      always visible, on every screen size, full stop.
              // The blurred backdrop just means the contain-fitted image
              // never looks like it's floating on bare background when
              // its own aspect ratio doesn't match the panel's.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 🆕 BACKGROUND FILL: Card's surface color fills the entire
                  // image area on every device. This ensures NO empty/white
                  // space is visible when the image (using BoxFit.contain)
                  // doesn't cover the full panel area due to aspect ratio
                  // mismatch.
                  //
                  // ✅ BENEFITS:
                  // • Seamless look — empty space matches card background
                  // • Works on all aspect ratios (phones, tablets, etc.)
                  // • No visible gaps or different colored areas
                  // • Image appears to float naturally on the card surface
                  //
                  // 🛠️ PREVIOUS APPROACH (removed):
                  // Used a blurred, cover-fit copy of the image as backdrop.
                  // But TileMode.decal faded to transparent at edges,
                  // creating a ~25px darker band at top/bottom that showed
                  // as a visible seam. Removing that layer and using flat
                  // color fixes the seam at its source.
                  // 🆕 BACKGROUND FILL: Use consistent light blue color to fill
                  // empty space (left, right, top, bottom) when image uses
                  // BoxFit.contain on different aspect ratios.
                  Container(
                    color: const Color(
                      0xFFE6ECFC,
                    ), // 🎨 Light blue to fill empty space
                    // OPTIONAL: Uncomment for subtle visual depth
                    // decoration: BoxDecoration(
                    //   gradient: LinearGradient(
                    //     begin: Alignment.topRight,
                    //     end: Alignment.bottomLeft,
                    //     colors: [
                    //       const Color(0xFFE6ECFC),
                    //       const Color(0xFFE6ECFC).withOpacity(0.97),
                    //     ],
                    //   ),
                    // ),
                  ),
                  // Crisp image, fit:contain so the full week is always
                  // visible (never cropped). Its top/bottom edges are
                  // faded to transparent via ShaderMask so that even if a
                  // future image asset's edge color isn't a perfect match
                  // for `_surface`, the transition dissolves gradually
                  // instead of ending on a hard, visible line.
                  Center(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.08, 0.92, 1.0],
                      ).createShader(rect),
                      child: Image.asset(
                        genderedPrepPlanAsset,
                        fit: BoxFit
                            .contain, // ← Never crops — full image always visible
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🆕 SIMPLIFIED WEEK PREVIEW - Just icons, no fade effects
  // ── Dynamic card content ───────────────────────────────────────────────────
  // Style card and Prep & Plan card title/subtitle/cta driven by context.

  /// Returns {title, subtitle, cta, icon, prompt} for the Style card.
  _CardContent _styleCardContent() {
    final ctx = _recommendationCtx;
    final w = ctx.weather;
    final fit = ctx.fitness;
    final ward = ctx.wardrobe;

    // Priority order: upcoming event > weather > fitness > wardrobe > time-of-day

    // 📅 Upcoming occasion/meeting
    if (ctx.hasSoonOccasion) {
      final e = ctx.nextOccasion!;
      return _CardContent(
        title: AppLocalizations.t(context, 'style_occasion_title'),
        subtitle:
            '${e.title} in ${e.hoursUntil}h — ${AppLocalizations.t(context, 'style_occasion_subtitle')}',
        cta: AppLocalizations.t(context, 'style_occasion_cta'),
        icon: Icons.celebration_outlined,
        prompt:
            'I have "${e.title}" in ${e.hoursUntil} hours. Create the perfect occasion outfit.',
      );
    }
    if (ctx.hasSoonMeeting) {
      final e = ctx.nextMeeting!;
      return _CardContent(
        title: AppLocalizations.t(context, 'style_meeting_title'),
        subtitle:
            '"${e.title}" in ${e.hoursUntil}h — ${AppLocalizations.t(context, 'style_meeting_subtitle')}',
        cta: AppLocalizations.t(context, 'style_meeting_cta'),
        icon: Icons.work_outline_rounded,
        prompt:
            'I have a meeting "${e.title}" in ${e.hoursUntil} hours. Suggest a sharp professional outfit.',
      );
    }

    // 🌦️ Weather-driven
    if (w.isRainy) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_rainy_title'),
        subtitle: AppLocalizations.t(context, 'style_rainy_subtitle'),
        cta: AppLocalizations.t(context, 'style_rainy_cta'),
        icon: Icons.umbrella_outlined,
        prompt: 'It\'s raining today. Suggest a stylish waterproof outfit.',
      );
    }
    if (w.isCold && w.tempLabel.isNotEmpty) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_cold_title'),
        subtitle:
            '${w.tempLabel} ${AppLocalizations.t(context, 'style_cold_subtitle')}',
        cta: AppLocalizations.t(context, 'style_cold_cta'),
        icon: Icons.ac_unit_outlined,
        prompt: 'It\'s ${w.tempLabel} today. Suggest a warm layered outfit.',
      );
    }
    if (w.isHot && w.tempLabel.isNotEmpty) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_hot_title'),
        subtitle:
            '${w.tempLabel} ${AppLocalizations.t(context, 'style_hot_subtitle')}',
        cta: AppLocalizations.t(context, 'style_hot_cta'),
        icon: Icons.wb_sunny_outlined,
        prompt: 'It\'s ${w.tempLabel} today. Suggest a cool breathable outfit.',
      );
    }

    // 🏃 Fitness-driven
    if (fit.nextWorkoutLabel.isNotEmpty && ctx.isMorning) {
      return _CardContent(
        title:
            '${fit.nextWorkoutLabel} ${AppLocalizations.t(context, 'style_gym_title_suffix')}',
        subtitle: AppLocalizations.t(context, 'style_gym_subtitle'),
        cta: AppLocalizations.t(context, 'style_gym_cta'),
        icon: Icons.fitness_center_outlined,
        prompt:
            'Today is my ${fit.nextWorkoutLabel} day. Suggest a stylish gym outfit.',
      );
    }
    if (fit.hasActiveStreak && ctx.isMorning) {
      return _CardContent(
        title:
            '${fit.workoutStreakDays}-${AppLocalizations.t(context, 'style_streak_title_suffix')}',
        subtitle: AppLocalizations.t(context, 'style_streak_subtitle'),
        cta: AppLocalizations.t(context, 'style_streak_cta'),
        icon: Icons.local_fire_department_outlined,
        prompt:
            'I\'m on a ${fit.workoutStreakDays}-day fitness streak. Suggest a motivating outfit for today.',
      );
    }

    // 👗 Wardrobe-driven
    if (ward.hasUnwornItems && ward.unwornItems >= 3) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_wardrobe_title'),
        subtitle:
            '${ward.unwornItems} ${AppLocalizations.t(context, 'style_wardrobe_subtitle')}',
        cta: AppLocalizations.t(context, 'style_wardrobe_cta'),
        icon: Icons.dry_cleaning_outlined,
        prompt:
            'I have ${ward.unwornItems} clothing items I\'ve never worn. Build fresh outfits using them.',
      );
    }
    if (ward.favoriteStyle.isNotEmpty) {
      return _CardContent(
        title:
            '${ward.favoriteStyle.capitalize()} ${AppLocalizations.t(context, 'style_fav_title_suffix')}',
        subtitle: AppLocalizations.t(context, 'style_fav_subtitle'),
        cta: AppLocalizations.t(context, 'style_fav_cta'),
        icon: Icons.favorite_outline_rounded,
        prompt:
            'Show me new ${ward.favoriteStyle} fashion picks that match my style preferences.',
      );
    }

    // 📅 Time-of-day fallbacks
    if (ctx.isMondayMorning) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_week_title'),
        subtitle: AppLocalizations.t(context, 'style_week_subtitle'),
        cta: AppLocalizations.t(context, 'style_week_cta'),
        icon: Icons.date_range_outlined,
        prompt: 'Plan 5 complete outfits for my work week ahead.',
      );
    }
    if (ctx.isFridayEvening) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_friday_title'),
        subtitle: AppLocalizations.t(context, 'style_friday_subtitle'),
        cta: AppLocalizations.t(context, 'style_friday_cta'),
        icon: Icons.nightlife_outlined,
        prompt: 'Help me pick a stylish evening outfit for Friday night.',
      );
    }
    if (ctx.isWeekend) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_weekend_title'),
        subtitle: AppLocalizations.t(context, 'style_weekend_subtitle'),
        cta: AppLocalizations.t(context, 'style_weekend_cta'),
        icon: Icons.weekend_outlined,
        prompt: 'Suggest a relaxed yet stylish casual outfit for the weekend.',
      );
    }
    if (ctx.isEvening) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_evening_title'),
        subtitle: AppLocalizations.t(context, 'style_evening_subtitle'),
        cta: AppLocalizations.t(context, 'style_evening_cta'),
        icon: Icons.spa_outlined,
        prompt: 'Build me an evening outfit and skincare routine.',
      );
    }
    if (ctx.isMorning) {
      return _CardContent(
        title: AppLocalizations.t(context, 'style_card_title'),
        subtitle: _userName.isNotEmpty
            ? '${AppLocalizations.t(context, 'greeting_morning')}, $_userName! ${AppLocalizations.t(context, 'style_morning_plan')}'
            : AppLocalizations.t(context, 'style_morning_subtitle_default'),
        cta: AppLocalizations.t(context, 'style_morning_cta'),
        icon: Icons.auto_awesome_rounded,
        prompt: 'Plan a complete outfit for me today.',
      );
    }

    // Default
    return _CardContent(
      title: AppLocalizations.t(context, 'style_default_title'),
      subtitle: AppLocalizations.t(context, 'style_default_subtitle'),
      cta: AppLocalizations.t(context, 'style_default_cta'),
      icon: Icons.auto_awesome_rounded,
      prompt:
          'Surprise me with a complete outfit based on my style preferences.',
    );
  }

  /// Returns {title, subtitle, cta, icon, prompt} for the Prep & Plan card.
  _CardContent _prepCardContent() {
    final ctx = _recommendationCtx;
    final fit = ctx.fitness;

    // Priority: upcoming event > Sunday > Monday > fitness meal > wardrobe > time

    // 📅 Upcoming occasion — prep checklist
    if (ctx.hasSoonOccasion) {
      final e = ctx.nextOccasion!;
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_event_title'),
        subtitle:
            '"${e.title}" in ${e.hoursUntil}h — ${AppLocalizations.t(context, 'prep_event_subtitle')}',
        cta: AppLocalizations.t(context, 'prep_event_cta'),
        icon: Icons.checklist_rounded,
        prompt:
            'Create a complete prep checklist for my upcoming event: "${e.title}".',
      );
    }

    // 📅 Travel today
    if (ctx.upcomingEvents.any(
      (e) => e.type == _EventType.travel && e.isToday,
    )) {
      final e = ctx.upcomingEvents.firstWhere(
        (e) => e.type == _EventType.travel && e.isToday,
      );
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_travel_title'),
        subtitle: AppLocalizations.t(context, 'prep_travel_subtitle'),
        cta: AppLocalizations.t(context, 'prep_travel_cta'),
        icon: Icons.flight_outlined,
        prompt:
            'Create a travel packing checklist and outfit plan for my trip today: "${e.title}".',
      );
    }

    // 📅 Sunday — weekly prep
    if (ctx.isSunday) {
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_sunday_title'),
        subtitle: AppLocalizations.t(context, 'prep_sunday_subtitle'),
        cta: AppLocalizations.t(context, 'prep_sunday_cta'),
        icon: Icons.event_available_outlined,
        prompt:
            'Help me do a complete Sunday prep: weekly meal plan, outfit planning, and goal setting.',
      );
    }

    // 📅 Monday — weekly kickoff
    if (ctx.isMondayMorning) {
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_monday_title'),
        subtitle: AppLocalizations.t(context, 'prep_monday_subtitle'),
        cta: AppLocalizations.t(context, 'prep_monday_cta'),
        icon: Icons.rocket_launch_outlined,
        prompt: 'Help me plan my week: schedule, meals, and daily outfits.',
      );
    }

    // 🏃 Meal plan needed
    if (fit.mealPlanNeeded && (ctx.isAfternoon || ctx.isEvening)) {
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_meal_title'),
        subtitle: AppLocalizations.t(context, 'prep_meal_subtitle'),
        cta: AppLocalizations.t(context, 'prep_meal_cta'),
        icon: Icons.restaurant_outlined,
        prompt:
            'I haven\'t met my calorie goal today. Suggest healthy meals I can prepare now.',
      );
    }

    // 🏃 Workout plan
    if (fit.nextWorkoutLabel.isNotEmpty) {
      return _CardContent(
        title: fit.nextWorkoutLabel.isNotEmpty
            ? '${fit.nextWorkoutLabel} ${AppLocalizations.t(context, 'prep_workout_title_suffix')}'
            : AppLocalizations.t(context, 'prep_workout_title_default'),
        subtitle: AppLocalizations.t(context, 'prep_workout_subtitle'),
        cta: AppLocalizations.t(context, 'prep_workout_cta'),
        icon: Icons.fitness_center_outlined,
        prompt:
            'Plan my ${fit.nextWorkoutLabel} workout: exercises, sets, nutrition, and gear.',
      );
    }

    // Time-of-day fallbacks
    if (ctx.isEvening) {
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_tomorrow_title'),
        subtitle: AppLocalizations.t(context, 'prep_tomorrow_subtitle'),
        cta: AppLocalizations.t(context, 'prep_tomorrow_cta'),
        icon: Icons.nights_stay_outlined,
        prompt: 'Help me prepare for tomorrow: outfit, schedule, and to-dos.',
      );
    }
    if (ctx.isMorning) {
      return _CardContent(
        title: AppLocalizations.t(context, 'prep_day_title'),
        subtitle: AppLocalizations.t(context, 'prep_day_subtitle'),
        cta: AppLocalizations.t(context, 'prep_day_cta'),
        icon: Icons.today_outlined,
        prompt: 'Help me plan today: meals, outfit, and schedule.',
      );
    }

    // Default
    return _CardContent(
      title: AppLocalizations.t(context, 'prep_default_title'),
      subtitle: AppLocalizations.t(context, 'prep_default_subtitle'),
      cta: AppLocalizations.t(context, 'prep_default_cta'),
      icon: Icons.grid_view_rounded,
      prompt: 'Help me plan and organise my wardrobe, meals, and schedule.',
    );
  }

  Widget _buildSectionHead() {
    final screenH = MediaQuery.of(context).size.height;
    const double topPad = 18.0;
    const double botPad = 12.0;
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: botPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.t(context, 'picks_section_title'), // 🆕
                style: TextStyle(
                  color: _textHeading,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _accent.withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: Text(
                  AppLocalizations.t(context, 'picks_ai_curated'), // 🆕
                  style: TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: _openSeeAll,
            child: Text(
              AppLocalizations.t(context, 'picks_see_all'), // 🆕
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicksStrip() {
    // 🆕 Picks localized
    final picks = [
      (
        AppLocalizations.t(context, 'pick_minimal_chic'),
        AppLocalizations.t(context, 'pick_minimal_chic_tag'),
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_street_edit'),
        AppLocalizations.t(context, 'pick_street_edit_tag'),
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_office_look'),
        AppLocalizations.t(context, 'pick_office_look_tag'),
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_evening'),
        AppLocalizations.t(context, 'pick_evening_tag'),
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
    ];
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    return SizedBox(
      height: isTablet
          ? (MediaQuery.of(context).size.height * 0.26).clamp(200.0, 280.0)
          : (MediaQuery.of(context).size.height * 0.22).clamp(150.0, 190.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: picks.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return _buildPickCard(
            cardIdx: i,
            name: picks[i].$1,
            tag: picks[i].$2,
            imageUrl: picks[i].$3,
            liked: _likedState[i],
          );
        },
      ),
    );
  }

  Widget _buildPickCard({
    required int cardIdx,
    required String name,
    required String tag,
    required String imageUrl,
    required bool liked,
  }) {
    // Responsive card width: tablet=22%, phone=28%, clamped per form factor
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    final cardW = isTablet
        ? (screenW * 0.18).clamp(140.0, 200.0)
        : (screenW * 0.28).clamp(88.0, 130.0);
    return _AnimatedPressable(
      liftY: -4.0,
      scaleHover: 1.03,
      scalePressed: 0.97,
      onTap: () => _openPickSheet(name, tag),
      child: Container(
        width: cardW,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_surface, _bgSecondary],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 1),
          boxShadow: [
            BoxShadow(
              color: _shadowMedium,
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
            BoxShadow(color: _shadowLight, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth:
                          (112 * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_ctx, _err, _st) => Container(
                        color: _accent.withOpacity(0.1),
                        child: Icon(Icons.image, color: _textMuted),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildLikeButton(cardIdx, liked),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _textHeading,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tag,
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w300,
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

  Widget _buildLikeButton(int cardIdx, bool liked) {
    return AnimatedBuilder(
      animation: _heartPopCtrls[cardIdx],
      builder: (context, _) {
        final t = _heartPopCtrls[cardIdx].value;
        double scale = 1.0;
        if (t < 0.40) {
          scale = 1.0 + (0.38 * (t / 0.40));
        } else if (t < 0.70) {
          scale = 1.38 - (0.50 * ((t - 0.40) / 0.30));
        } else {
          scale = 0.88 + (0.12 * ((t - 0.70) / 0.30));
        }
        return GestureDetector(
          onTap: () => _toggleLike(cardIdx),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: liked ? _accent.withOpacity(0.20) : _shadowStrong,
                border: liked
                    ? Border.all(color: _accent.withOpacity(0.50), width: 1)
                    : null,
              ),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? _accentSecondary : _textHeading.withOpacity(0.7),
                size: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatWrap() {
    return AhviChatPromptBar(
      controller: _chatController,
      focusNode: _chatFocusNode,
      hintText: _chatPlaceholder,
      hasTextListenable: _chatController,
      surface: _surface,
      border: _border,
      accent: _accent,
      accentSecondary: _accentSecondary,
      textHeading: _textHeading,
      textMuted: _textMuted,
      shadowMedium: _shadowMedium,
      onAccent: _onAccent,
      onVoiceTap: _toggleListening,
      isListening: _isListening,
      // onPlusTap not set — widget opens lens sheet using its own Builder context
      padding: EdgeInsets.zero,
      onSendMessage: (text) {
        _chatFocusNode.unfocus();
        _openChatWithPrompt(text);
      },
      themeTokens: _t,
      // null -> canonical _runFindSimilarFlow default, same as Style Me's "+".
      onVisualSearch: null,
      onFindSimilar: null,
      onAddToWardrobe:
          null, // uses showAddToWardrobeModal default in lens sheet
    );
  }

  // ── ChatGPT-style plus menu ───────────────────────────────────────────────
  Widget _buildPlusMenu() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Position it just above the chat bar
    final menuBottom = safeBottom + 86.0 + 60.0 + 8.0; // 60px prompt bar height

    final menuItems = [
      (
        Icons.camera_alt_outlined,
        AppLocalizations.t(context, 'plus_menu_camera'),
        AppLocalizations.t(context, 'plus_menu_camera_sub'),
      ),
      (
        Icons.photo_library_outlined,
        AppLocalizations.t(context, 'plus_menu_gallery'),
        AppLocalizations.t(context, 'plus_menu_gallery_sub'),
      ),
      (
        Icons.insert_drive_file_outlined,
        AppLocalizations.t(context, 'plus_menu_files'),
        AppLocalizations.t(context, 'plus_menu_files_sub'),
      ),
      (
        Icons.browse_gallery_outlined,
        AppLocalizations.t(context, 'plus_menu_browse'),
        AppLocalizations.t(context, 'plus_menu_browse_sub'),
      ),
    ];

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closePlusMenu,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned(
              left: 20,
              bottom: menuBottom,
              child: AnimatedBuilder(
                animation: _plusMenuCtrl,
                builder: (context, _) {
                  final t = _plusMenuCtrl.value;
                  return Transform.translate(
                    offset: Offset(0, 16 * (1 - t)),
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: GestureDetector(
                        onTap: () {}, // prevent tap-through
                        child: Container(
                          width: 220,
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _accent.withOpacity(0.18),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _bgPrimary.withOpacity(0.40),
                                blurRadius: 32,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: _accent.withOpacity(0.08),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(menuItems.length, (i) {
                              final item = menuItems[i];
                              final isLast = i == menuItems.length - 1;
                              return _PlusMenuItem(
                                icon: item.$1,
                                title: item.$2,
                                subtitle: item.$3,
                                accent: _accent,
                                accentSecondary: _accentSecondary,
                                textHeading: _textHeading,
                                textMuted: _textMuted,
                                panel: _panel,
                                border: _border,
                                showDivider: !isLast,
                                delayT: (i * 0.06).clamp(0.0, 0.3),
                                animT: t,
                                onTap: () {
                                  _closePlusMenu();
                                  _showComingSoon();
                                },
                              );
                            }),
                          ),
                        ),
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

  Widget _buildBottomNav() {
    // 🆕 Nav labels localized from constant keys defined at top of file
    final navLabelKeys = _homeNavKeys;
    final items = _homeNavItems;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    const double pillH =
        64.0; // ✏️ Increased from 50.0 — taller nav bar, icons less cramped
    const double maxBulge = 14.0; // ✏️ Increased from 8.0
    const double totalH = pillH + maxBulge + 0.0; // totalH = 78px (was 58px)
    const double iconContainerSize = 32.0; // ✏️ Reduced from 36.0
    const double iconSize = 16.0; // ✏️ Reduced from 18.0

    // On tablet, constrain nav to a max width and center it
    final navMaxW = isTablet ? 480.0 : double.infinity;

    return SizedBox(
      height: totalH,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: navMaxW),
          child: AnimatedBuilder(
            animation: Listenable.merge(_navRiseCtrls),
            builder: (context, _) {
              final activeIdx = _activeNavIdx;
              final bulgeT = _navRiseCtrls[activeIdx].value;

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: totalH,
                    child: CustomPaint(
                      painter: _NavPillPainter(
                        activeIdx: activeIdx,
                        itemCount: items.length,
                        bulgeT: bulgeT,
                        pillH: pillH,
                        maxBulge: maxBulge,
                        fillColor: _surface,
                        borderColor: _border,
                        glowColor: _accent,
                        shadowColor: _shadowMedium,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: pillH,
                    child: Row(
                      children: List.generate(items.length, (i) {
                        final active = activeIdx == i;
                        final rise = -10.0 * _navRiseCtrls[i].value;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _handleNavTap(i),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, rise),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    width: iconContainerSize,
                                    height: iconContainerSize,
                                    decoration: active
                                        ? BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: _accentGradient2,
                                            boxShadow: [
                                              BoxShadow(
                                                color: _accent.withOpacity(
                                                  0.45,
                                                ),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4),
                                              ),
                                              BoxShadow(
                                                color: _accent.withOpacity(
                                                  0.25,
                                                ),
                                                blurRadius: 28,
                                              ),
                                            ],
                                          )
                                        : null,
                                    child: Icon(
                                      items[i].icon,
                                      color: active ? _onAccent : _textMuted,
                                      size: active ? iconSize + 1 : iconSize,
                                    ),
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(0, rise),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    style: TextStyle(
                                      color: active ? _textHeading : _textMuted,
                                      fontSize: 8,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      letterSpacing: -0.01,
                                    ),
                                    // 🆕 label localized
                                    child: Text(
                                      AppLocalizations.t(
                                        context,
                                        navLabelKeys[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiOverlay() {
    final screenH = MediaQuery.of(context).size.height;
    final bottomClearance = (screenH * 0.20).clamp(140.0, 190.0);
    final overlayTopOffset = (screenH * 0.072).clamp(50.0, 72.0);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _overlayFadeCtrl,
        builder: (context, _) => Opacity(
          opacity: _overlayFadeCtrl.value,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismissOverlay,
                  child: Container(color: _bgPrimary.withOpacity(0.92)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomClearance,
                child: IgnorePointer(child: const SizedBox.expand()),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: overlayTopOffset,
                bottom: bottomClearance,
                child: Column(
                  children: [
                    Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (b) =>
                              _accentGradient.createShader(b),
                          child: Text(
                            'AHVI',
                            style: TextStyle(
                              fontFamily: 'Anton',
                              color: _textHeading,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // 🆕 brandSub ఇప్పుడు key — translate చేస్తున్నాం
                          AppLocalizations.t(context, _overlayBrandSub),
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _overlayScrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _EntryFadeSlide(
                          key: ValueKey(
                            '${_overlayState}_${_activeIntent ?? ''}',
                          ),
                          child: _buildOverlayContent(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent() {
    switch (_overlayState) {
      case _OverlayState.suggestions:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.t(context, 'overlay_suggested_for_you'), // 🆕
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 8),
            ..._overlaySuggestions.map(
              (q) => _AnimatedPressable(
                scalePressed: 0.97,
                // 🆕 q ఇప్పుడు key — translate చేసి API కి పంపుతున్నాం
                onTap: () => _handleQuery(
                  AppLocalizations.t(context, q),
                  _activeIntent ?? 'chat',
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: _surface.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(color: _shadowMedium, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          AppLocalizations.t(context, q), // 🆕 translated
                          style: TextStyle(
                            color: _textSub,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case _OverlayState.thinking:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _accent.withOpacity(0.18),
                      _accentSecondary.withOpacity(0.28),
                    ],
                  ),
                  border: Border.all(color: _accent.withOpacity(0.30)),
                ),
                child: Center(
                  child: ShaderMask(
                    shaderCallback: (b) => _accentGradient.createShader(b),
                    child: Icon(
                      Icons.auto_awesome,
                      color: _textHeading,
                      size: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _thinkingCtrl,
                builder: (_, __) {
                  Widget dot(int i) {
                    const period = 1.0;
                    const phaseShift = 0.125;
                    final t = (_thinkingCtrl.value + i * phaseShift) % period;
                    final sine = math.sin(t * math.pi * 2);
                    final lift = sine > 0 ? sine : 0.0;
                    final dy = -5.0 * lift;
                    final opacity = 0.3 + 0.7 * lift;
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 5.0 : 0),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Opacity(
                          opacity: opacity.clamp(0.3, 1.0),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _accentGradient,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: _surface.withOpacity(0.90),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _accent.withOpacity(0.20)),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.10),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [dot(0), dot(1), dot(2)],
                    ),
                  );
                },
              ),
            ],
          ),
        );

      case _OverlayState.response:
        if (_responses.isEmpty) return const SizedBox();
        return Column(
          children: _responses.map((resp) {
            final isLast = resp == _responses.last;
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildResponseContent(
                resp,
                showTags: isLast && _tagsRevealed,
              ),
            );
          }).toList(),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildResponseContent(_ResponseData resp, {bool showTags = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: _phoneShell,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: _accent.withOpacity(0.15)),
            ),
            child: Text(
              resp.question,
              style: TextStyle(
                color: _textHeading,
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _accent.withOpacity(0.18),
                    _accentSecondary.withOpacity(0.28),
                  ],
                ),
                border: Border.all(color: _accent.withOpacity(0.30)),
              ),
              child: Center(
                child: ShaderMask(
                  shaderCallback: (b) => _accentGradient.createShader(b),
                  child: Icon(
                    Icons.auto_awesome,
                    color: _textHeading,
                    size: 10,
                  ),
                ),
              ),
            ),
            Text(
              'AHVI',
              style: TextStyle(
                fontFamily: 'Anton',
                color: _textHeading,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (resp.intro.isNotEmpty) ...[
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 40,
            ),
            child: Text(
              resp.intro,
              style: TextStyle(
                color: _textSub,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _buildResponseBody(resp),

        if (showTags) ...[
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _tagsRevealCtrl,
            builder: (_, __) => Opacity(
              opacity: _tagsRevealCtrl.value,
              child: Transform.translate(
                offset: Offset(0, 7 * (1 - _tagsRevealCtrl.value)),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _responseTags
                      .map(
                        (tag) => _AnimatedPressable(
                          scalePressed: 0.96,
                          liftY: -1.5,
                          // 🆕 tag key translate చేసి submit చేస్తున్నాం
                          onTap: () =>
                              _submitQuery(AppLocalizations.t(context, tag)),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width - 60,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: _accent.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              AppLocalizations.t(context, tag), // 🆕 translated
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildResponseBody(_ResponseData resp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (resp.type) {
      case 'outfits':
        final outfitCardW = (MediaQuery.of(context).size.width * 0.22).clamp(
          76.0,
          96.0,
        );
        final outfitStripH = (MediaQuery.of(context).size.height * 0.185).clamp(
          138.0,
          168.0,
        );
        return SizedBox(
          height: outfitStripH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: resp.outfits.length,
            separatorBuilder: (_, i2) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final o = resp.outfits[i];
              return Container(
                width: outfitCardW,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: outfitStripH * 0.62,
                      child: Image.network(
                        o.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        cacheWidth:
                            (outfitCardW *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        cacheHeight:
                            (outfitStripH *
                                    0.62 *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_ctx, _err, _st) =>
                            Container(color: _accent.withOpacity(0.1)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name,
                            style: TextStyle(
                              color: isDark ? _textHeading : _tileText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 3,
                            children: o.tags
                                .map(
                                  (t) => Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 70,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _accent.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      t,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _textMuted,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );

      case 'tasks':
        return Column(
          children: resp.tasks.map((t) {
            final dotColor = t.priority == 'high'
                ? _accent
                : t.priority == 'mid'
                ? _accentSecondary
                : _accentTertiary.withOpacity(0.5);
            return Opacity(
              opacity: t.done ? 0.45 : 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _border.withOpacity(0.35)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: t.done
                              ? _accentTertiary.withOpacity(0.5)
                              : _accent.withOpacity(0.3),
                        ),
                        color: t.done
                            ? _accentTertiary.withOpacity(0.15)
                            : _transparent,
                      ),
                      child: t.done
                          ? Icon(Icons.check, color: _accentTertiary, size: 10)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.label,
                            style: TextStyle(
                              color: t.done ? _textMuted : _textHeading,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: t.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.due,
                            style: TextStyle(
                              color: t.priority == 'high'
                                  ? _accentTertiary
                                  : _textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case 'week':
        return LayoutBuilder(
          builder: (context, constraints) {
            final itemCount = resp.weekDays.length;
            // 🔧 IMPROVED: Use fewer columns on small screens
            final crossAxisCount = constraints.maxWidth < 360 ? 5 : 7;
            final cellSpacing = constraints.maxWidth < 340 ? 3.0 : 4.0;
            final aspectRatio = constraints.maxWidth < 360 ? 0.55 : 0.52;

            final rows = ((itemCount / crossAxisCount).ceil()).clamp(1, 6);
            final cellWidth =
                (constraints.maxWidth - ((crossAxisCount - 1) * cellSpacing)) /
                crossAxisCount;
            final cellHeight = cellWidth / aspectRatio;
            final gridHeight = (rows * cellHeight) + ((rows - 1) * cellSpacing);

            return SizedBox(
              height: gridHeight,
              child: GridView.builder(
                itemCount: itemCount,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: cellSpacing,
                  mainAxisSpacing: cellSpacing,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (_, index) {
                  final d = resp.weekDays[index];
                  // 🔧 IMPROVED: Responsive text sizing in grid
                  final dayLabelSize = constraints.maxWidth < 360 ? 8.0 : 7.5;
                  final dateLabelSize = constraints.maxWidth < 360 ? 7.0 : 6.5;
                  final itemTextSize = constraints.maxWidth < 360 ? 6.0 : 5.5;

                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: d.isToday
                          ? _accent.withOpacity(0.10)
                          : _bgPrimary.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: d.isToday
                            ? _accent.withOpacity(0.25)
                            : _border.withOpacity(0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          d.day,
                          style: TextStyle(
                            fontSize: dayLabelSize,
                            fontWeight: FontWeight.w700,
                            color: d.isToday ? _accent : _textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          d.label.split(' ').last,
                          style: TextStyle(
                            fontSize: dateLabelSize,
                            color: _textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        ...d.items
                            .take(2)
                            .map(
                              (it) => Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  it,
                                  style: TextStyle(
                                    fontSize: itemTextSize,
                                    color: _textSub,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );

      case 'plan':
        return Column(
          children: resp.planSections.map((s) {
            final c = s.color(context.themeTokens);
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: TextStyle(
                      color: c,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...s.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        it,
                        style: TextStyle(
                          color: _textSub,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );

      case 'prepare_exact':
        return _buildPrepareExactChecklistCard(resp.question);

      case 'text':
      default:
        return const SizedBox();
    }
  }

  Widget _buildPrepareExactChecklistCard(String title) {
    final sections = [
      (
        name: AppLocalizations.t(context, 'checklist_section_documents'),
        emoji: '📄',
        color: _accentTertiary,
        items: [
          AppLocalizations.t(context, 'checklist_item_passport'),
          AppLocalizations.t(context, 'checklist_item_boarding_pass'),
          AppLocalizations.t(context, 'checklist_item_travel_insurance'),
          AppLocalizations.t(context, 'checklist_item_hotel_confirmation'),
          AppLocalizations.t(context, 'checklist_item_visa'),
        ],
      ),
      (
        name: AppLocalizations.t(context, 'checklist_section_tech'),
        emoji: '🔌',
        color: _accentSecondary,
        items: [
          AppLocalizations.t(context, 'checklist_item_phone_charger'),
          AppLocalizations.t(context, 'checklist_item_power_bank'),
          AppLocalizations.t(context, 'checklist_item_headphones'),
          AppLocalizations.t(context, 'checklist_item_laptop'),
          AppLocalizations.t(context, 'checklist_item_adapter'),
        ],
      ),
      (
        name: AppLocalizations.t(context, 'checklist_section_comfort'),
        emoji: '😴',
        color: _accent,
        items: [
          AppLocalizations.t(context, 'checklist_item_neck_pillow'),
          AppLocalizations.t(context, 'checklist_item_eye_mask'),
          AppLocalizations.t(context, 'checklist_item_earplugs'),
          AppLocalizations.t(context, 'checklist_item_jacket'),
          AppLocalizations.t(context, 'checklist_item_compression_socks'),
        ],
      ),
    ];
    const sectionImages = [
      [
        'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1522199755839-a2bacb67c546?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1517336714739-489689fd1ca8?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1525547719571-a2d4ac8945e2?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1583394838336-acd977736f90?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1593344484962-796055d4a3a4?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1520006403909-838d6b92c22e?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1506485338023-6ce5f36692df?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=400&h=260&fit=crop&auto=format',
      ],
    ];

    final itemsState = _prepareExactItemsByTitle.putIfAbsent(
      title,
      () => sections.map((s) => List<String>.from(s.items)).toList(),
    );
    final addCtrls = _prepareExactAddControllersByTitle.putIfAbsent(
      title,
      () => List.generate(sections.length, (_) => TextEditingController()),
    );
    final checksState = _prepareExactChecksByTitle.putIfAbsent(
      title,
      () => itemsState
          .map(
            (items) => List<bool>.filled(items.length, false, growable: true),
          )
          .toList(),
    );
    final outfitSaved = _prepareExactOutfitSavedByTitle.putIfAbsent(
      title,
      () => List<bool>.filled(3, false, growable: true),
    );
    final isListSaved = _prepareExactSavedByTitle[title] ?? false;

    for (var i = 0; i < itemsState.length; i++) {
      final targetLen = itemsState[i].length;
      if (checksState[i].length < targetLen) {
        checksState[i].addAll(
          List<bool>.filled(
            targetLen - checksState[i].length,
            false,
            growable: true,
          ),
        );
      } else if (checksState[i].length > targetLen) {
        checksState[i] = checksState[i].sublist(0, targetLen);
      }
    }

    return StatefulBuilder(
      builder: (context, checklistSetState) {
        final totalItems = itemsState.fold<int>(
          0,
          (sum, items) => sum + items.length,
        );
        final totalChecked = checksState.fold<int>(
          0,
          (sum, items) => sum + items.where((v) => v).length,
        );
        final progress = totalItems == 0 ? 0.0 : totalChecked / totalItems;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: _phoneShell,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppLocalizations.t(context, 'checklist_generated_for')} $title',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$totalChecked ${AppLocalizations.t(context, 'checklist_of')} $totalItems ${AppLocalizations.t(context, 'checklist_items')}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _border.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 400),
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: _accentTertiary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _border, width: 1)),
                  color: _panel,
                ),
                child: Column(
                  children: List.generate(sections.length, (sIdx) {
                    final s = sections[sIdx];
                    final doneCount = checksState[sIdx].where((v) => v).length;
                    return Container(
                      color: _phoneShell,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      margin: const EdgeInsets.only(bottom: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.emoji,
                                style: const TextStyle(fontSize: 15, height: 1),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _textHeading,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentTertiary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '$doneCount/${itemsState[sIdx].length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _accentTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 64,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: sectionImages[sIdx].length,
                              itemExtent: 88,
                              itemBuilder: (_, imgIdx) {
                                final img = sectionImages[sIdx][imgIdx];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right:
                                        imgIdx == sectionImages[sIdx].length - 1
                                        ? 0
                                        : 8,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _border),
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: Image.network(
                                      img,
                                      fit: BoxFit.cover,
                                      cacheWidth: 264,
                                      cacheHeight: 192,
                                      errorBuilder: (_ctx, _err, _st) =>
                                          Container(
                                            color: _panel,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.image_outlined,
                                              size: 16,
                                              color: _textMuted,
                                            ),
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(itemsState[sIdx].length, (i) {
                            final done = checksState[sIdx][i];
                            return GestureDetector(
                              onTap: () => checklistSetState(
                                () => checksState[sIdx][i] = !done,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  border: i < itemsState[sIdx].length - 1
                                      ? Border(
                                          bottom: BorderSide(
                                            color: _border.withOpacity(0.85),
                                            width: 1,
                                          ),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: done ? s.color : _border,
                                          width: 1.5,
                                        ),
                                        color: done ? s.color : _panel,
                                      ),
                                      alignment: Alignment.center,
                                      child: done
                                          ? const Icon(
                                              Icons.check,
                                              size: 11,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        itemsState[sIdx][i],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: done
                                              ? _textMuted
                                              : _textHeading,
                                          decoration: done
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        checklistSetState(() {
                                          itemsState[sIdx].removeAt(i);
                                          checksState[sIdx].removeAt(i);
                                        });
                                      },
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: Text(
                                            '×',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: _textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _bgSecondary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: addCtrls[sIdx],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _textHeading,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.t(
                                        context,
                                        'checklist_add_item',
                                      ),
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textMuted,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) {
                                      final val = addCtrls[sIdx].text.trim();
                                      if (val.isEmpty) return;
                                      checklistSetState(() {
                                        itemsState[sIdx].add(val);
                                        checksState[sIdx].add(false);
                                        addCtrls[sIdx].clear();
                                      });
                                    },
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    final val = addCtrls[sIdx].text.trim();
                                    if (val.isEmpty) return;
                                    checklistSetState(() {
                                      itemsState[sIdx].add(val);
                                      checksState[sIdx].add(false);
                                      addCtrls[sIdx].clear();
                                    });
                                  },
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: s.color,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '+',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10131B),
                                        height: 1,
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
                  }),
                ),
              ),
              Container(
                color: _phoneShell,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: IgnorePointer(
                  ignoring: isListSaved,
                  child: GestureDetector(
                    onTap: () {
                      final boards = [
                        AppLocalizations.t(context, 'board_party_looks'),
                        AppLocalizations.t(context, 'board_occasion'),
                        AppLocalizations.t(context, 'board_office_fit'),
                        AppLocalizations.t(context, 'board_vacation'),
                        AppLocalizations.t(context, 'board_everything_else'),
                      ];
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => Container(
                          decoration: BoxDecoration(
                            color: _bgSecondary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: _border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                AppLocalizations.t(context, 'board_save_title'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _textHeading,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.t(
                                  context,
                                  'board_save_subtitle',
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...boards.asMap().entries.map((entry) {
                                final i = entry.key;
                                final label = entry.value;
                                return GestureDetector(
                                  onTap: () async {
                                    final boardId = _boardIdByLabel[label];
                                    if (boardId == null) {
                                      Navigator.pop(context);
                                      return;
                                    }
                                    Navigator.pop(context);
                                    await _savePrepareExactToBoard(
                                      boardId: boardId,
                                      title: title,
                                      sections: sections,
                                      itemsState: itemsState,
                                      checksState: checksState,
                                      outfitSaved: outfitSaved,
                                    );
                                    if (!mounted) return;
                                    checklistSetState(
                                      () => _prepareExactSavedByTitle[title] =
                                          true,
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _panel,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: _border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: _textHeading,
                                            ),
                                          ),
                                        ),
                                        if (i == 3) // Vacation board (index 3)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _accentSecondary,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: Text(
                                              AppLocalizations.t(
                                                context,
                                                'board_suggested_badge',
                                              ),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: isListSaved
                            ? LinearGradient(colors: [_accent, _accentTertiary])
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_accent, _accentTertiary],
                              ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isListSaved ? '✅' : '📌',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isListSaved
                                ? AppLocalizations.t(context, 'checklist_saved')
                                : AppLocalizations.t(
                                    context,
                                    'checklist_save_to_board',
                                  ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _onAccent,
                              letterSpacing: 0.14,
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
        );
      },
    );
  }

  Widget _buildPickSheet({
    required String name,
    required String tag,
    required VoidCallback onClose,
  }) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_surface, _bgSecondary],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: _accent.withOpacity(0.12), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.15),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              40 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: _textHeading,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tag,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedPressable(
                        scalePressed: 0.97,
                        onTap: onClose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _accent.withOpacity(0.20),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(
                                context,
                                'pick_sheet_save_to_board',
                              ),
                              style: TextStyle(
                                color: _accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedPressable(
                        scalePressed: 0.97,
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: _accentGradient2,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withOpacity(0.35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(
                                context,
                                'pick_sheet_style_this',
                              ),
                              style: TextStyle(
                                color: _onAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeeAllPanel() {
    // 🆕 seeAll picks localized
    final seeAllPicks = [
      (
        AppLocalizations.t(context, 'pick_minimal_chic'),
        AppLocalizations.t(context, 'pick_minimal_chic_tag'),
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_street_edit'),
        AppLocalizations.t(context, 'pick_street_edit_tag'),
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_office_look'),
        AppLocalizations.t(context, 'pick_office_look_tag'),
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_evening'),
        AppLocalizations.t(context, 'pick_evening_tag'),
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_athleisure'),
        AppLocalizations.t(context, 'pick_athleisure_tag'),
        'https://images.unsplash.com/photo-1538805060514-97d9cc17730c?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_resort_wear'),
        AppLocalizations.t(context, 'pick_resort_wear_tag'),
        'https://images.unsplash.com/photo-1469334031218-e382a71b716b?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
    ];
    return AnimatedBuilder(
      animation: _seeAllCtrl,
      builder: (context, _) {
        final slideOffset = (1.0 - _seeAllCtrl.value);
        return Transform.translate(
          offset: Offset(MediaQuery.of(context).size.width * slideOffset, 0),
          child: Container(
            color: _bgPrimary,
            child: Column(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _closeSeeAll,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _panel,
                              border: Border.all(
                                color: _accent.withOpacity(0.20),
                                width: 1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: _textMuted,
                              size: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.t(
                            context,
                            'picks_section_title',
                          ), // 🆕
                          style: TextStyle(
                            color: _textHeading,
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: seeAllPicks.length,
                    itemBuilder: (context, i) {
                      return RepaintBoundary(
                        child: _AnimatedPressable(
                          scalePressed: 0.97,
                          onTap: () {
                            _closeSeeAll();
                            Future.delayed(
                              const Duration(milliseconds: 380),
                              () {
                                if (mounted) {
                                  _openPickSheet(
                                    seeAllPicks[i].$1,
                                    seeAllPicks[i].$2,
                                  );
                                }
                              },
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: _surface,
                              border: Border.all(color: _border, width: 1),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    seeAllPicks[i].$3,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    cacheWidth:
                                        (240 *
                                                MediaQuery.of(
                                                  context,
                                                ).devicePixelRatio)
                                            .round(),
                                    filterQuality: FilterQuality.low,
                                    errorBuilder: (_ctx, _err, _st) =>
                                        Container(
                                          color: _accent.withOpacity(0.1),
                                          child: Icon(
                                            Icons.image,
                                            color: _textMuted,
                                          ),
                                        ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seeAllPicks[i].$1,
                                        style: TextStyle(
                                          color: _textHeading,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        seeAllPicks[i].$2,
                                        style: TextStyle(
                                          color: _textMuted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
      },
    );
  }

  // ── Notifications Panel ──────────────────────────────────────────────────
  Widget _buildNotificationPanel() {
    final screenH = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    // No static data — real notifications come from backend
    // 🆕 Use the notifications list from state that updates dynamically
    final List<_NotifData> notifications = _notificationsList;

    return Positioned.fill(
      child: Stack(
        children: [
          // Blurred backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // 🆕 Mark all notifications as read when panel closes
                for (int i = 0; i < _notificationsList.length; i++) {
                  final notif = _notificationsList[i];
                  _notificationsList[i] = _NotifData(
                    icon: notif.icon,
                    color: notif.color,
                    title: notif.title,
                    body: notif.body,
                    time: notif.time,
                    unread: false,
                  );
                }
                _updateUnreadNotifCount();
                setState(() => _notifPanelOpen = false);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                opacity: _notifPanelOpen ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 280),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ),
            ),
          ),

          // Bottom sheet — 70% height, slides up
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {},
              child: AnimatedSlide(
                offset: _notifPanelOpen ? Offset.zero : const Offset(0, 1.0),
                duration: const Duration(milliseconds: 380),
                curve: const Cubic(0.16, 1.0, 0.3, 1.0),
                child: AnimatedOpacity(
                  opacity: _notifPanelOpen ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 300) {
                        setState(() => _notifPanelOpen = false);
                      }
                    },
                    child: Container(
                      height: screenH * 0.70,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        border: Border.all(
                          color: _border.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 40,
                            offset: const Offset(0, -8),
                          ),
                          BoxShadow(
                            color: _accent.withOpacity(0.06),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        child: Column(
                          children: [
                            // Drag handle
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: _border.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                              child: Row(
                                children: [
                                  ShaderMask(
                                    shaderCallback: (b) =>
                                        _accentGradient.createShader(b),
                                    child: Text(
                                      AppLocalizations.t(
                                        context,
                                        'notifications_title',
                                      ),
                                      style: TextStyle(
                                        color: _textHeading,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => _notifPanelOpen = false),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _bgSecondary,
                                        border: Border.all(
                                          color: _border.withOpacity(0.5),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: _textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Divider(
                              height: 1,
                              thickness: 1,
                              color: _border.withOpacity(0.4),
                            ),

                            // List or empty state
                            Expanded(
                              child: notifications.isEmpty
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _accent.withOpacity(0.08),
                                          ),
                                          child: Icon(
                                            Icons.notifications_none_rounded,
                                            size: 30,
                                            color: _accent.withOpacity(0.5),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          AppLocalizations.t(
                                            context,
                                            'notifications_empty_title',
                                          ),
                                          style: TextStyle(
                                            color: _textHeading,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          AppLocalizations.t(
                                            context,
                                            'notifications_empty_subtitle',
                                          ),
                                          style: TextStyle(
                                            color: _textMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.separated(
                                      padding: EdgeInsets.only(
                                        top: 4,
                                        bottom: bottomPad + 16,
                                      ),
                                      itemCount: notifications.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        thickness: 1,
                                        indent: 66,
                                        endIndent: 16,
                                        color: _border.withOpacity(0.35),
                                      ),
                                      itemBuilder: (context, i) {
                                        final n = notifications[i];
                                        return _AnimatedPressable(
                                          scalePressed: 0.98,
                                          onTap: () => setState(
                                            () => _notifPanelOpen = false,
                                          ),
                                          child: Container(
                                            color: n.unread
                                                ? _accent.withOpacity(0.04)
                                                : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: n.color.withOpacity(
                                                      0.14,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    n.icon,
                                                    size: 18,
                                                    color: n.color,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              n.title,
                                                              style: TextStyle(
                                                                color:
                                                                    _textHeading,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    n.unread
                                                                    ? FontWeight
                                                                          .w700
                                                                    : FontWeight
                                                                          .w600,
                                                                letterSpacing:
                                                                    -0.1,
                                                                height: 1.2,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            n.time,
                                                            style: TextStyle(
                                                              color: _textMuted,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        n.body,
                                                        style: TextStyle(
                                                          color: _textMuted,
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                          height: 1.35,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (n.unread) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    width: 7,
                                                    height: 7,
                                                    margin:
                                                        const EdgeInsets.only(
                                                          top: 5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: _accent,
                                                    ),
                                                  ),
                                                ],
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

  Widget _buildComingSoonToast() {
    final screenH = MediaQuery.of(context).size.height;
    return Positioned(
      bottom: 110.0,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _toastVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: AnimatedSlide(
            offset: _toastVisible ? Offset.zero : const Offset(0, 0.3),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _bgSecondary.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: _shadowMedium, blurRadius: 28)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, color: _accent, size: 15),
                    SizedBox(width: 7),
                    Text(
                      AppLocalizations.t(context, 'coming_soon'), // 🆕
                      style: TextStyle(
                        color: _textHeading,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
  }

  // 🆕 DYNAMIC ROUTINE DATA FETCHING METHODS
  // These methods sync with real data from screens and services

  // ─── WEAR / DAILY WEAR ───
  // 🔧 FIX: "Wear" tracks DailyWearScreen's own daily pick — NOT generic
  // Wardrobe "last worn" data. Now reads from HomeCardSummaryProvider,
  // exactly like Care (Skincare) and Medicine below. DailyWearScreen must
  // set summary.wearHomeSubtitle / wearHomeStatus / isWearDone (and call
  // notifyListeners()) whenever the user picks/confirms today's outfit —
  // that file isn't in this upload, so that side still needs wiring up.
  // Falls back to the old Wardrobe-derived guess only if those fields
  // aren't available yet, so nothing breaks in the meantime.
  String _getDailyWearDescription() {
    try {
      final subtitle = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).wearHomeSubtitle;
      if (subtitle.isNotEmpty) return subtitle;
    } catch (_) {}
    // Fallback: generic Wardrobe data (until DailyWearScreen wires the provider up)
    final outfit = _wardrobeSignal.lastWornItemName;
    if (outfit.isNotEmpty) {
      return outfit.length > 20 ? outfit.substring(0, 17) + '...' : outfit;
    }
    return _wardrobeSignal.favoriteStyle.isNotEmpty
        ? _wardrobeSignal.favoriteStyle
        : AppLocalizations.t(context, 'wear_pick_outfit');
  }

  String _getDailyWearStatus() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).wearHomeStatus;
    } catch (_) {
      return _wardrobeSignal.daysSinceLastWorn == 0
          ? AppLocalizations.t(context, 'status_done')
          : AppLocalizations.t(context, 'status_in_progress');
    }
  }

  bool _isDailyWearDone() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).isWearDone;
    } catch (_) {
      return _wardrobeSignal.daysSinceLastWorn == 0;
    }
  }

  // ─── MOVE / WORKOUT ───
  String _getWorkoutDescription() {
    try {
      final sub = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).moveHomeSubtitle;
      if (sub.isNotEmpty) {
        return sub.length > 20 ? '${sub.substring(0, 17)}...' : sub;
      }
    } catch (_) {}
    final workoutLabel = _workoutLabel;
    if (workoutLabel.isNotEmpty && workoutLabel != 'workout_mobility') {
      String displayLabel = workoutLabel.startsWith('workout_')
          ? AppLocalizations.t(context, workoutLabel)
          : workoutLabel;
      return displayLabel.length > 20
          ? '${displayLabel.substring(0, 17)}...'
          : displayLabel;
    }
    return AppLocalizations.t(context, 'routine_move_desc'); // "7-min stretch"
  }

  String _getWorkoutStatus() {
    try {
      final st = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).moveHomeStatus;
      if (st.isNotEmpty) return st;
    } catch (_) {}
    return _fitnessSignal.hasActiveStreak
        ? AppLocalizations.t(context, 'status_in_progress')
        : AppLocalizations.t(context, 'status_in_progress');
  }

  bool _isWorkoutDone() {
    // Check if workout goal met today
    return _fitnessSignal.stepGoalMet;
  }

  // ─── EAT / MEAL PLAN ───
  String _getMealDescription() {
    try {
      final sub = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).eatHomeSubtitle;
      if (sub.isNotEmpty) {
        return sub.length > 20 ? '${sub.substring(0, 17)}...' : sub;
      }
    } catch (_) {}
    if (_fitnessSignal.calorieGoalMet) {
      return AppLocalizations.t(context, 'home_card_eat_default');
    }
    return AppLocalizations.t(context, 'eat_meal_prep');
  }

  String _getMealStatus() {
    try {
      final st = Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).eatHomeStatus;
      if (st.isNotEmpty) return st;
    } catch (_) {}
    return _fitnessSignal.calorieGoalMet
        ? AppLocalizations.t(context, 'status_done')
        : AppLocalizations.t(context, 'status_in_progress');
  }

  bool _isMealDone() {
    return _fitnessSignal.calorieGoalMet;
  }

  // ─── CARE / SKINCARE ───
  String _getSkincareDescription() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).skincareHomeSubtitle;
    } catch (_) {
      final hour = DateTime.now().hour;
      if (hour >= 6 && hour < 12)
        return AppLocalizations.t(context, 'skin_morning_routine');
      if (hour >= 19) return AppLocalizations.t(context, 'skin_night_routine');
      return AppLocalizations.t(context, 'care_routine');
    }
  }

  String _getSkincareStatus() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).skincareHomeStatus;
    } catch (_) {
      final hour = DateTime.now().hour;
      return (hour >= 6 && hour < 12) || hour >= 19
          ? AppLocalizations.t(context, 'status_in_progress')
          : AppLocalizations.t(context, 'status_in_progress');
    }
  }

  bool _isSkincareDone() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).isSkincareDone;
    } catch (_) {
      return false;
    }
  }

  // ─── MEDICINE / HEALTH ───
  String _getMedicineDescription() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).medicineHomeSubtitle;
    } catch (_) {
      return AppLocalizations.t(context, 'medi_take_medicines');
    }
  }

  String _getMedicineStatus() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).medicineHomeStatus;
    } catch (_) {
      return AppLocalizations.t(context, 'status_in_progress');
    }
  }

  bool _isMedicineDone() {
    try {
      return Provider.of<HomeCardSummaryProvider>(
        context,
        listen: false,
      ).isMedicineDone;
    } catch (_) {
      return false;
    }
  }
}

// ── Plus Menu Item Widget ─────────────────────────────────────────────────────

class _PlusMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentSecondary;
  final Color textHeading;
  final Color textMuted;
  final Color panel;
  final Color border;
  final bool showDivider;
  final double delayT;
  final double animT;
  final VoidCallback? onTap;

  const _PlusMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentSecondary,
    required this.textHeading,
    required this.textMuted,
    required this.panel,
    required this.border,
    required this.showDivider,
    required this.delayT,
    required this.animT,
    this.onTap,
  });

  @override
  State<_PlusMenuItem> createState() => _PlusMenuItemState();
}

class _PlusMenuItemState extends State<_PlusMenuItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Staggered per-item fade: each item fades in slightly after the previous
    final itemT = ((widget.animT - widget.delayT) / (1.0 - widget.delayT))
        .clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _pressed
                ? widget.accent.withOpacity(0.08)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Opacity(
              opacity: itemT,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - itemT)),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.accent.withOpacity(0.20),
                          width: 1,
                        ),
                      ),
                      child: Icon(widget.icon, color: widget.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: widget.textHeading,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: widget.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
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
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: widget.border.withOpacity(0.6),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _NavPillPainter extends CustomPainter {
  final int activeIdx;
  final int itemCount;
  final double bulgeT;
  final double pillH;
  final double maxBulge;
  final Color fillColor;
  final Color borderColor;
  final Color glowColor;
  final Color shadowColor;

  const _NavPillPainter({
    required this.activeIdx,
    required this.itemCount,
    required this.bulgeT,
    required this.pillH,
    required this.maxBulge,
    required this.fillColor,
    required this.borderColor,
    required this.glowColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pillTop = h - pillH;
    final r = pillH / 2;

    final itemW = w / itemCount;
    final cx = itemW * activeIdx + itemW / 2;

    final bulgeH = maxBulge * bulgeT;
    final peakY = pillTop - bulgeH;

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, pillTop, w, pillH),
      Radius.circular(r),
    );
    final pillPath = Path()..addRRect(pillRect);

    final hw = itemW * 0.38;
    final tang = hw * 0.55;
    final lx = cx - hw;
    final rx = cx + hw;

    final bp = Path();
    bp.moveTo(lx, pillTop);
    bp.cubicTo(lx + tang, pillTop, cx - tang, peakY, cx, peakY);
    bp.cubicTo(cx + tang, peakY, rx - tang, pillTop, rx, pillTop);
    bp.close();

    final combined = Path.combine(PathOperation.union, pillPath, bp);

    canvas.drawPath(
      combined.shift(const Offset(0, 8)),
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    if (bulgeH > 1) {
      canvas.drawPath(
        combined,
        Paint()
          ..color = glowColor.withOpacity(0.12 * bulgeT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    canvas.drawPath(combined, Paint()..color = fillColor);

    canvas.drawPath(
      combined,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_NavPillPainter old) =>
      old.activeIdx != activeIdx ||
      old.bulgeT != bulgeT ||
      old.fillColor != fillColor ||
      old.shadowColor != shadowColor ||
      old.glowColor != glowColor ||
      old.borderColor != borderColor;
}

enum _OverlayState { idle, suggestions, thinking, response }

// ── Notification data model ───────────────────────────────────────────────────
class _NotifData {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String time;
  final bool unread;

  const _NotifData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
  });
}

class _IntentConfig {
  final List<String> suggestions;
  final String brandSub;
  final List<String> responseTags;
  const _IntentConfig({
    required this.suggestions,
    required this.brandSub,
    required this.responseTags,
  });
}

class _ResponseData {
  final String type, question, intro;
  final List<_Outfit> outfits;
  final List<_Task> tasks;
  final List<_WeekDay> weekDays;
  final List<_PlanSection> planSections;
  const _ResponseData({
    required this.type,
    required this.question,
    this.intro = '',
    this.outfits = const [],
    this.tasks = const [],
    this.weekDays = const [],
    this.planSections = const [],
  });
}

class _Outfit {
  final String name, imageUrl;
  final List<String> tags;
  const _Outfit(this.name, this.tags, this.imageUrl);
}

class _Task {
  final String label, due, priority;
  final bool done;
  const _Task(this.label, this.due, this.priority, this.done);
}

class _WeekDay {
  final String day, label;
  final List<String> items;
  final bool done, isToday;
  const _WeekDay(
    this.day,
    this.label,
    this.items, {
    this.done = false,
    this.isToday = false,
  });
}

class _PlanSection {
  final String title;
  final Color Function(AppThemeTokens) color;
  final List<String> items;
  const _PlanSection(this.title, this.color, this.items);
}

// 🆕 Intent config ఇప్పుడు localization keys use చేస్తోంది
// Runtime లో AppLocalizations.t() తో translate అవుతాయి
const _intentConfig = {
  'style': _IntentConfig(
    suggestions: ['intent_style_s1', 'intent_style_s2', 'intent_style_s3'],
    brandSub: 'intent_style_sub',
    responseTags: [
      'intent_style_tag1',
      'intent_style_tag2',
      'intent_style_tag3',
    ],
  ),
  'organize': _IntentConfig(
    suggestions: [
      'intent_organize_s1',
      'intent_organize_s2',
      'intent_organize_s3',
      'intent_organize_s4',
      'intent_organize_s5',
      'intent_organize_s6',
      'intent_organize_s7',
      'intent_organize_s8',
    ],
    brandSub: 'intent_organize_sub',
    responseTags: [],
  ),
  'prepare': _IntentConfig(
    suggestions: [
      'intent_prepare_s1',
      'intent_prepare_s2',
      'intent_prepare_s3',
    ],
    brandSub: 'intent_prepare_sub',
    responseTags: [
      'intent_prepare_tag1',
      'intent_prepare_tag2',
      'intent_prepare_tag3',
    ],
  ),
  'chat': _IntentConfig(
    suggestions: ['intent_chat_s1', 'intent_chat_s2', 'intent_chat_s3'],
    brandSub: 'intent_chat_sub',
    responseTags: ['intent_chat_tag1', 'intent_chat_tag2', 'intent_chat_tag3'],
  ),
};

// 🆕 _intentPlaceholder ఇప్పుడు JSON keys — AppLocalizations.t() తో translate అవుతాయి
// placeholder_chat, placeholder_style, placeholder_organize, placeholder_prepare
// _setPlaceholder('chat') → 'placeholder_chat' → JSON లో translate అవుతుంది

class _GradientText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;

  const _GradientText(
    this.text, {
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.accent.primary, t.accent.tertiary],
      ).createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.56,
          height: 1.1,
        ),
      ),
    );
  }
}

class _EntryFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double dy;
  final Duration delay;

  const _EntryFadeSlide({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOut,
    this.dy = 24.0,
    this.delay = Duration.zero,
  });

  @override
  State<_EntryFadeSlide> createState() => _EntryFadeSlideState();
}

class _EntryFadeSlideState extends State<_EntryFadeSlide> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double h = constraints.biggest.height;
        if (h == 0 || h == double.infinity) {
          h = MediaQuery.of(context).size.height;
        }

        final frac = widget.dy / h;
        return AnimatedOpacity(
          opacity: _show ? 1.0 : 0.0,
          duration: widget.duration,
          curve: widget.curve,
          child: AnimatedSlide(
            offset: _show ? Offset.zero : Offset(0, frac),
            duration: widget.duration,
            curve: widget.curve,
            child: widget.child,
          ),
        );
      },
    );
  }
}

const _cardTapDuration = Duration(milliseconds: 200);
const _cardTapCurve = Cubic(0.34, 1.56, 0.64, 1.0);

class _CardPressable extends StatefulWidget {
  final Widget Function(bool isHovered) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final Offset pressedOffset;

  const _CardPressable({
    required this.builder,
    this.onTap,
    this.pressedScale = 0.97,
    this.pressedOffset = Offset.zero,
  });

  @override
  State<_CardPressable> createState() => _CardPressableState();
}

class _CardPressableState extends State<_CardPressable> {
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
        child: AnimatedSlide(
          offset: _pressed ? widget.pressedOffset : Offset.zero,
          duration: _cardTapDuration,
          curve: _cardTapCurve,
          child: AnimatedScale(
            scale: _pressed ? widget.pressedScale : 1.0,
            duration: _cardTapDuration,
            curve: _cardTapCurve,
            child: widget.builder(_hovered),
          ),
        ),
      ),
    );
  }
}

class _PrepareQuickChip extends StatefulWidget {
  final String label;
  final VoidCallback onSend;
  final Color accent;
  final Color accentSecondary;
  final Color panel;
  final Color border;
  final Color activeText;
  final Color textMuted;

  const _PrepareQuickChip({
    required this.label,
    required this.onSend,
    required this.accent,
    required this.accentSecondary,
    required this.panel,
    required this.border,
    required this.activeText,
    required this.textMuted,
  });

  @override
  State<_PrepareQuickChip> createState() => _PrepareQuickChipState();
}

class _PrepareQuickChipState extends State<_PrepareQuickChip> {
  bool _active = false;
  bool _hovered = false;

  void _activateAndSend() {
    setState(() => _active = true);
    widget.onSend();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _active = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered && !_active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _activateAndSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: _active
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.accent, widget.accentSecondary],
                  )
                : null,
            color: _active
                ? null
                : hovered
                ? widget.accent.withOpacity(0.15)
                : widget.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _active
                  ? Colors.transparent
                  : hovered
                  ? widget.accent.withOpacity(0.5)
                  : widget.border,
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _active
                  ? widget.activeText
                  : hovered
                  ? widget.accent
                  : widget.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroRowData {
  const _HeroRowData({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.page,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Widget page;
}

// ── Badge ─────────────────────────────────────────────────────────────────────

class _HeroCardBadge extends StatelessWidget {
  const _HeroCardBadge({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        AppLocalizations.t(context, 'hero_badge_routine'),
        style: TextStyle(
          color: accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ── Routine item row ──────────────────────────────────────────────────────────

/// Fully accessible, animated tap target (min 48 × 48 px).
/// Pressed state: slight background tint + scale-down via AnimatedContainer.
class _RoutineItem extends StatefulWidget {
  const _RoutineItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.textHeading,
    required this.textMuted,
    required this.onTap,
    this.scale = 1.0,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Color textHeading;
  final Color textMuted;
  final VoidCallback onTap;

  /// Responsive scale factor (1.0 = baseline 360dp phone). Derived from the
  /// hero card's own width so rows stay readable on small screens and don't
  /// look tiny/oversized on large ones.
  final double scale;

  @override
  State<_RoutineItem> createState() => _RoutineItemState();
}

class _RoutineItemState extends State<_RoutineItem> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _pressed || _hovered;
    final s = widget.scale;
    final bubbleSize = 28.0 * s;
    final iconSize = 13.0 * s;
    final labelSize = 12.0 * s;
    final valueSize = 10.5 * s;
    final chevronSize = 14.0 * s;

    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.value}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1.5 * s),
            decoration: BoxDecoration(
              color: isActive
                  ? widget.color.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Icon bubble ──────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.only(top: 1.5 * s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: bubbleSize,
                    height: bubbleSize,
                    decoration: BoxDecoration(
                      color: isActive
                          ? widget.color.withOpacity(0.22)
                          : widget.color.withOpacity(0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: iconSize,
                        color: widget.color,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8 * s),

                // ── Label + subtitle ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.textHeading,
                          fontSize: labelSize,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.value,
                        style: TextStyle(
                          color: widget.textMuted,
                          fontSize: valueSize,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ],
                  ),
                ),

                // ── Chevron ──────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.only(top: 2.0 * s, left: 4.0 * s),
                  child: AnimatedSlide(
                    offset: isActive ? const Offset(0.15, 0) : Offset.zero,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: chevronSize,
                      color: widget.color.withOpacity(isActive ? 0.90 : 0.50),
                    ),
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

class _AnimatedPressable extends StatefulWidget {
  final Widget? child;
  final Widget Function(bool isHovered, bool isPressed)? builder;
  final VoidCallback? onTap;
  final double liftY;
  final double scaleHover;
  final double scalePressed;

  const _AnimatedPressable({
    this.child,
    this.builder,
    this.onTap,
    this.liftY = 0.0,
    this.scaleHover = 1.0,
    this.scalePressed = 0.97,
  }) : assert(child != null || builder != null);

  @override
  State<_AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<_AnimatedPressable> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    double scale = 1.0;
    double dy = 0.0;
    if (_isPressed) {
      scale = widget.scalePressed;
    } else if (_isHovered) {
      scale = widget.scaleHover;
      dy = -widget.liftY;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: _isPressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 340),
          curve: _isPressed
              ? const Cubic(0.4, 0.0, 1.0, 1.0)
              : const Cubic(0.34, 1.40, 0.64, 1.0),
          transform: Matrix4.translationValues(0.0, _isPressed ? 0.0 : dy, 0.0)
            ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0)),
          transformAlignment: Alignment.center,
          child: widget.builder != null
              ? widget.builder!(_isHovered, _isPressed)
              : widget.child!,
        ),
      ),
    );
  }
}
