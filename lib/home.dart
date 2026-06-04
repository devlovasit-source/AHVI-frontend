import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
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
import 'package:myapp/widgets/ahvi_stylist_chat.dart'; // AhVi single chat implementation
import 'package:myapp/app_localizations.dart'; // 🆕 Localization
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/daily_wear.dart';
import 'package:myapp/diet_fitness.dart';
import 'package:myapp/diet_page.dart';
import 'package:myapp/skincare.dart';
import 'package:myapp/home_card_summary_provider.dart';

// ─── Colors ──────────────────────────────────────────────

// 🆕 Nav items are now built dynamically in _buildBottomNav() using localization
// _homeNavItems icons only — labels come from JSON
const _homeNavIcons = <IconData>[
  Icons.home_outlined,
  Icons.chat_bubble_outline_rounded,
  Icons.dry_cleaning_outlined,
  Icons.grid_view_rounded,
  Icons.explore_outlined,
];
// Keep original for fallback / non-localized usage
const _homeNavItems = <({IconData icon, String label})>[
  (icon: Icons.home_outlined, label: 'Home'),
  (icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
  (icon: Icons.dry_cleaning_outlined, label: 'Wardrobe'),
  (icon: Icons.grid_view_rounded, label: 'Planner'),
  (icon: Icons.explore_outlined, label: 'Explore'),
];

Color _accent(AppThemeTokens t) => t.accent.primary;
Color _accentSecondary(AppThemeTokens t) => t.accent.secondary;
Color _accentTertiary(AppThemeTokens t) => t.accent.tertiary;

// ─── Dynamic Recommendation Engine ──────────────────────────────────────────

/// Represents a single proactive AI suggestion with contextual metadata.
class _AiSuggestion {
  const _AiSuggestion({
    required this.text,
    required this.promptText,
    required this.icon,
    required this.intent,
    this.priority = 0,
  });

  final String text;
  final String promptText;
  final IconData icon;
  final String intent;
  final int priority;
}

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

  // ── Context equality (for cache invalidation) ─────────────────────────────
  String get _cacheKey =>
      '$hour-$weekday-$userName-${recentIntents.length}'
      '-${weather.condition.index}-${weather.tempCelsius?.round()}'
      '-${upcomingEvents.length}'
      '-${wardrobe.daysSinceLastWorn}-${wardrobe.unwornItems}'
      '-${fitness.workoutStreakDays}-${fitness.calorieGoalMet}';
}

// ── Scoring engine ────────────────────────────────────────────────────────────

/// Pure function — builds a scored, sorted list of suggestions for the
/// current context. All signals live here so they can be extended independently.
List<_AiSuggestion> _buildDynamicSuggestions(_RecommendationContext ctx) {
  final all = <_AiSuggestion>[];
  final name = ctx.userName;
  final w = ctx.weather;
  final fit = ctx.fitness;
  final ward = ctx.wardrobe;

  // ── 🌦️ WEATHER SIGNALS ────────────────────────────────────────────────────

  if (w.isRainy) {
    all.add(_AiSuggestion(
      text: "It's raining — want a rainy-day outfit that still looks great?",
      promptText: "Suggest a stylish, practical outfit for a rainy day. Include waterproof layers.",
      icon: Icons.umbrella_outlined,
      intent: 'style',
      priority: ctx.isMorning ? 15 : 8,
    ));
  }

  if (w.isCold && w.tempLabel.isNotEmpty) {
    all.add(_AiSuggestion(
      text: "It's ${w.tempLabel} outside — let me build a cosy layered look.",
      promptText: "It's ${w.tempLabel} today. Suggest a warm yet stylish layered outfit.",
      icon: Icons.ac_unit_outlined,
      intent: 'style',
      priority: ctx.isMorning ? 14 : 7,
    ));
  }

  if (w.isHot && w.tempLabel.isNotEmpty) {
    all.add(_AiSuggestion(
      text: "Hot day at ${w.tempLabel} — I've got breathable outfit ideas.",
      promptText: "It's ${w.tempLabel} today. Suggest a cool, breathable yet stylish outfit.",
      icon: Icons.wb_sunny_outlined,
      intent: 'style',
      priority: ctx.isMorning ? 14 : 6,
    ));
  }

  if (w.isClear && ctx.isWeekend) {
    all.add(_AiSuggestion(
      text: "Beautiful day out — perfect for a fresh weekend look!",
      promptText: "It's a clear sunny day on the weekend. Suggest a fresh, fun outdoor outfit.",
      icon: Icons.nature_outlined,
      intent: 'style',
      priority: 10,
    ));
  }

  if (!w.isRainy && !w.isCold && !w.isHot && ctx.isMorning) {
    all.add(_AiSuggestion(
      text: w.description.isNotEmpty
          ? "${w.description.capitalize()} today — here's your style brief."
          : "Nice weather today — want me to plan the perfect outfit?",
      promptText: "Plan a complete outfit for today's weather: ${w.description.isNotEmpty ? w.description : 'mild conditions'}.",
      icon: Icons.cloud_outlined,
      intent: 'style',
      priority: 9,
    ));
  }

  // ── 📅 CALENDAR SIGNALS ────────────────────────────────────────────────────

  final meeting = ctx.nextMeeting;
  if (meeting != null && meeting.isSoon) {
    all.add(_AiSuggestion(
      text: '"${meeting.title}" in ${meeting.hoursUntil}h — want a meeting-ready look?',
      promptText: 'I have a meeting called "${meeting.title}" in ${meeting.hoursUntil} hours. Suggest a sharp, confident outfit.',
      icon: Icons.work_outline_rounded,
      intent: 'style',
      priority: 18,
    ));
  } else if (meeting != null && meeting.isToday) {
    all.add(_AiSuggestion(
      text: '"${meeting.title}" later today — let\'s get the outfit right.',
      promptText: 'I have a meeting called "${meeting.title}" later today. Suggest a professional outfit.',
      icon: Icons.event_outlined,
      intent: 'style',
      priority: 12,
    ));
  }

  final occasion = ctx.nextOccasion;
  if (occasion != null && occasion.isSoon) {
    all.add(_AiSuggestion(
      text: '"${occasion.title}" is in ${occasion.hoursUntil}h — let\'s nail the look!',
      promptText: 'I have "${occasion.title}" in ${occasion.hoursUntil} hours. Create the perfect occasion outfit for me.',
      icon: Icons.celebration_outlined,
      intent: 'style',
      priority: 19,
    ));
  }

  if (ctx.upcomingEvents.any((e) => e.type == _EventType.dinner && e.isToday)) {
    final dinner = ctx.upcomingEvents.firstWhere((e) => e.type == _EventType.dinner && e.isToday);
    all.add(_AiSuggestion(
      text: 'Dinner plans tonight — I can style a perfect evening look.',
      promptText: 'I have dinner plans tonight: "${dinner.title}". Suggest an elegant yet comfortable evening outfit.',
      icon: Icons.restaurant_outlined,
      intent: 'style',
      priority: ctx.isAfternoon || ctx.isEvening ? 14 : 8,
    ));
  }

  if (ctx.upcomingEvents.any((e) => e.type == _EventType.travel && e.isToday)) {
    all.add(_AiSuggestion(
      text: 'Travel day! Want a stylish yet comfy airport outfit?',
      promptText: 'I am travelling today. Suggest a stylish, comfortable travel outfit with practical tips.',
      icon: Icons.flight_outlined,
      intent: 'style',
      priority: ctx.isMorning ? 17 : 11,
    ));
  }

  // ── 👗 WARDROBE SIGNALS ────────────────────────────────────────────────────

  if (ward.hasUnwornItems && ward.unwornItems >= 3) {
    all.add(_AiSuggestion(
      text: 'You have ${ward.unwornItems} unworn pieces — want to rediscover them?',
      promptText: 'I have ${ward.unwornItems} clothing items I have never worn. Help me build outfits using them.',
      icon: Icons.dry_cleaning_outlined,
      intent: 'organize',
      priority: ctx.isMorning ? 11 : 6,
    ));
  }

  if (ward.wardrobeNeedsAttention && ward.lastWornItemName.isNotEmpty) {
    all.add(_AiSuggestion(
      text: "Haven't styled a new look in ${ward.daysSinceLastWorn}d — want fresh inspiration?",
      promptText: "I haven't planned a new outfit in ${ward.daysSinceLastWorn} days. Surprise me with something fresh from my wardrobe.",
      icon: Icons.auto_fix_high_outlined,
      intent: 'style',
      priority: ward.daysSinceLastWorn >= 3 ? 10 : 6,
    ));
  }

  if (ward.favoriteStyle.isNotEmpty) {
    all.add(_AiSuggestion(
      text: 'New ${ward.favoriteStyle} picks match your taste — want to see?',
      promptText: 'Show me the latest ${ward.favoriteStyle} fashion picks that match my saved preferences.',
      icon: Icons.favorite_outline_rounded,
      intent: 'style',
      priority: ctx.recentIntents.contains('style') ? 9 : 5,
    ));
  }

  // ── 🏃 FITNESS SIGNALS ─────────────────────────────────────────────────────

  if (fit.hasActiveStreak) {
    all.add(_AiSuggestion(
      text: '${fit.workoutStreakDays}-day streak! Keep it going — what\'s today\'s workout?',
      promptText: 'I have a ${fit.workoutStreakDays}-day workout streak. Suggest today\'s workout routine to maintain it.',
      icon: Icons.local_fire_department_outlined,
      intent: 'style',
      priority: ctx.isMorning ? 12 : 7,
    ));
  }

  if (fit.nextWorkoutLabel.isNotEmpty && ctx.isMorning) {
    all.add(_AiSuggestion(
      text: '${fit.nextWorkoutLabel} day — I can suggest the right gym outfit.',
      promptText: 'Today is my ${fit.nextWorkoutLabel} workout. Suggest a comfortable and stylish gym outfit.',
      icon: Icons.fitness_center_outlined,
      intent: 'style',
      priority: 11,
    ));
  }

  if (fit.mealPlanNeeded && (ctx.isAfternoon || ctx.isEvening)) {
    all.add(_AiSuggestion(
      text: "You haven't hit your calorie goal — want a meal plan?",
      promptText: "I haven't met my calorie goal today. Suggest healthy, easy meals I can prepare now.",
      icon: Icons.restaurant_outlined,
      intent: 'eat',
      priority: 10,
    ));
  }

  if (fit.waterGlassesToday < 4 && ctx.isAfternoon) {
    all.add(_AiSuggestion(
      text: "Only ${fit.waterGlassesToday} glasses of water today — stay hydrated!",
      promptText: "I've only had ${fit.waterGlassesToday} glasses of water today. Give me a hydration plan and healthy snack ideas.",
      icon: Icons.water_drop_outlined,
      intent: 'eat',
      priority: 8,
    ));
  }

  // ── 📅 TIME + DAY SIGNALS (always-available fallbacks) ─────────────────────

  all.add(_AiSuggestion(
    text: name.isNotEmpty
        ? "Morning, $name — want me to plan today's look?"
        : "Good morning — want me to plan today's outfit?",
    promptText: "Plan a complete outfit for today based on the weather and my schedule.",
    icon: Icons.wb_sunny_outlined,
    intent: 'style',
    priority: ctx.isMorning ? 10 : 2,
  ));

  if (ctx.isMondayMorning) {
    all.add(_AiSuggestion(
      text: "New week — want me to plan 5 outfits in one go?",
      promptText: "Plan 5 complete outfits for me for the entire work week ahead.",
      icon: Icons.date_range_outlined,
      intent: 'style',
      priority: 13,
    ));
  }

  if (ctx.isFridayEvening) {
    all.add(_AiSuggestion(
      text: "Friday night — let's plan something special to wear.",
      promptText: "Help me pick a stylish evening outfit for Friday night out.",
      icon: Icons.nightlife_outlined,
      intent: 'style',
      priority: 13,
    ));
  }

  if (ctx.isSunday && ctx.isAfternoon) {
    all.add(_AiSuggestion(
      text: "Sunday is perfect for weekly meal prep — want help?",
      promptText: "Create a healthy and practical weekly meal prep plan for me.",
      icon: Icons.restaurant_outlined,
      intent: 'eat',
      priority: 11,
    ));
  }

  if (ctx.isWeekend) {
    all.add(_AiSuggestion(
      text: "Weekend vibes — want a casual look for today?",
      promptText: "Suggest a relaxed, stylish casual outfit for the weekend.",
      icon: Icons.weekend_outlined,
      intent: 'style',
      priority: 9,
    ));
  }

  if (ctx.isEvening) {
    all.add(_AiSuggestion(
      text: "Wind-down time — I can build your evening skincare routine.",
      promptText: "Build me a personalised evening skincare routine.",
      icon: Icons.spa_outlined,
      intent: 'style',
      priority: 8,
    ));
  }

  if (ctx.isNight) {
    all.add(_AiSuggestion(
      text: "Browsing late? I noticed new minimal picks that suit you.",
      promptText: "Show me the latest minimal fashion picks tailored to my saved style.",
      icon: Icons.auto_awesome_outlined,
      intent: 'style',
      priority: 7,
    ));
  }

  // ── Engagement-history boosts ─────────────────────────────────────────────
  if (ctx.recentIntents.contains('organize')) {
    all.add(_AiSuggestion(
      text: "Let's organise your wardrobe — I can sort by occasion.",
      promptText: "Help me organise my wardrobe by occasion and season.",
      icon: Icons.dry_cleaning_outlined,
      intent: 'organize',
      priority: 9,
    ));
  }

  if (ctx.recentIntents.contains('prepare')) {
    all.add(_AiSuggestion(
      text: "Got an event coming up? Let me help you prepare.",
      promptText: "Help me prepare a complete checklist for an upcoming event.",
      icon: Icons.event_outlined,
      intent: 'prepare',
      priority: 9,
    ));
  }

  // ── Always-available fallback ─────────────────────────────────────────────
  all.add(_AiSuggestion(
    text: "Feeling indecisive? I can style you in seconds.",
    promptText: "Surprise me with a complete outfit based on my style preferences.",
    icon: Icons.auto_fix_high_outlined,
    intent: 'style',
    priority: 5,
  ));

  // Sort by priority descending, return top 8.
  all.sort((a, b) => b.priority.compareTo(a.priority));
  return all.take(8).toList();
}

// ── Cache ─────────────────────────────────────────────────────────────────────

List<_AiSuggestion> _cachedSuggestions = [];
String _lastCacheKey = '';

List<_AiSuggestion> _getOrRefreshSuggestions(_RecommendationContext ctx) {
  final key = ctx._cacheKey;
  if (key != _lastCacheKey) {
    _cachedSuggestions = _buildDynamicSuggestions(ctx);
    _lastCacheKey = key;
  }
  return _cachedSuggestions;
}

// ── String helper ─────────────────────────────────────────────────────────────
extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// 🆕 AI suggestions keys — values come from JSON
const _aiSuggestionKeys = [
  'ai_sug_1',
  'ai_sug_2',
  'ai_sug_3',
  'ai_sug_4',
  'ai_sug_5',
  'ai_sug_6',
  'ai_sug_7',
];
// Keep original English as fallback
const _aiSuggestions = [
  "Your 2pm meeting is in 4 hrs — want to prep an outfit?",
  "It's 14°C and partly cloudy — shall I suggest a layered look?",
  "You haven't planned your week yet — want me to help?",
  "Feeling indecisive? I can style you in seconds.",
  "New drops match your saved style — want to see them?",
  "Your Friday dinner is coming up — let's plan the look.",
  "I noticed you love minimal styles — new picks are in.",
];

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

typedef _SuggestionState = ({int index, double opacity});
typedef _ClockState = ({String greeting, String date});

class Screen4 extends StatefulWidget {
  const Screen4({super.key, this.onShellNavTap});

  final ValueChanged<int>? onShellNavTap;

  @override
  State<Screen4> createState() => _Screen4State();
}

class _Screen4State extends State<Screen4> with TickerProviderStateMixin, WidgetsBindingObserver {
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

    // Re-sync fitness signal whenever HomeCardSummaryProvider notifies
    // (this is called on every Provider change that this widget depends on).
    _syncFitnessSignal();
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
  Color get _shadowStrong => _bgPrimary.withValues(alpha: 0.35);
  Color get _shadowMedium => _bgPrimary.withValues(alpha: 0.20);
  Color get _shadowLight => _bgPrimary.withValues(alpha: 0.12);
  Color get _transparent => _bgPrimary.withValues(alpha: 0.0);
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

  final ValueNotifier<_SuggestionState> _suggestionState =
      ValueNotifier<_SuggestionState>((index: 0, opacity: 1.0));
  Timer? _suggestionTimer;

  // ── Plus menu ─────────────────────────────────────────────────────────────
  // (Lens sheet manages its own state — no local controller needed)
  late AnimationController _plusMenuCtrl; // kept to avoid dispose() errors

  bool _toastVisible = false;
  Timer? _toastTimer;

  bool _seeAllOpen = false;
  late AnimationController _seeAllCtrl;

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
  final stt.SpeechToText _speech = stt.SpeechToText();
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
    _lastCacheKey = '';
    // Notify card widgets to re-evaluate their dynamic content.
    _cardContextVersion.value += 1;
    // Reset suggestion ticker to index 0 — new signals may have changed
    // priorities, so the highest-ranked suggestion should show first.
    _suggestionState.value = (index: 0, opacity: 1.0);
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

  /// Returns the live-ranked suggestion list for the current context.
  List<_AiSuggestion> get _dynamicSuggestions =>
      _getOrRefreshSuggestions(_recommendationCtx);

  // ── Signal fetchers ────────────────────────────────────────────────────────

  /// Fetches weather for the user's device locale via open-meteo (no API key).
  Future<void> _fetchWeatherSignal() async {
    try {
      // Use a free, no-key geocoding + weather API.
      // Falls back gracefully — never throws to caller.
      const lat = 17.385; // Hyderabad default; replace with device GPS if available
      const lon = 78.486;
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weathercode'
        '&timezone=auto',
      );
      final client = HttpClient();
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(const Utf8Decoder()).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toDouble();
          final code = (current['weathercode'] as num?)?.toInt() ?? 0;
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
      }
      client.close();
    } catch (_) {
      // Weather fetch is best-effort — fail silently.
    }
  }

  static _WeatherCondition _wmoCodeToCondition(int code) {
    if (code == 0) return _WeatherCondition.clear;
    if (code <= 3) return _WeatherCondition.cloudy;
    if (code >= 51 && code <= 82) return _WeatherCondition.rainy;
    if (code >= 85) return _WeatherCondition.rainy; // snow/sleet → treat as rainy
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
      final raw = await backend.getTodayCalendarEvents();

      final events = raw.map<_CalendarEvent>((e) {
        // Parse start_time — ISO-8601 string from the backend.
        DateTime startsAt;
        try {
          startsAt = DateTime.parse(e['start_time']?.toString() ?? '');
        } catch (_) {
          startsAt = DateTime.now().add(const Duration(hours: 8));
        }

        // Map backend `type` field to our internal enum.
        final rawType = (e['type'] ?? e['event_type'] ?? '').toString().toLowerCase();
        final _EventType type;
        if (rawType.contains('meet') || rawType.contains('work') || rawType.contains('call')) {
          type = _EventType.meeting;
        } else if (rawType.contains('travel') || rawType.contains('flight') || rawType.contains('trip')) {
          type = _EventType.travel;
        } else if (rawType.contains('dinner') || rawType.contains('lunch') || rawType.contains('brunch')) {
          type = _EventType.dinner;
        } else if (rawType.contains('workout') || rawType.contains('gym') || rawType.contains('fitness')) {
          type = _EventType.workout;
        } else if (rawType.contains('party') || rawType.contains('wedding') ||
                   rawType.contains('occasion') || rawType.contains('event') ||
                   rawType.contains('celebrat')) {
          type = _EventType.occasion;
        } else {
          type = _EventType.other;
        }

        return _CalendarEvent(
          title: e['title']?.toString() ?? e['summary']?.toString() ?? 'Event',
          startsAt: startsAt,
          type: type,
        );
      }).toList();

      // Sort chronologically so nextMeeting / nextOccasion pick the soonest.
      events.sort((a, b) => a.startsAt.compareTo(b.startsAt));

      if (mounted) {
        setState(() {
          _calendarEvents = events;
          _invalidateSuggestionCache();
        });
      }
    } catch (e) {
      debugPrint('📅 _fetchCalendarSignal error: $e');
      // Leave _calendarEvents unchanged — engine degrades gracefully.
    }
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
          final aDate = _parseDate(a['wornAt'] ?? a['last_worn'] ?? a['worn_at']);
          final bDate = _parseDate(b['wornAt'] ?? b['last_worn'] ?? b['worn_at']);
          return bDate.compareTo(aDate); // most recent first
        });
        lastWornItemName = wornItems.first['name']?.toString() ?? '';
        final lastDate = _parseDate(
            wornItems.first['wornAt'] ?? wornItems.first['last_worn'] ?? wornItems.first['worn_at']);
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
            tagCounts[occ.toLowerCase()] = (tagCounts[occ.toLowerCase()] ?? 0) + 1;
          }
        }
        if (tagCounts.isNotEmpty) {
          favoriteStyle = (tagCounts.entries.toList()
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
      final summary = Provider.of<HomeCardSummaryProvider>(context, listen: false);
      final moveText = summary.move.toLowerCase();
      final eatText  = summary.eat.toLowerCase();

      // Streak: "3-day streak", "Day 5", "5 days"
      int streak = 0;
      final streakMatch = RegExp(r'(\d+)[- ]?day').firstMatch(moveText);
      if (streakMatch != null) streak = int.tryParse(streakMatch.group(1) ?? '') ?? 0;

      // Calorie goal: "1,840 / 2,000 kcal" or "1840/2000"
      bool calorieGoalMet = false;
      final calMatch = RegExp(r'(\d[\d,]+)\s*/\s*(\d[\d,]+)').firstMatch(eatText);
      if (calMatch != null) {
        final consumed = int.tryParse(calMatch.group(1)!.replaceAll(',', '')) ?? 0;
        final goal    = int.tryParse(calMatch.group(2)!.replaceAll(',', '')) ?? 1;
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
      final workout   = data['workout']   as Map<String, dynamic>? ?? {};
      final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};

      // Streak
      final streak = (workout['streak'] as num?)?.toInt() ??
                     (data['streak']   as num?)?.toInt() ??
                     _fitnessSignal.workoutStreakDays;

      // Workout label
      final workoutName = workout['name']?.toString() ??
                          workout['type']?.toString() ??
                          data['workout_type']?.toString() ?? '';
      final nextWorkout = workoutName.isNotEmpty
          ? _extractWorkoutLabel(workoutName.toLowerCase())
          : _fitnessSignal.nextWorkoutLabel;

      // Calorie goal
      final consumed = (nutrition['calories_consumed'] as num?)?.toInt() ??
                       (data['calories_consumed']     as num?)?.toInt() ?? 0;
      final goal     = (nutrition['calories_goal']    as num?)?.toInt() ??
                       (data['calories_goal']         as num?)?.toInt() ?? 0;
      final calorieGoalMet = goal > 0 ? consumed >= goal : _fitnessSignal.calorieGoalMet;

      // Water glasses
      final water = (nutrition['water_glasses'] as num?)?.toInt() ??
                    (data['water_glasses']       as num?)?.toInt() ??
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

  /// Extracts a human-readable workout label from a free-text string.
  static String _extractWorkoutLabel(String text) {
    if (text.contains('leg'))    return 'Leg Day';
    if (text.contains('chest'))  return 'Chest Day';
    if (text.contains('back'))   return 'Back Day';
    if (text.contains('arm') || text.contains('bicep') || text.contains('tricep')) return 'Arm Day';
    if (text.contains('cardio') || text.contains('run') || text.contains('jog'))   return 'Cardio';
    if (text.contains('yoga'))   return 'Yoga';
    if (text.contains('hiit'))   return 'HIIT';
    if (text.contains('full body') || text.contains('fullbody')) return 'Full Body';
    if (text.contains('stretch') || text.contains('mobility'))  return 'Mobility';
    if (text.contains('rest'))   return '';
    return '';
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
  String get _chatPlaceholder => AppLocalizations.t(context, _chatPlaceholderKey);
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

  List<String> _responseTags = [];
  bool _tagsRevealed = false;

  String _userName = '';
  Uint8List? _avatarBytes;

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

  @override
  void initState() {
    super.initState();
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

    _suggestionTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _rotateSuggestion(),
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

    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _updateClock(),
    );

    _fetchUserProfile();

    // ── 🌦️📅👗🏃 Kick off all context signal fetches ─────────────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchWeatherSignal();
      _fetchCalendarSignal();
      _fetchWardrobeSignal();
      _syncFitnessSignal();
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
  }

  Future<void> _fetchUserProfile() async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final profileCtrl = Provider.of<profile.ProfileController>(context, listen: false);
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
          : 'Stylist';

      // avatarPath లేనప్పుడు Appwrite fallback avatar తెచ్చుకో
      Uint8List? avatarBytes;
      try {
        avatarBytes = await appwrite.getUserAvatar(rawName);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _userName = firstName;
          _avatarBytes = avatarBytes;
          _invalidateSuggestionCache(); // name changed → rescore
        });
      }
    }
  }

  void _updateClock() {
    if (!mounted) return;
    final now = DateTime.now();
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
      date: '${days[now.weekday % 7]}, ${now.day} ${months[now.month - 1]}',
    );
    // Invalidate suggestion cache — hour/weekday may have changed
    _invalidateSuggestionCache();
  }

  void _rotateSuggestion() {
    final current = _suggestionState.value;
    _suggestionState.value = (index: current.index, opacity: 0.0);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final maxIdx = _dynamicSuggestions.isNotEmpty
          ? _dynamicSuggestions.length
          : _aiSuggestions.length;
      _suggestionState.value = (
        index: (current.index + 1) % maxIdx,
        opacity: 1.0,
      );
    });
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
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _chatController.text = result.recognizedWords;
            _chatController.selection = TextSelection.fromPosition(
              TextPosition(offset: _chatController.text.length),
            );
          });
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _speech.stop();
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_IN',
        cancelOnError: true,
        partialResults: true,
      );
    }
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
    _chatFocusNode.removeListener(_onChatFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardHeight.dispose();
    _speech.stop();
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
    _suggestionTimer?.cancel();
    _toastTimer?.cancel();
    _clockTimer?.cancel();
    _suggestionState.dispose();
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
        _navRiseCtrls[_activeNavIdx].animateTo(0.0, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
        _navRiseCtrls[0].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
        setState(() => _activeNavIdx = 0);
      } else {
        // 🔧 FIX: Already on home tab — rise animation ensure చేయి
        _navRiseCtrls[0].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
      }
      if (widget.onShellNavTap != null) widget.onShellNavTap!(0);
      return;
    }

    // Highlight the tapped tab immediately before navigating
    void _activateTab(int i) {
      _navRiseCtrls[_activeNavIdx].animateTo(0.0, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
      _navRiseCtrls[i].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
      setState(() => _activeNavIdx = i);
    }

    if (idx == 1) {
      _activateTab(1);
      showAhviStylistChatSheet(context, moduleContext: 'style');
      return;
    }
    if (idx == 2) {
      // 🔧 FIX: Shell కి delegate చేసే ముందు local tab highlight చేయి
      _navRiseCtrls[_activeNavIdx].animateTo(0.0, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
      _navRiseCtrls[2].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
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
      _navRiseCtrls[_activeNavIdx].animateTo(0.0, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
      _navRiseCtrls[3].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
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

    _navRiseCtrls[_activeNavIdx].animateTo(0.0, curve: const Cubic(0.4, 0.0, 0.2, 1.0));
    _navRiseCtrls[idx].animateTo(1.0, curve: const Cubic(0.34, 1.56, 0.64, 1.0));
    setState(() => _activeNavIdx = idx);
  }

  void _openPlusMenu(BuildContext ctx) {
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(ctx, rootNavigator: true);
    showAhviLensSheet(
      ctx,
      t: _t,
      onVisualSearch: () => _showComingSoon(),
      onFindSimilar: () => _showComingSoon(),
      onAddToWardrobe: () => showAddToWardrobeModal(navigator.context),
    );
  }

  void _closePlusMenu() {
    // No-op: lens sheet manages its own dismiss
  }

  void _openNavScreen(Widget page) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
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
    ).then((_) {
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
        initialPrompt = null; // Organise module — wardrobe/outfit organisation chat
        break;
      case 'plan':
        module = 'prepare';
        initialPrompt = null; // Plan/Prepare module — event & trip planning chat
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
      barrierColor: _bgPrimary.withValues(alpha: 0.30),
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
        _responses.clear();
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
    setState(
      () => _chatPlaceholderKey =
          'placeholder_$intent',
    );
  }

  void _handlePrepareChipSend(String query) {
    if (_activeIntent == 'prepare' &&
        (_overlayState == _OverlayState.suggestions ||
            _overlayState == _OverlayState.response)) {
      _handleQuery(query, 'prepare');
      return;
    }
    if (_overlayState == _OverlayState.idle) {
      _triggerIntent('prepare');
      Future.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        if (_overlayState == _OverlayState.suggestions &&
            (_activeIntent ?? 'prepare') == 'prepare') {
          _handleQuery(query, 'prepare');
        }
      });
    }
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
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasTransientUi,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(backgroundColor: _bgPrimary, resizeToAvoidBottomInset: false, body: _buildPhoneScreen()),
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

                  const navBarH = 86.0; // nav bar total height (pillH + maxBulge + safeBottom)
                  const topSectionH = 170.0;
                  const spacing = 18.0;

                  // Placeholder height — _buildFixedLogoBar తో exact match:
                  // SafeArea.top (statusBarH) + topPad + logoFontSize + botPad
                  // Chat _ChatLogoHeader కూడా same values use చేస్తోంది
                  final double topPad = screenH < 700 ? 6.0 : 10.0;
                  final double botPad = screenH < 700 ? 4.0 : 6.0;
                  final double logoFontSizeH = screenH < 700 ? 26.0 : 30.0;
                  final double statusBarH = MediaQuery.paddingOf(context).top;
                  final double topBarPlaceholderH = statusBarH + topPad + logoFontSizeH + botPad;

                  // Available height after fixed sections
                  const chatBarH = 64.0;
                  const navBarH2 = 86.0;
                  const bottomReserve = 10 + chatBarH + navBarH2;
                  final availableH = screenH - topBarPlaceholderH - topSectionH - bottomReserve - spacing;
                  // Hero gets 62%, secondary gets 38% of available space
                  final heroFlex = 62;
                  final secFlex  = 38;

                  return SizedBox(
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20.0, right: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Space reserved for fixed logo overlay (not animated)
                          SizedBox(height: topBarPlaceholderH),
                          // Greeting + suggestion ticker — re-renders on signal change
                          ValueListenableBuilder<int>(
                            valueListenable: _cardContextVersion,
                            builder: (context, _, __) => _buildGreetingBlock(),
                          ),
                          // Hero card — grows with screen
                          Expanded(
                            flex: heroFlex,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildHeroCard(),
                            ),
                          ),
                          // Style & Prep cards — re-render when any context signal changes
                          Expanded(
                            flex: secFlex,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ValueListenableBuilder<int>(
                                valueListenable: _cardContextVersion,
                                builder: (context, _, __) => _buildSecondaryRow(),
                              ),
                            ),
                          ),
                          // Space reserved for floating prompt bar + nav bar (Positioned in Stack)
                          const SizedBox(height: 10 + 64 + navBarH),
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFixedLogoBar(),
          ),

          if (_overlayState != _OverlayState.idle) _buildAiOverlay(),


          if (_activeIntent == 'prepare' &&
              (_overlayState == _OverlayState.suggestions ||
                  _overlayState == _OverlayState.response))
            Builder(
              builder: (context) {
                final keyboardH = MediaQuery.of(context).viewInsets.bottom;
                final chipsBottom = keyboardH > 0 ? keyboardH + 72 : (MediaQuery.of(context).size.height * 0.23).clamp(160.0, 210.0);
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
              final navBarTotalH = safeB + 86.0 + 8.0;
              final promptBottom = kbH > 0 ? kbH + 8.0 : navBarTotalH;
              return Positioned(
                left: 20,
                right: 20,
                bottom: promptBottom,
                // Wrap in MediaQuery with zeroed viewInsets so Flutter does NOT
                // call showOnScreen / scroll-to-visible when the TextField gets
                // focus — that was causing the whole page to jump to the top.
                child: MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: _buildChatWrap(),
                ),
              );
            },
          ),

          // Only show nav bar when NOT inside a Shell (Shell has its own nav bar)
          // 🔧 FIX: Keyboard open అయినా nav bar same position లో ఉండాలి — hide చేయకూడదు
          if (widget.onShellNavTap == null)
            Builder(builder: (ctx) {
              final safeB = MediaQuery.paddingOf(ctx).bottom;
              return Positioned(left: 16, right: 16, bottom: safeB + 8, child: _buildBottomNav());
            }),

          if (_seeAllOpen) _buildSeeAllPanel(),

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
                  child: _auroraOrb(340, 340, c1.withValues(alpha: 0.30)),
                ),
                Positioned(
                  bottom: -60 + (t2 * 60),
                  right: -60 + (t2 * 30),
                  child: _auroraOrb(300, 300, c2.withValues(alpha: 0.34)),
                ),
                Positioned(
                  top: 300 + (t3 * -60),
                  left: -40 + (t3 * 100),
                  child: _auroraOrb(220, 220, c3.withValues(alpha: 0.22)),
                ),
                Positioned(
                  top: 140 + (t1 * 80),
                  right: -30,
                  child: _auroraOrb(180, 180, c1.withValues(alpha: 0.18)),
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
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final screenH = MediaQuery.of(context).size.height;
    final double topPad = screenH < 700 ? 6.0 : 10.0;
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
    return AhviHeader(
      frosted: false,
      right: _buildProfileAvatar(),
    );
  }

  Widget _buildProfileAvatar() {
    // ✅ FIX: ProfileController ని watch చేసి avatarPath directly వాడు
    // profile లో photo మారినప్పుడు ఇక్కడ automatically rebuild అవుతుంది
    final avatarPath = context
        .watch<profile.ProfileController>()
        .state
        .avatarPath;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
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
        ).then((_) {
          // userName refresh కోసం మాత్రమే
          if (mounted) _fetchUserProfile();
        });
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _panel,
          border: Border.all(color: _accent.withValues(alpha: 0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _shadowMedium,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarPath != null && avatarPath.isNotEmpty
            ? Align(
                alignment: Alignment.center,
                child: Image.file(
                  File(avatarPath),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: _accent.withValues(alpha: 0.7),
                  ),
                ),
              )
            : _avatarBytes != null
                ? Align(
                    alignment: Alignment.center,
                    child: Image.memory(
                      _avatarBytes!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: _accent.withValues(alpha: 0.7),
                  ),
      ),
    );
  }

  Widget _buildGreetingBlock() {
    final screenH = MediaQuery.of(context).size.height;
    final double greetFontSize = screenH < 700 ? 20.0 : 24.0;
    final double botPad = screenH < 700 ? 4.0 : 6.0;
    return Padding(
      padding: EdgeInsets.only(bottom: botPad),
      child: ValueListenableBuilder<_ClockState>(
        valueListenable: _clockState,
        builder: (context, clock, _) {
          // 🆕 greeting key ని translate చేస్తున్నాం
          final greetingText = AppLocalizations.t(context, clock.greeting);

          // ProfileController నుండి name చదువు — onboarding లో enter చేసిన name వస్తుంది
          final profileName = context.watch<profile.ProfileController>().state.name ?? '';
          final displayName = profileName.isNotEmpty
              ? profileName.split(' ').first
              : _userName;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clock.date.isEmpty ? 'Fri, 6 Mar' : clock.date,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3.0),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: greetFontSize,
                    fontWeight: FontWeight.w400,
                    color: _textHeading,
                    letterSpacing: -0.56,
                    height: 1.1,
                  ),
                  children: [
                    if (displayName.isNotEmpty) ...[
                      TextSpan(text: '$greetingText, '), // 🆕 translated
                      WidgetSpan(
                        child: _GradientText(
                          '$displayName.',
                          fontSize: greetFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ] else
                      TextSpan(text: '$greetingText.'), // login కాలేదు — name లేదు
                  ],
                ),
              ),
              const SizedBox(height: 6.0),
              ValueListenableBuilder<_SuggestionState>(
                valueListenable: _suggestionState,
                builder: (context, suggestion, _) {
                  // ── Dynamic suggestion — resolved at render time ─────────
                  final dynamic = _dynamicSuggestions;
                  final safeIdx = dynamic.isNotEmpty
                      ? suggestion.index % dynamic.length
                      : suggestion.index % _aiSuggestions.length;

                  // Prefer dynamic suggestion text; fall back to static key.
                  final String suggestionText;
                  final String promptText;
                  final IconData suggestionIcon;
                  if (dynamic.isNotEmpty) {
                    suggestionText = dynamic[safeIdx].text;
                    promptText = dynamic[safeIdx].promptText;
                    suggestionIcon = dynamic[safeIdx].icon;
                  } else {
                    suggestionText = AppLocalizations.t(
                        context, _aiSuggestionKeys[safeIdx]);
                    promptText = _aiSuggestions[safeIdx];
                    suggestionIcon = Icons.auto_awesome;
                  }

                  return _AnimatedPressable(
                    liftY: -1.5,
                    scalePressed: 0.98,
                    onTap: () => _openChatWithPrompt(promptText),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface.withValues(alpha: 0.80),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(color: _shadowMedium, blurRadius: 10),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  _accent.withValues(alpha: 0.15),
                                  _accentTertiary.withValues(alpha: 0.15),
                                ],
                              ),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: ShaderMask(
                                shaderCallback: (b) =>
                                    _accentGradient.createShader(b),
                                child: Icon(
                                  suggestionIcon,
                                  color: _textHeading,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: suggestion.opacity,
                              duration: const Duration(milliseconds: 350),
                              child: Text(
                                suggestionText,
                                style: TextStyle(
                                  color: _textSub,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _accent.withValues(alpha: 0.65),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPromptChipsRow() {
    // 🆕 Chips localized
    final chips = [
      ('✦', AppLocalizations.t(context, 'chip_outfit_idea'), AppLocalizations.t(context, 'chip_prompt_outfit')),
      ('◎', AppLocalizations.t(context, 'chip_daily_plan'), AppLocalizations.t(context, 'chip_prompt_daily_plan')),
      ('⊹', AppLocalizations.t(context, 'chip_workout'), AppLocalizations.t(context, 'chip_prompt_workout')),
      ('◈', AppLocalizations.t(context, 'chip_meal_plan'), AppLocalizations.t(context, 'chip_prompt_meal_plan')),
      ('◷', AppLocalizations.t(context, 'chip_schedule'), AppLocalizations.t(context, 'chip_prompt_schedule')),
    ];
    return SizedBox(
      height: 40,
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
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                      fontSize: 12,
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
            onSend: () => _handlePrepareChipSend(_prepareChipKeys[i].$2),
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

  Widget _buildHeroCard() {
    final cardBg = _surface;

    // ── Dynamic summaries from HomeCardSummaryProvider ────────────────────────
    final summary = context.watch<HomeCardSummaryProvider>();

    // ── Data ──────────────────────────────────────────────────────────────────
    final heroRows = <_HeroRowData>[
      _HeroRowData(
        icon: Icons.checkroom_outlined,
        color: const Color(0xFF6B8FD4),
        label: AppLocalizations.t(context, 'hero_row_wear'),
        value: summary.wear,
        page: DailyWearScreen(),
      ),
      _HeroRowData(
        icon: Icons.directions_run_rounded,
        color: const Color(0xFF5BBF8A),
        label: AppLocalizations.t(context, 'hero_row_move'),
        value: summary.move,
        page: DietAndFitnessScreen(),
      ),
      _HeroRowData(
        icon: Icons.restaurant_outlined,
        color: const Color(0xFFE8895A),
        label: AppLocalizations.t(context, 'hero_row_eat'),
        value: summary.eat,
        page: MainScreen(),
      ),
      _HeroRowData(
        icon: Icons.spa_outlined,
        color: const Color(0xFFB07FD4),
        label: AppLocalizations.t(context, 'hero_row_care'),
        value: summary.care,
        page: SkincareScreen(),
      ),
    ];

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: cardBg,
          border: Border.all(
            color: _border.withValues(alpha: 0.45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _shadowStrong,
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: _shadowLight,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // ── Background image — right side with left-edge fade ──────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 140,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/hero_card.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  // Left fade — blends smoothly into card surface
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [cardBg, cardBg.withValues(alpha: 0.0)],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Bottom fade — blends into card bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [cardBg.withValues(alpha: 0.0), cardBg],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Foreground content ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ── Headline ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      AppLocalizations.t(context, 'hero_card_headline'),
                      style: TextStyle(
                        color: _textHeading,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.4,
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Routine rows ─────────────────────────────────────
                  ...List.generate(heroRows.length, (i) {
                    final row = heroRows[i];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoutineItem(
                          icon: row.icon,
                          color: row.color,
                          label: row.label,
                          value: row.value,
                          textHeading: _textHeading,
                          textMuted: _textSub,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => row.page),
                          ),
                        ),
                        if (i < heroRows.length - 1)
                          const SizedBox(height: 2),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


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
        title: 'Occasion Look',
        subtitle: '${e.title} in ${e.hoursUntil}h — I\'ll pick the perfect outfit.',
        cta: 'Style Me Now',
        icon: Icons.celebration_outlined,
        prompt: 'I have "${e.title}" in ${e.hoursUntil} hours. Create the perfect occasion outfit.',
      );
    }
    if (ctx.hasSoonMeeting) {
      final e = ctx.nextMeeting!;
      return _CardContent(
        title: 'Meeting Ready',
        subtitle: '"${e.title}" in ${e.hoursUntil}h — sharp & confident look.',
        cta: 'Get the Look',
        icon: Icons.work_outline_rounded,
        prompt: 'I have a meeting "${e.title}" in ${e.hoursUntil} hours. Suggest a sharp professional outfit.',
      );
    }

    // 🌦️ Weather-driven
    if (w.isRainy) {
      return _CardContent(
        title: 'Rainy Day Style',
        subtitle: 'Stay dry & chic — I\'ll build your rain-ready outfit.',
        cta: 'See Outfit',
        icon: Icons.umbrella_outlined,
        prompt: 'It\'s raining today. Suggest a stylish waterproof outfit.',
      );
    }
    if (w.isCold && w.tempLabel.isNotEmpty) {
      return _CardContent(
        title: 'Layer Up',
        subtitle: '${w.tempLabel} outside — cosy layers that still look great.',
        cta: 'Build the Look',
        icon: Icons.ac_unit_outlined,
        prompt: 'It\'s ${w.tempLabel} today. Suggest a warm layered outfit.',
      );
    }
    if (w.isHot && w.tempLabel.isNotEmpty) {
      return _CardContent(
        title: 'Beat the Heat',
        subtitle: '${w.tempLabel} today — breathable fits that look effortless.',
        cta: 'Cool Outfits',
        icon: Icons.wb_sunny_outlined,
        prompt: 'It\'s ${w.tempLabel} today. Suggest a cool breathable outfit.',
      );
    }

    // 🏃 Fitness-driven
    if (fit.nextWorkoutLabel.isNotEmpty && ctx.isMorning) {
      return _CardContent(
        title: '${fit.nextWorkoutLabel} Fit',
        subtitle: 'Look great at the gym — I\'ll pick the perfect workout gear.',
        cta: 'Gym Outfit',
        icon: Icons.fitness_center_outlined,
        prompt: 'Today is my ${fit.nextWorkoutLabel} day. Suggest a stylish gym outfit.',
      );
    }
    if (fit.hasActiveStreak && ctx.isMorning) {
      return _CardContent(
        title: '${fit.workoutStreakDays}-Day Streak!',
        subtitle: 'Keep the momentum — here\'s your energy-forward look.',
        cta: 'Style the Streak',
        icon: Icons.local_fire_department_outlined,
        prompt: 'I\'m on a ${fit.workoutStreakDays}-day fitness streak. Suggest a motivating outfit for today.',
      );
    }

    // 👗 Wardrobe-driven
    if (ward.hasUnwornItems && ward.unwornItems >= 3) {
      return _CardContent(
        title: 'Rediscover Pieces',
        subtitle: '${ward.unwornItems} unworn items waiting — let\'s create new looks.',
        cta: 'Explore Wardrobe',
        icon: Icons.dry_cleaning_outlined,
        prompt: 'I have ${ward.unwornItems} clothing items I\'ve never worn. Build fresh outfits using them.',
      );
    }
    if (ward.favoriteStyle.isNotEmpty) {
      return _CardContent(
        title: '${ward.favoriteStyle.capitalize()} Style',
        subtitle: 'New picks that match your taste are in — want to see?',
        cta: 'View Picks',
        icon: Icons.favorite_outline_rounded,
        prompt: 'Show me new ${ward.favoriteStyle} fashion picks that match my style preferences.',
      );
    }

    // 📅 Time-of-day fallbacks
    if (ctx.isMondayMorning) {
      return _CardContent(
        title: 'Week Ahead',
        subtitle: 'Plan 5 outfits for the week in one go.',
        cta: 'Plan My Week',
        icon: Icons.date_range_outlined,
        prompt: 'Plan 5 complete outfits for my work week ahead.',
      );
    }
    if (ctx.isFridayEvening) {
      return _CardContent(
        title: 'Friday Night',
        subtitle: 'Evening plans? Let\'s find you the perfect look.',
        cta: 'Night Look',
        icon: Icons.nightlife_outlined,
        prompt: 'Help me pick a stylish evening outfit for Friday night.',
      );
    }
    if (ctx.isWeekend) {
      return _CardContent(
        title: 'Weekend Vibes',
        subtitle: 'Casual, fresh looks for a great weekend.',
        cta: 'Style Weekend',
        icon: Icons.weekend_outlined,
        prompt: 'Suggest a relaxed yet stylish casual outfit for the weekend.',
      );
    }
    if (ctx.isEvening) {
      return _CardContent(
        title: 'Evening Look',
        subtitle: 'Wind down in style — skincare & evening outfit sorted.',
        cta: 'Evening Routine',
        icon: Icons.spa_outlined,
        prompt: 'Build me an evening outfit and skincare routine.',
      );
    }
    if (ctx.isMorning) {
      return _CardContent(
        title: 'Today\'s Style',
        subtitle: _userName.isNotEmpty
            ? 'Morning, $_userName! Let me plan your look.'
            : 'Good morning — let\'s plan your outfit.',
        cta: 'Plan My Look',
        icon: Icons.auto_awesome_rounded,
        prompt: 'Plan a complete outfit for me today.',
      );
    }

    // Default
    return _CardContent(
      title: 'AI Stylist',
      subtitle: 'Your personal AI fashion assistant, ready to style you.',
      cta: 'Let\'s Style',
      icon: Icons.auto_awesome_rounded,
      prompt: 'Surprise me with a complete outfit based on my style preferences.',
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
        title: 'Event Prep',
        subtitle: '"${e.title}" in ${e.hoursUntil}h — checklist ready?',
        cta: 'Prep Checklist',
        icon: Icons.checklist_rounded,
        prompt: 'Create a complete prep checklist for my upcoming event: "${e.title}".',
      );
    }

    // 📅 Travel today
    if (ctx.upcomingEvents.any((e) => e.type == _EventType.travel && e.isToday)) {
      final e = ctx.upcomingEvents.firstWhere((e) => e.type == _EventType.travel && e.isToday);
      return _CardContent(
        title: 'Travel Ready',
        subtitle: 'Packing list + outfit for your trip today.',
        cta: 'Pack & Prep',
        icon: Icons.flight_outlined,
        prompt: 'Create a travel packing checklist and outfit plan for my trip today: "${e.title}".',
      );
    }

    // 📅 Sunday — weekly prep
    if (ctx.isSunday) {
      return _CardContent(
        title: 'Sunday Prep',
        subtitle: 'Plan meals, outfits & goals for the week ahead.',
        cta: 'Plan My Week',
        icon: Icons.event_available_outlined,
        prompt: 'Help me do a complete Sunday prep: weekly meal plan, outfit planning, and goal setting.',
      );
    }

    // 📅 Monday — weekly kickoff
    if (ctx.isMondayMorning) {
      return _CardContent(
        title: 'Week Kickoff',
        subtitle: 'Set intentions, meals & outfits for the week.',
        cta: 'Start Planning',
        icon: Icons.rocket_launch_outlined,
        prompt: 'Help me plan my week: schedule, meals, and daily outfits.',
      );
    }

    // 🏃 Meal plan needed
    if (fit.mealPlanNeeded && (ctx.isAfternoon || ctx.isEvening)) {
      return _CardContent(
        title: 'Meal Plan',
        subtitle: 'Haven\'t hit your calorie goal — let me fix that.',
        cta: 'Plan Meals',
        icon: Icons.restaurant_outlined,
        prompt: 'I haven\'t met my calorie goal today. Suggest healthy meals I can prepare now.',
      );
    }

    // 🏃 Workout plan
    if (fit.nextWorkoutLabel.isNotEmpty) {
      return _CardContent(
        title: fit.nextWorkoutLabel.isNotEmpty ? '${fit.nextWorkoutLabel} Plan' : 'Workout Plan',
        subtitle: 'Your routine, nutrition & gear sorted in one go.',
        cta: 'Plan Workout',
        icon: Icons.fitness_center_outlined,
        prompt: 'Plan my ${fit.nextWorkoutLabel} workout: exercises, sets, nutrition, and gear.',
      );
    }

    // Time-of-day fallbacks
    if (ctx.isEvening) {
      return _CardContent(
        title: 'Tomorrow Prep',
        subtitle: 'Lay out tomorrow\'s outfit & plan the day tonight.',
        cta: 'Prep Tonight',
        icon: Icons.nights_stay_outlined,
        prompt: 'Help me prepare for tomorrow: outfit, schedule, and to-dos.',
      );
    }
    if (ctx.isMorning) {
      return _CardContent(
        title: 'Day Plan',
        subtitle: 'Meals, outfit & schedule — I\'ll organise your day.',
        cta: 'Plan My Day',
        icon: Icons.today_outlined,
        prompt: 'Help me plan today: meals, outfit, and schedule.',
      );
    }

    // Default
    return _CardContent(
      title: 'Prep & Plan',
      subtitle: 'Organise wardrobe, meals & schedule with AI.',
      cta: 'Start Planning',
      icon: Icons.grid_view_rounded,
      prompt: 'Help me plan and organise my wardrobe, meals, and schedule.',
    );
  }

  Widget _buildSecondaryRow() {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final prep = _prepCardContent(); // 🆕 context-aware
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Card 1: Style (image panel separated from hero card) ─────────
        Expanded(
          child: _buildStyleCard(),
        ),
        const SizedBox(width: 12),
        // ── Card 2: Plan & Prep (combined) ───────────────────────────────
        Expanded(
          child: _buildSecCard(
            icon: prep.icon,
            title: prep.title,
            subtitle: prep.subtitle,
            ctaLabel: prep.cta,
            intent: 'organize',
            prompt: prep.prompt,
            assetImage: 'assets/images/plan_card.jpg',
          ),
        ),
      ],
    );
  }

  Widget _buildStyleCard() {
    final content = _styleCardContent(); // 🆕 context-aware
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmerCtrl, _breatheCtrl]),
        builder: (context, _) {
          final accentColor = context.themeTokens.accent.primary;
          final accentTertiary = context.themeTokens.accent.tertiary;
          final breatheOpacity = 0.10 + 0.10 * _breatheCtrl.value;
          final shimmerAlpha =
              0.5 + 0.5 * math.sin(_shimmerCtrl.value * math.pi * 2);

          return _CardPressable(
            onTap: () => _openChatWithPrompt(content.prompt),
            builder: (isHovered) {
              return Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.20),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _shadowMedium,
                      blurRadius: isHovered ? 52 : 28,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: isHovered ? 0.15 : 0.08,
                      ),
                      blurRadius: 20,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // ── Radial glow background ────────────────────────────
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.8, -0.5),
                            radius: 1.4,
                            colors: [
                              accentColor.withValues(alpha: 0.18),
                              _transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // ── Fashion image — right side with left-edge fade ────
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 110,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              'assets/images/style_card.jpg',
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              filterQuality: FilterQuality.low,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 48,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [_surface, _transparent],
                                  stops: const [0.72, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Animated breathing border overlay ─────────────────
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withValues(alpha: breatheOpacity),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── Shimmer top line ───────────────────────────────────
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _transparent,
                              accentColor.withValues(alpha: 0.55 * shimmerAlpha),
                              accentColor.withValues(alpha: 0.35),
                              _transparent,
                            ],
                            stops: const [0.0, 0.30, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // ── Card content — icon + title + subtitle + CTA ──────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.16 : 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: accentColor.withValues(alpha: 0.18),
                                          width: 1,
                                        ),
                                      ),
                                      child: Icon(
                                        content.icon, // 🆕 dynamic icon
                                        color: isHovered ? accentColor : _textMuted,
                                        size: 18,
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.18 : 0.06,
                                        ),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: isHovered ? 0.30 : 0.15,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Transform.translate(
                                        offset: Offset(isHovered ? 2.0 : 0.0, 0),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: isHovered ? accentColor : _textMuted,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // 🆕 Dynamic title
                                Text(
                                  content.title,
                                  style: TextStyle(
                                    color: _textHeading,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                // 🆕 Dynamic subtitle
                                Text(
                                  content.subtitle,
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w300,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // ── Gradient CTA button — full width pill ────────────
                          _AnimatedPressable(
                            liftY: -2.0,
                            scalePressed: 0.95,
                            onTap: () => _openChatWithPrompt(content.prompt),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [accentColor, accentTertiary],
                                ),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.40),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: accentTertiary.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    content.cta, // 🆕 dynamic CTA
                                    style: TextStyle(
                                      color: _onAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.20,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _onAccent,
                                    size: 11,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSecCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String ctaLabel,  // 🆕 direct label (not a localization key)
    required String intent,
    String? prompt,            // 🆕 optional direct prompt; falls back to _openModuleChat
    String? imageUrl,
    String? assetImage,
  }) {
    final screenH = MediaQuery.of(context).size.height;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmerCtrl, _breatheCtrl]),
        builder: (context, _) {
          // 🔧 Fresh read inside builder — palette switch అయినప్పుడు stale అవ్వవు
          final accentColor = context.themeTokens.accent.primary;
          final accentTertiary = context.themeTokens.accent.tertiary;
          final breatheOpacity = 0.10 + 0.10 * _breatheCtrl.value;
          final shimmerAlpha =
              0.5 + 0.5 * math.sin(_shimmerCtrl.value * math.pi * 2);

          return _CardPressable(
            onTap: () => prompt != null
                ? _openChatWithPrompt(prompt)
                : _openModuleChat(intent),
            builder: (isHovered) {
              return Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.20),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _shadowMedium,
                      blurRadius: isHovered ? 52 : 28,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: isHovered ? 0.15 : 0.08,
                      ),
                      blurRadius: 20,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Radial glow background
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.8, -0.5),
                            radius: 1.4,
                            colors: [
                              accentColor.withValues(alpha: 0.18),
                              _transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Hero-card style: image on right, left-edge fade
                    if (assetImage != null || imageUrl != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 110,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: assetImage != null
                                  ? Image.asset(
                                assetImage,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (_ctx, _err, _st) =>
                                const SizedBox.shrink(),
                              )
                                  : Image.network(
                                imageUrl!,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                cacheWidth:
                                (130 *
                                    MediaQuery.of(
                                      context,
                                    ).devicePixelRatio)
                                    .round(),
                                filterQuality: FilterQuality.low,
                                errorBuilder: (_ctx, _err, _st) =>
                                const SizedBox.shrink(),
                              ),
                            ),
                            // Left fade — blends into card surface
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [_surface, _transparent],
                                    stops: const [0.72, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Animated breathing border overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withValues(
                                alpha: breatheOpacity,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Shimmer top line
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _transparent,
                              accentColor.withValues(
                                alpha: 0.55 * shimmerAlpha,
                              ),
                              accentColor.withValues(alpha: 0.35),
                              _transparent,
                            ],
                            stops: const [0.0, 0.30, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Card content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // Card top content — icon + title + subtitle
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.16 : 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: 0.18,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Icon(
                                        icon,
                                        color: isHovered
                                            ? accentColor
                                            : _textMuted,
                                        size: 18,
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.18 : 0.06,
                                        ),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: isHovered ? 0.30 : 0.15,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Transform.translate(
                                        offset: Offset(
                                          isHovered ? 2.0 : 0.0,
                                          0,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: isHovered
                                              ? accentColor
                                              : _textMuted,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: _textHeading,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w300,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                          ),
                          // Gradient CTA button — full width pill
                          _AnimatedPressable(
                            liftY: -2.0,
                            scalePressed: 0.95,
                            onTap: () => prompt != null
                                ? _openChatWithPrompt(prompt)
                                : _openModuleChat(intent),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accentColor,
                                    context.themeTokens.accent.tertiary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.40),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: context.themeTokens.accent.tertiary
                                        .withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    ctaLabel,
                                    style: TextStyle(
                                      color: _onAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.20,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _onAccent,
                                    size: 11,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
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
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.18),
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
                        color: _accent.withValues(alpha: 0.1),
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
                color: liked ? _accent.withValues(alpha: 0.20) : _shadowStrong,
                border: liked
                    ? Border.all(
                        color: _accent.withValues(alpha: 0.50),
                        width: 1,
                      )
                    : null,
              ),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked
                    ? _accentSecondary
                    : _textHeading.withValues(alpha: 0.7),
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
      onVisualSearch: () => _showComingSoon(),
      onFindSimilar: () => _showComingSoon(),
      onAddToWardrobe: null, // uses showAddToWardrobeModal default in lens sheet
    );
  }

  // ── ChatGPT-style plus menu ───────────────────────────────────────────────
  Widget _buildPlusMenu() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Position it just above the chat bar
    final menuBottom = safeBottom + 86.0 + 72.0 + 8.0;

    final menuItems = [
      (Icons.camera_alt_outlined,       AppLocalizations.t(context, 'plus_menu_camera'),   AppLocalizations.t(context, 'plus_menu_camera_sub')),
      (Icons.photo_library_outlined,    AppLocalizations.t(context, 'plus_menu_gallery'),  AppLocalizations.t(context, 'plus_menu_gallery_sub')),
      (Icons.insert_drive_file_outlined, AppLocalizations.t(context, 'plus_menu_files'),    AppLocalizations.t(context, 'plus_menu_files_sub')),
      (Icons.browse_gallery_outlined,   AppLocalizations.t(context, 'plus_menu_browse'),   AppLocalizations.t(context, 'plus_menu_browse_sub')),
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
                              color: _accent.withValues(alpha: 0.18),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _bgPrimary.withValues(alpha: 0.40),
                                blurRadius: 32,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.08),
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
    // 🆕 Nav labels localized
    final navLabelKeys = [
      'nav_home', 'nav_chat', 'nav_wardrobe', 'nav_planner', 'nav_explore',
    ];
    final items = _homeNavItems;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    const double pillH = 62.0;
    const double maxBulge = 18.0;
    const double totalH = pillH + maxBulge + 6.0;
    const double iconContainerSize = 42.0;
    const double iconSize = 20.0;

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
                                            color: _accent.withValues(alpha: 0.45),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                          BoxShadow(
                                            color: _accent.withValues(alpha: 0.25),
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
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  letterSpacing: -0.01,
                                ),
                                // 🆕 label localized
                                child: Text(AppLocalizations.t(context, navLabelKeys[i])),
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
                  child: Container(color: _bgPrimary.withValues(alpha: 0.92)),
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
                    color: _surface.withValues(alpha: 0.85),
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
                          color: _accent.withValues(alpha: 0.55),
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
                      _accent.withValues(alpha: 0.18),
                      _accentSecondary.withValues(alpha: 0.28),
                    ],
                  ),
                  border: Border.all(color: _accent.withValues(alpha: 0.30)),
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
                      color: _surface.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.10),
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
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
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
              border: Border.all(color: _accent.withValues(alpha: 0.15)),
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
                    _accent.withValues(alpha: 0.18),
                    _accentSecondary.withValues(alpha: 0.28),
                  ],
                ),
                border: Border.all(color: _accent.withValues(alpha: 0.30)),
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
                          onTap: () => _submitQuery(AppLocalizations.t(context, tag)),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width - 60,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.20),
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
        final outfitCardW = (MediaQuery.of(context).size.width * 0.22).clamp(76.0, 96.0);
        final outfitStripH = (MediaQuery.of(context).size.height * 0.185).clamp(138.0, 168.0);
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
                            (outfitCardW * MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        cacheHeight:
                            (outfitStripH * 0.62 * MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_ctx, _err, _st) =>
                            Container(color: _accent.withValues(alpha: 0.1)),
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
                                      color: _accent.withValues(alpha: 0.10),
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
                : _accentTertiary.withValues(alpha: 0.5);
            return Opacity(
              opacity: t.done ? 0.45 : 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _border.withValues(alpha: 0.35)),
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
                              ? _accentTertiary.withValues(alpha: 0.5)
                              : _accent.withValues(alpha: 0.3),
                        ),
                        color: t.done
                            ? _accentTertiary.withValues(alpha: 0.15)
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
            final rows = ((itemCount / 7).ceil()).clamp(1, 6);
            const spacing = 4.0;
            final cellWidth = (constraints.maxWidth - (6 * spacing)) / 7;
            final cellHeight = cellWidth / 0.52;
            final gridHeight = (rows * cellHeight) + ((rows - 1) * spacing);
            return SizedBox(
              height: gridHeight,
              child: GridView.builder(
                itemCount: itemCount,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: 0.52,
                ),
                itemBuilder: (_, index) {
                  final d = resp.weekDays[index];
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: d.isToday
                          ? _accent.withValues(alpha: 0.10)
                          : _bgPrimary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: d.isToday
                            ? _accent.withValues(alpha: 0.25)
                            : _border.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          d.day,
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            color: d.isToday ? _accent : _textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          d.label.split(' ').last,
                          style: TextStyle(fontSize: 6.5, color: _textMuted),
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
                                  color: _accent.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  it,
                                  style: TextStyle(
                                    fontSize: 5.5,
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
                        color: _border.withValues(alpha: 0.35),
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
                                  color: _accentTertiary.withValues(alpha: 0.12),
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
                                      errorBuilder: (_ctx, _err, _st) => Container(
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
                                            color: _border.withValues(
                                              alpha: 0.85,
                                            ),
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
                                      hintText: AppLocalizations.t(context, 'checklist_add_item'),
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
                      const boards = [
                        '🎉 Party Looks',
                        '💍 Occasion',
                        '💼 Office Fit',
                        '✈️ Vacation',
                        '✨ Everything Else',
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
                                AppLocalizations.t(context, 'board_save_subtitle'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...boards.map(
                                (label) => GestureDetector(
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
                                        if (label.contains('Vacation'))
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
                                              AppLocalizations.t(context, 'board_suggested_badge'),
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
                                ),
                              ),
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
                            ? LinearGradient(
                                colors: [_accent, _accentTertiary],
                              )
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
                            isListSaved ? AppLocalizations.t(context, 'checklist_saved') : AppLocalizations.t(context, 'checklist_save_to_board'),
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
              border: Border.all(
                color: _accent.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.15),
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
                      color: _accent.withValues(alpha: 0.25),
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
                            color: _accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.20),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(context, 'pick_sheet_save_to_board'),
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
                                color: _accent.withValues(alpha: 0.35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(context, 'pick_sheet_style_this'),
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
        'Athleisure',
        'Sport · Morning',
        'https://images.unsplash.com/photo-1538805060514-97d9cc17730c?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        'Resort Wear',
        'Vacation · Breezy',
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
                                color: _accent.withValues(alpha: 0.20),
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
                          AppLocalizations.t(context, 'picks_section_title'), // 🆕
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
                                    errorBuilder: (_ctx, _err, _st) => Container(
                                      color: _accent.withValues(alpha: 0.1),
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
                  color: _bgSecondary.withValues(alpha: 0.92),
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
}

// ── Plus Menu Item ────────────────────────────────────────────────────────────
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
                ? widget.accent.withValues(alpha: 0.08)
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
                        color: widget.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.accent.withValues(alpha: 0.20),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.accent,
                        size: 18,
                      ),
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
            color: widget.border.withValues(alpha: 0.6),
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
          ..color = glowColor.withValues(alpha: 0.12 * bulgeT)
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
    suggestions: [
      'intent_style_s1',
      'intent_style_s2',
      'intent_style_s3',
    ],
    brandSub: 'intent_style_sub',
    responseTags: ['intent_style_tag1', 'intent_style_tag2', 'intent_style_tag3'],
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
    responseTags: ['intent_prepare_tag1', 'intent_prepare_tag2', 'intent_prepare_tag3'],
  ),
  'chat': _IntentConfig(
    suggestions: [
      'intent_chat_s1',
      'intent_chat_s2',
      'intent_chat_s3',
    ],
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
                ? widget.accent.withValues(alpha: 0.15)
                : widget.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _active
                  ? Colors.transparent
                  : hovered
                  ? widget.accent.withValues(alpha: 0.5)
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
        color: accent.withValues(alpha: 0.10),
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
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Color textHeading;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  State<_RoutineItem> createState() => _RoutineItemState();
}

class _RoutineItemState extends State<_RoutineItem> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _pressed || _hovered;
    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.value}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? widget.color.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Icon bubble ──────────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isActive
                        ? widget.color.withValues(alpha: 0.22)
                        : widget.color.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, size: 13, color: widget.color),
                ),
                const SizedBox(width: 8),

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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: -0.1,
                        ),
                      ),
                      Text(
                        widget.value,
                        style: TextStyle(
                          color: widget.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // ── Chevron ──────────────────────────────────────────────
                AnimatedSlide(
                  offset: isActive ? const Offset(0.15, 0) : Offset.zero,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: widget.color.withValues(alpha: isActive ? 0.90 : 0.50),
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
