import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
// theme_tokens.dart — use package import below if in a sub-folder
// Update this path to match your project structure, e.g.:
// import 'package:your_app/theme/theme_tokens.dart';
import 'theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';

// ─── THEME COLORS ────────────────────────────────────────────────────────────
// NOTE: kAccent and meal-type colors remain constant (not theme-dependent)
const Color kAccent = Color(0xFF7B6EF6);

// ─── THEME HELPERS ───────────────────────────────────────────────────────────
// Use these in build() methods instead of old hardcoded constants
extension DietTheme on BuildContext {
  AppThemeTokens get _t => Theme.of(this).extension<AppThemeTokens>()!;
  Color get dBg => _t.backgroundPrimary;
  Color get dText => _t.textPrimary;
  Color get dText2 => _t.textPrimary.withValues(alpha: 0.85);
  Color get dMuted => _t.mutedText;
  Color get dSurface => _t.backgroundSecondary;
  Color get dSurface2 => _t.card;
  Color get dBorder => _t.cardBorder;
  Color get dPanel => _t.panel;
  Color get dPanelBorder => _t.panelBorder;
  Color get dAccent => _t.accent.primary;
  Color get dAccent2 => _t.accent.secondary;
  Color get dSnackBg => _t.backgroundPrimary.computeLuminance() > 0.5
      ? const Color(0xFF1C1C1E)
      : const Color(0xFF2C2C2E);
}

const Color kBreakfastFg = Color(0xFFB85500);
const Color kBreakfastBg = Color(0xFFFFF4EE);
const Color kLunchFg = Color(0xFF1A7A35);
const Color kLunchBg = Color(0xFFF0FAF2);
const Color kDinnerFg = Color(0xFF3634A3);
const Color kDinnerBg = Color(0xFFF0F0FD);
const Color kSnackFg = Color(0xFFB8003A);
const Color kSnackBg = Color(0xFFFFF0F5);

// ─── DATA MODELS ─────────────────────────────────────────────────────────────
class Meal {
  String type;
  String name;
  String desc;
  int cal;
  int protein;
  int carbs;
  int fat;
  String cls;
  String icon;
  String? imagePath; // Local path or URL
  Meal({
    required this.type,
    required this.name,
    required this.desc,
    required this.cal,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    required this.cls,
    this.icon = '',
    this.imagePath,
  });
  Meal copyWith({
    String? type,
    String? name,
    String? desc,
    int? cal,
    int? protein,
    int? carbs,
    int? fat,
    String? imagePath,
  }) {
    return Meal(
      type: type ?? this.type,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      cal: cal ?? this.cal,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      cls: cls,
      icon: icon,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'desc': desc,
    'cal': cal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'cls': cls,
    'icon': icon,
    'imagePath': imagePath,
  };
  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
    type: j['type'] ?? '',
    name: j['name'] ?? '',
    desc: j['desc'] ?? '',
    cal: j['cal'] ?? 0,
    protein: j['protein'] ?? 0,
    carbs: j['carbs'] ?? 0,
    fat: j['fat'] ?? 0,
    cls: j['cls'] ?? '',
    icon: j['icon'] ?? '',
    imagePath: j['imagePath'],
  );
}

class DayPlan {
  final String label; // e.g. "Monday" or "Week 1"
  final List<Meal> meals;
  DayPlan({required this.label, required this.meals});
}

class MealPlan {
  int id;
  String name;
  String desc;
  String planType; // daily / weekly / monthly
  List<Meal> meals; // used for daily
  List<DayPlan> days; // used for weekly (7) / monthly (4)
  MealPlan({
    required this.id,
    required this.name,
    required this.desc,
    required this.planType,
    required this.meals,
    this.days = const [],
  });
  int get totalCal => planType == 'daily'
      ? meals.fold(0, (a, m) => a + m.cal)
      : days.fold(0, (a, d) => a + d.meals.fold(0, (b, m) => b + m.cal));
  int get totalProtein => planType == 'daily'
      ? meals.fold(0, (a, m) => a + m.protein)
      : days.fold(0, (a, d) => a + d.meals.fold(0, (b, m) => b + m.protein));
  MealPlan copyWith({
    String? name,
    String? desc,
    String? planType,
    List<Meal>? meals,
    List<DayPlan>? days,
  }) {
    return MealPlan(
      id: id,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      planType: planType ?? this.planType,
      meals: meals ?? this.meals,
      days: days ?? this.days,
    );
  }
}

class ChatMessage {
  final String text;
  final bool isBot;
  MealPlan? plan;
  ChatMessage({required this.text, required this.isBot, this.plan});
}

// ─── IMAGE PROVIDER (Wikipedia / TheMealDB API) ──────────────────────────────
class MealImageProvider {
  static final Map<String, String> _cache = {};
  static Future<String?> fetchImage(String mealName) async {
    final query = mealName.toLowerCase().trim();
    if (query.isEmpty) return null;
    if (_cache.containsKey(query)) return _cache[query];
    // Tier 1: TheMealDB
    try {
      final decodedQuery = query
          .replaceFirst(RegExp(r'^\🌅|^\☀️|^\🌙|^\🍎'), '')
          .trim();
      final nameUri = Uri.encodeComponent(
        decodedQuery.split(' ').take(2).join(' '),
      );
      final res = await http
          .get(
            Uri.parse(
              'https://www.themealdb.com/api/json/v1/1/search.php?s=$nameUri',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final meal = data['meals']?[0];
        if (meal != null && meal['strMealThumb'] != null) {
          _cache[query] = meal['strMealThumb'];
          return meal['strMealThumb'];
        }
      }
    } catch (_) {}
    // Tier 2: Wikipedia Summary API
    try {
      final wikiUri = Uri.encodeComponent(query);
      final res = await http
          .get(
            Uri.parse(
              'https://en.wikipedia.org/api/rest_v1/page/summary/$wikiUri',
            ),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final imgUrl =
            data['thumbnail']?['source'] ?? data['originalimage']?['source'];
        if (imgUrl != null) {
          final formatted = imgUrl.toString().replaceFirst(
            RegExp(r'\/\d+px-'),
            '/480px-',
          );
          _cache[query] = formatted;
          return formatted;
        }
      }
    } catch (_) {}
    // Tier 3: Unsplash source (no API key needed)
    try {
      final unsplashQuery = Uri.encodeComponent(
        query.split(' ').take(2).join(' '),
      );
      final url = 'https://source.unsplash.com/400x300/?$unsplashQuery,food';
      _cache[query] = url;
      return url;
    } catch (_) {}
    return null;
  }
}

// ─── MAIN SCREEN ─────────────────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isChatOpen = false;
  final List<MealPlan> _plans = [];
  final _plansMessengerKey = GlobalKey<ScaffoldMessengerState>();

  void _showSnack(SnackBar snack) {
    _plansMessengerKey.currentState?.showSnackBar(snack);
  }

  void _addPlan(MealPlan p) {
    setState(() {
      _plans.add(
        MealPlan(
          id: DateTime.now().millisecondsSinceEpoch,
          name: p.name,
          desc: p.desc,
          planType: p.planType,
          meals: List.from(p.meals),
        ),
      );
    });
  }

  void _savePlanFromChat(MealPlan p) {
    final plan = MealPlan(
      id: DateTime.now().millisecondsSinceEpoch,
      name: p.name,
      desc: p.desc,
      planType: p.planType,
      meals: List.from(p.meals),
    );
    setState(() => _plans.add(plan));
    _showSnack(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF30D158), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${plan.name}" ${AppLocalizations.t(context, 'diet_saved_to_plans')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: context.dSnackBg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deletePlan(int id) {
    setState(() => _plans.removeWhere((p) => p.id == id));
  }

  void _editPlan(MealPlan updated) {
    setState(() {
      final idx = _plans.indexWhere((p) => p.id == updated.id);
      if (idx != -1) _plans[idx] = updated;
    });
    _showSnack(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.edit_note_rounded,
              color: Color(0xFFFFD60A),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${updated.name}" ${AppLocalizations.t(context, 'diet_updated_successfully')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: context.dSnackBg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.dBg,
      body: Stack(
        children: [
          PlansScreen(
            plans: _plans,
            onAdd: _addPlan,
            onDelete: _deletePlan,
            onEdit: _editPlan,
            messengerKey: _plansMessengerKey,
          ),

          if (!_isChatOpen)
            Positioned(
              bottom: 30,
              right: 20,
              child: _AskAhviFab(
                onTap: () => setState(() => _isChatOpen = true),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOutCubic,
            left: 0,
            right: 0,
            top: _isChatOpen ? 0 : MediaQuery.of(context).size.height,
            bottom: _isChatOpen ? 0 : -MediaQuery.of(context).size.height,
            child: _DietChatPanel(
              onSavePlan: (p) {
                _savePlanFromChat(p);
                setState(() => _isChatOpen = false);
              },
              onClose: () => setState(() => _isChatOpen = false),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PLANS SCREEN ─────────────────────────────────────────────────────────────
class PlansScreen extends StatefulWidget {
  final List<MealPlan> plans;
  final ValueChanged<MealPlan> onAdd;
  final ValueChanged<int> onDelete;
  final ValueChanged<MealPlan> onEdit;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  const PlansScreen({
    super.key,
    required this.plans,
    required this.onAdd,
    required this.onDelete,
    required this.onEdit,
    required this.messengerKey,
  });
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String _filter = 'all';
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered = _filter == 'all'
        ? widget.plans
        : widget.plans.where((p) => p.planType == _filter).toList();
    return ScaffoldMessenger(
      key: widget.messengerKey,
      child: Scaffold(
        backgroundColor: context.dBg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showAddModal(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: context.dAccent,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D6C63FF),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              AppLocalizations.t(
                                context,
                                'diet_add_custom_meal',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterTabs(
                      selected: _filter,
                      onSelect: (v) => setState(() => _filter = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: widget.plans.isEmpty
                    ? _emptyState(false)
                    : filtered.isEmpty
                    ? _emptyState(true)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => PlanCard(
                          plan: filtered[i],
                          onDelete: () => widget.onDelete(filtered[i].id),
                          onEdit: () => _showEditModal(context, filtered[i]),
                          messengerKey: widget.messengerKey,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool isFilter) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(isFilter ? '🔍' : '🥗', style: const TextStyle(fontSize: 42)),
          const SizedBox(height: 10),
          Text(
            isFilter
                ? AppLocalizations.t(context, 'diet_no_filter')
                : AppLocalizations.t(context, 'diet_no_plans'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.dMuted, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _showAddModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddMealModal(
        messengerKey: widget.messengerKey,
        onSave: (plan) {
          widget.onAdd(plan);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditModal(BuildContext context, MealPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditMealModal(
        plan: plan,
        messengerKey: widget.messengerKey,
        onSave: (updated) {
          widget.onEdit(updated);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  String _weekday(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _month(int m) => [
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
  ][m - 1];
}

class _FilterTabs extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _FilterTabs({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('all', '⊞', AppLocalizations.t(context, 'diet_all_plans')),
      ('daily', '☀️', AppLocalizations.t(context, 'diet_filter_daily')),
      ('weekly', '📅', AppLocalizations.t(context, 'diet_filter_weekly')),
      ('monthly', '📆', AppLocalizations.t(context, 'diet_filter_monthly')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((t) {
          final active = selected == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? context.dAccent : context.dSurface,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: active ? context.dAccent : context.dBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Text(t.$2, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text(
                      t.$3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : context.dText2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final Meal m;
  const _MealRow({required this.m});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.dBorder)),
      ),
      child: Row(
        children: [
          _MealImage(imagePath: m.imagePath, emoji: m.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  m.type,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.dMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${m.cal} cal',
            style: TextStyle(
              fontSize: 12,
              color: context.dMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class PlanCard extends StatelessWidget {
  final MealPlan plan;
  final VoidCallback onDelete;
  final bool isSuggestion;
  final ValueChanged<MealPlan>? onSave;
  final VoidCallback? onEdit;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  const PlanCard({
    super.key,
    required this.plan,
    required this.onDelete,
    this.isSuggestion = false,
    this.onSave,
    this.onEdit,
    this.messengerKey,
  });

  void _showToast(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String message,
  }) {
    final messenger =
        messengerKey?.currentState ?? ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: context.dSnackBg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = plan.planType.toLowerCase();
    final isWeekly = type == 'weekly';
    final isMonthly = type == 'monthly';
    final Color topBgStart = isWeekly
        ? const Color(0xFFB2E0D8)
        : (isMonthly ? const Color(0xFFB8D4F5) : const Color(0xFFF7C5C5));
    final Color topBgEnd = isWeekly
        ? const Color(0xFFC8EED6)
        : (isMonthly ? const Color(0xFFC8C8F8) : const Color(0xFFF9D8C8));
    final Color titleColor = isWeekly
        ? const Color(0xFF164A38)
        : (isMonthly ? const Color(0xFF1A2E6A) : const Color(0xFF7A2020));
    final Color typePillColor = isWeekly
        ? const Color(0xFF2A6E5E)
        : (isMonthly ? const Color(0xFF2A4A8A) : const Color(0xFFA04040));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.dSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [topBgStart, topBgEnd]),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
                      color: typePillColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isSuggestion) ...[
                  GestureDetector(
                    onTap: () {
                      _showToast(
                        context,
                        icon: Icons.edit_note_rounded,
                        iconColor: const Color(0xFFFFD60A),
                        message:
                            '${AppLocalizations.t(context, 'diet_editing')} "${plan.name}"...',
                      );
                      onEdit?.call();
                    },
                    child: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: typePillColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: ctx.dSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Text(
                            AppLocalizations.t(context, 'diet_delete_plan'),
                            style: TextStyle(
                              color: ctx.dText,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          content: Text(
                            AppLocalizations.t(
                              context,
                              'diet_delete_confirm',
                            ).replaceAll('{name}', plan.name),
                            style: TextStyle(
                              color: ctx.dMuted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                AppLocalizations.t(context, 'common_cancel'),
                                style: TextStyle(
                                  color: ctx.dMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showToast(
                                  context,
                                  icon: Icons.delete_forever_rounded,
                                  iconColor: const Color(0xFFFF453A),
                                  message: '"${plan.name}" deleted!',
                                );
                                onDelete();
                              },
                              child: Text(
                                AppLocalizations.t(context, 'common_delete'),
                                style: const TextStyle(
                                  color: Color(0xFFFF453A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Icon(
                      Icons.delete_sweep_outlined,
                      size: 18,
                      color: typePillColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (plan.planType == 'daily')
            ...plan.meals.map((m) => _MealRow(m: m))
          else
            ...plan.days.map(
              (day) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    color: typePillColor.withValues(alpha: 0.08),
                    child: Text(
                      day.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: typePillColor,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  ...day.meals.map((m) => _MealRow(m: m)),
                ],
              ),
            ),
          if (isSuggestion)
            Container(
              padding: const EdgeInsets.all(10),
              color: context.dSurface2,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: context.dSurface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.dAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: context.dAccent,
                            ),
                            SizedBox(width: 5),
                            Text(
                              AppLocalizations.t(context, 'common_edit'),
                              style: TextStyle(
                                color: context.dAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => onSave?.call(plan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: context.dAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            AppLocalizations.t(context, 'diet_save_suggestion'),
                            style: TextStyle(
                              color: Colors.white,
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
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              color: context.dSurface2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${AppLocalizations.t(context, 'diet_total')}: ${plan.totalCal} ${AppLocalizations.t(context, 'diet_cal')}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
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

class AddMealModal extends StatefulWidget {
  final ValueChanged<MealPlan> onSave;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  const AddMealModal({
    super.key,
    required this.onSave,
    required this.messengerKey,
  });
  @override
  State<AddMealModal> createState() => _AddMealModalState();
}

class _AddMealModalState extends State<AddMealModal> {
  final _nameCtrl = TextEditingController();
  final String _planType = 'daily';
  bool _isSaved = false;
  final _bNameCtrl = TextEditingController(),
      _lNameCtrl = TextEditingController(),
      _dNameCtrl = TextEditingController(),
      _sNameCtrl = TextEditingController();
  final _bCalCtrl = TextEditingController(),
      _lCalCtrl = TextEditingController(),
      _dCalCtrl = TextEditingController(),
      _sCalCtrl = TextEditingController();
  String? _bImg, _lImg, _dImg, _sImg;

  // Local messenger key — toasts appear INSIDE the modal, not behind it
  final _localKey = GlobalKey<ScaffoldMessengerState>();

  void _toast({
    required IconData icon,
    required Color iconColor,
    required String msg,
  }) {
    _localKey.currentState?.clearSnackBars();
    _localKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: context.dSnackBg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast(
        icon: Icons.warning_amber_rounded,
        iconColor: const Color(0xFFFFD60A),
        msg: AppLocalizations.t(context, 'diet_enter_plan_name'),
      );
      return;
    }
    final meals = <Meal>[];
    void add(
      String type,
      String cls,
      String icon,
      TextEditingController n,
      TextEditingController c,
      String? img,
    ) {
      if (n.text.trim().isNotEmpty)
        meals.add(
          Meal(
            type: type,
            cls: cls,
            icon: icon,
            name: n.text.trim(),
            desc: '',
            cal: int.tryParse(c.text.trim()) ?? 0,
            imagePath: img,
          ),
        );
    }

    add('Breakfast', 'breakfast', '🌅', _bNameCtrl, _bCalCtrl, _bImg);
    add('Lunch', 'lunch', '☀️', _lNameCtrl, _lCalCtrl, _lImg);
    add('Dinner', 'dinner', '🌙', _dNameCtrl, _dCalCtrl, _dImg);
    add('Snack', 'snack', '🍎', _sNameCtrl, _sCalCtrl, _sImg);
    if (meals.isEmpty) {
      _toast(
        icon: Icons.restaurant_outlined,
        iconColor: const Color(0xFFFF9F0A),
        msg: AppLocalizations.t(context, 'diet_add_meal_entry'),
      );
      return;
    }
    setState(() => _isSaved = true);
    widget.onSave(
      MealPlan(id: 0, name: name, desc: '', planType: _planType, meals: meals),
    );
    _toast(
      icon: Icons.check_circle,
      iconColor: const Color(0xFF30D158),
      msg: '"$name" plan saved successfully!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _localKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, sc) {
            return Container(
              decoration: BoxDecoration(
                color: context.dSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.dBorder),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.t(
                              context,
                              'diet_add_custom_meal_plan',
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  // Scrollable body
                  Expanded(
                    child: ListView(
                      controller: sc,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          AppLocalizations.t(context, 'diet_plan_name'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.t(
                              context,
                              'diet_plan_hint',
                            ),
                            filled: true,
                            fillColor: context.dSurface2,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: context.dBorder,
                                width: 1.5,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: context.dBorder,
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: context.dAccent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppLocalizations.t(context, 'diet_plan_type'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: context.dAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.dAccent),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(context, 'diet_daily'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.dAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          AppLocalizations.t(context, 'diet_meals'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _MealEntry(
                          label: AppLocalizations.t(context, 'diet_breakfast'),
                          emoji: '🌅',
                          color: kBreakfastFg,
                          bg: kBreakfastBg,
                          nameCtrl: _bNameCtrl,
                          calCtrl: _bCalCtrl,
                          imagePath: _bImg,
                          onImageChanged: (v) => setState(() => _bImg = v),
                        ),
                        _MealEntry(
                          label: AppLocalizations.t(context, 'diet_lunch'),
                          emoji: '☀️',
                          color: kLunchFg,
                          bg: kLunchBg,
                          nameCtrl: _lNameCtrl,
                          calCtrl: _lCalCtrl,
                          imagePath: _lImg,
                          onImageChanged: (v) => setState(() => _lImg = v),
                        ),
                        _MealEntry(
                          label: AppLocalizations.t(context, 'diet_dinner'),
                          emoji: '🌙',
                          color: kDinnerFg,
                          bg: kDinnerBg,
                          nameCtrl: _dNameCtrl,
                          calCtrl: _dCalCtrl,
                          imagePath: _dImg,
                          onImageChanged: (v) => setState(() => _dImg = v),
                        ),
                        _MealEntry(
                          label: AppLocalizations.t(context, 'diet_snack'),
                          emoji: '🍎',
                          color: kSnackFg,
                          bg: kSnackBg,
                          nameCtrl: _sNameCtrl,
                          calCtrl: _sCalCtrl,
                          imagePath: _sImg,
                          onImageChanged: (v) => setState(() => _sImg = v),
                        ),
                        const SizedBox(height: 30),
                        GestureDetector(
                          onTap: _isSaved ? null : _save,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: _isSaved
                                  ? const Color(0xFF1A7A35)
                                  : context.dAccent,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_isSaved
                                              ? const Color(0xFF1A7A35)
                                              : context.dAccent)
                                          .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSaved) ...[
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    _isSaved
                                        ? AppLocalizations.t(
                                            context,
                                            'diet_plan_saved',
                                          )
                                        : AppLocalizations.t(
                                            context,
                                            'diet_save_my_plan',
                                          ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ], // ListView children
                    ), // ListView
                  ), // Expanded
                ], // Column children
              ), // Column
            ); // Container
          }, // builder
        ), // DraggableScrollableSheet
      ), // Scaffold
    ); // ScaffoldMessenger
  }
}

class _MealEntry extends StatefulWidget {
  final String label, emoji;
  final Color color, bg;
  final TextEditingController nameCtrl, calCtrl;
  final String? imagePath;
  final ValueChanged<String?> onImageChanged;
  const _MealEntry({
    required this.label,
    required this.emoji,
    required this.color,
    required this.bg,
    required this.nameCtrl,
    required this.calCtrl,
    required this.imagePath,
    required this.onImageChanged,
  });
  @override
  State<_MealEntry> createState() => _MealEntryState();
}

class _MealEntryState extends State<_MealEntry> {
  bool _fetching = false;
  Future<void> _autoFetch() async {
    final name = widget.nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _fetching = true);
    final url = await MealImageProvider.fetchImage(name);
    if (mounted) {
      setState(() => _fetching = false);
      if (url != null) widget.onImageChanged(url);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.nameCtrl.addListener(_onNameChanged);
  }

  String _lastFetched = '';
  void _onNameChanged() {
    final name = widget.nameCtrl.text.trim();
    if (name.length > 3 && name != _lastFetched) {
      _lastFetched = name;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (widget.nameCtrl.text.trim() == name && mounted) _autoFetch();
      });
    }
  }

  @override
  void dispose() {
    widget.nameCtrl.removeListener(_onNameChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.dSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 17)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _fetching ? null : _autoFetch,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.dAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _fetching
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: context.dAccent,
                          ),
                        )
                      : Icon(
                          Icons.auto_fix_high,
                          size: 14,
                          color: context.dAccent,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 90,
            decoration: BoxDecoration(
              color: widget.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.dBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.imagePath != null
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: _MealImage(
                          imagePath: widget.imagePath,
                          emoji: widget.emoji,
                          size: 90,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => widget.onImageChanged(null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black26,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _fetching
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.dAccent,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          AppLocalizations.t(context, 'diet_fetching_image'),
                          style: TextStyle(fontSize: 10, color: context.dMuted),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(widget.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.t(context, 'diet_type_name_hint'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.color.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.nameCtrl,
            decoration: InputDecoration(
              hintText: AppLocalizations.t(context, 'diet_meal_name_hint'),
              filled: true,
              fillColor: context.dSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.dBorder),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.calCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: AppLocalizations.t(context, 'diet_cal_hint'),
              suffixText: 'cal',
              filled: true,
              fillColor: context.dSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.dBorder),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DietChatPanel extends StatefulWidget {
  final ValueChanged<MealPlan> onSavePlan;
  final VoidCallback onClose;
  const _DietChatPanel({
    super.key,
    required this.onSavePlan,
    required this.onClose,
  });
  @override
  State<_DietChatPanel> createState() => _DietChatPanelState();
}

class _DietChatPanelState extends State<_DietChatPanel> {
  final _msgCtrl = TextEditingController();
  final _msgFocus = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _chatHistory = [];
  bool _isTyping = false;
  OverlayEntry? _overlay;

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  // ── Voice ──────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _messages.isEmpty) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: AppLocalizations.t(context, 'diet_chat_welcome'),
              isBot: true,
            ),
          );
        });
      }
    });
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (e) {
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
            _msgCtrl.text = result.recognizedWords;
            _msgCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _msgCtrl.text.length),
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
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _msgCtrl.dispose();
    _msgFocus.dispose();
    _removeOverlay();
    super.dispose();
  }

  // Detect plan type from user message
  String _detectPlanType(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('monthly') || m.contains('month')) return 'monthly';
    if (m.contains('weekly') || m.contains('week')) return 'weekly';
    return 'daily';
  }

  // All meals pool per diet (varied for each day)
  List<List<Meal>> _mealPool(String diet) {
    switch (diet) {
      case 'mediterranean':
        return [
          [
            Meal(
              type: 'Breakfast',
              name: 'Greek Yogurt with Honey',
              desc: '',
              cal: 320,
              protein: 18,
              carbs: 38,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Greek Chicken Salad',
              desc: '',
              cal: 520,
              protein: 42,
              carbs: 28,
              fat: 22,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Baked Sea Bass',
              desc: '',
              cal: 480,
              protein: 38,
              carbs: 20,
              fat: 18,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Hummus with Pita',
              desc: '',
              cal: 210,
              protein: 8,
              carbs: 26,
              fat: 9,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Shakshuka Eggs',
              desc: '',
              cal: 310,
              protein: 20,
              carbs: 22,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Falafel Wrap',
              desc: '',
              cal: 490,
              protein: 18,
              carbs: 58,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Lamb Kofta with Rice',
              desc: '',
              cal: 560,
              protein: 40,
              carbs: 42,
              fat: 20,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Olives & Feta Cheese',
              desc: '',
              cal: 180,
              protein: 6,
              carbs: 4,
              fat: 16,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Avocado Toast with Egg',
              desc: '',
              cal: 350,
              protein: 16,
              carbs: 32,
              fat: 18,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Tabbouleh Salad',
              desc: '',
              cal: 380,
              protein: 12,
              carbs: 48,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Grilled Swordfish',
              desc: '',
              cal: 500,
              protein: 44,
              carbs: 16,
              fat: 20,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Tzatziki with Veggies',
              desc: '',
              cal: 140,
              protein: 8,
              carbs: 10,
              fat: 7,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Oat Porridge with Dates',
              desc: '',
              cal: 340,
              protein: 10,
              carbs: 55,
              fat: 7,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Stuffed Bell Peppers',
              desc: '',
              cal: 430,
              protein: 22,
              carbs: 46,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Chicken Souvlaki',
              desc: '',
              cal: 510,
              protein: 42,
              carbs: 30,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Mixed Nuts',
              desc: '',
              cal: 200,
              protein: 6,
              carbs: 8,
              fat: 17,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Labneh with Herbs',
              desc: '',
              cal: 280,
              protein: 14,
              carbs: 18,
              fat: 16,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Lemon Herb Couscous',
              desc: '',
              cal: 460,
              protein: 16,
              carbs: 62,
              fat: 12,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Prawn Pasta',
              desc: '',
              cal: 540,
              protein: 36,
              carbs: 52,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Fresh Fruit Plate',
              desc: '',
              cal: 120,
              protein: 2,
              carbs: 28,
              fat: 1,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Spinach Feta Omelette',
              desc: '',
              cal: 330,
              protein: 22,
              carbs: 8,
              fat: 22,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Hummus Pita Bowl',
              desc: '',
              cal: 420,
              protein: 16,
              carbs: 54,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Moussaka',
              desc: '',
              cal: 580,
              protein: 30,
              carbs: 44,
              fat: 28,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Grape & Walnut Mix',
              desc: '',
              cal: 190,
              protein: 4,
              carbs: 24,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Banana Almond Smoothie',
              desc: '',
              cal: 300,
              protein: 12,
              carbs: 42,
              fat: 10,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Nicoise Salad',
              desc: '',
              cal: 440,
              protein: 30,
              carbs: 28,
              fat: 22,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Herb Roasted Chicken',
              desc: '',
              cal: 520,
              protein: 48,
              carbs: 14,
              fat: 24,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Cucumber Yogurt Dip',
              desc: '',
              cal: 130,
              protein: 7,
              carbs: 12,
              fat: 5,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
        ];
      case 'vegan':
        return [
          [
            Meal(
              type: 'Breakfast',
              name: 'Smoothie Bowl',
              desc: '',
              cal: 350,
              protein: 12,
              carbs: 52,
              fat: 10,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Lentil Buddha Bowl',
              desc: '',
              cal: 490,
              protein: 22,
              carbs: 68,
              fat: 12,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Black Bean Tacos',
              desc: '',
              cal: 450,
              protein: 20,
              carbs: 62,
              fat: 14,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Mixed Nuts & Berries',
              desc: '',
              cal: 180,
              protein: 5,
              carbs: 18,
              fat: 11,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Chia Seed Pudding',
              desc: '',
              cal: 320,
              protein: 10,
              carbs: 38,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Chickpea Curry',
              desc: '',
              cal: 480,
              protein: 20,
              carbs: 66,
              fat: 12,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Tofu Stir Fry',
              desc: '',
              cal: 420,
              protein: 22,
              carbs: 44,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Apple with Almond Butter',
              desc: '',
              cal: 190,
              protein: 4,
              carbs: 24,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Oat & Banana Pancakes',
              desc: '',
              cal: 360,
              protein: 10,
              carbs: 58,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Quinoa Veggie Bowl',
              desc: '',
              cal: 470,
              protein: 18,
              carbs: 62,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Mushroom Pasta',
              desc: '',
              cal: 460,
              protein: 16,
              carbs: 70,
              fat: 12,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Edamame',
              desc: '',
              cal: 150,
              protein: 12,
              carbs: 12,
              fat: 5,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Avocado Toast',
              desc: '',
              cal: 330,
              protein: 8,
              carbs: 36,
              fat: 18,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Sweet Potato Soup',
              desc: '',
              cal: 380,
              protein: 8,
              carbs: 60,
              fat: 10,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Vegetable Biryani',
              desc: '',
              cal: 490,
              protein: 14,
              carbs: 78,
              fat: 12,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Roasted Chickpeas',
              desc: '',
              cal: 160,
              protein: 8,
              carbs: 22,
              fat: 4,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Acai Bowl',
              desc: '',
              cal: 380,
              protein: 8,
              carbs: 60,
              fat: 12,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Falafel Wrap',
              desc: '',
              cal: 460,
              protein: 16,
              carbs: 58,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Cauliflower Tikka Masala',
              desc: '',
              cal: 430,
              protein: 14,
              carbs: 54,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Dates & Walnuts',
              desc: '',
              cal: 200,
              protein: 3,
              carbs: 28,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Green Detox Smoothie',
              desc: '',
              cal: 280,
              protein: 8,
              carbs: 42,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Tempeh Grain Bowl',
              desc: '',
              cal: 500,
              protein: 24,
              carbs: 60,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Lentil Soup with Bread',
              desc: '',
              cal: 420,
              protein: 18,
              carbs: 64,
              fat: 8,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Fruit & Seed Mix',
              desc: '',
              cal: 170,
              protein: 4,
              carbs: 26,
              fat: 7,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Coconut Yogurt Parfait',
              desc: '',
              cal: 310,
              protein: 6,
              carbs: 48,
              fat: 10,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Mango Tofu Salad',
              desc: '',
              cal: 440,
              protein: 18,
              carbs: 52,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Veggie Burger',
              desc: '',
              cal: 460,
              protein: 20,
              carbs: 56,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Kale Chips',
              desc: '',
              cal: 120,
              protein: 3,
              carbs: 14,
              fat: 6,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
        ];
      case 'highprotein':
        return [
          [
            Meal(
              type: 'Breakfast',
              name: 'Egg White Omelette',
              desc: '',
              cal: 310,
              protein: 32,
              carbs: 12,
              fat: 10,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Grilled Chicken Rice Bowl',
              desc: '',
              cal: 580,
              protein: 52,
              carbs: 45,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Salmon with Quinoa',
              desc: '',
              cal: 520,
              protein: 48,
              carbs: 32,
              fat: 18,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Cottage Cheese with Almonds',
              desc: '',
              cal: 220,
              protein: 20,
              carbs: 8,
              fat: 12,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Protein Pancakes',
              desc: '',
              cal: 360,
              protein: 30,
              carbs: 28,
              fat: 10,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Turkey Quinoa Bowl',
              desc: '',
              cal: 560,
              protein: 50,
              carbs: 40,
              fat: 12,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Tuna Steak & Veggies',
              desc: '',
              cal: 490,
              protein: 52,
              carbs: 16,
              fat: 18,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Greek Yogurt & Nuts',
              desc: '',
              cal: 230,
              protein: 18,
              carbs: 14,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Scrambled Eggs & Turkey',
              desc: '',
              cal: 380,
              protein: 36,
              carbs: 10,
              fat: 18,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Beef & Broccoli',
              desc: '',
              cal: 540,
              protein: 48,
              carbs: 28,
              fat: 20,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Chicken Tikka Masala',
              desc: '',
              cal: 510,
              protein: 46,
              carbs: 30,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Hard Boiled Eggs',
              desc: '',
              cal: 160,
              protein: 14,
              carbs: 2,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Whey Protein Smoothie',
              desc: '',
              cal: 300,
              protein: 34,
              carbs: 24,
              fat: 6,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Shrimp Stir Fry',
              desc: '',
              cal: 490,
              protein: 44,
              carbs: 36,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Lean Beef Meatballs',
              desc: '',
              cal: 530,
              protein: 50,
              carbs: 24,
              fat: 22,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Tuna on Rice Cakes',
              desc: '',
              cal: 190,
              protein: 22,
              carbs: 16,
              fat: 4,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Smoked Salmon Bagel',
              desc: '',
              cal: 400,
              protein: 28,
              carbs: 36,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Chicken Caesar Salad',
              desc: '',
              cal: 520,
              protein: 46,
              carbs: 22,
              fat: 22,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Pork Tenderloin',
              desc: '',
              cal: 500,
              protein: 50,
              carbs: 18,
              fat: 18,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Jerky & String Cheese',
              desc: '',
              cal: 200,
              protein: 20,
              carbs: 6,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Cottage Cheese Bowl',
              desc: '',
              cal: 310,
              protein: 28,
              carbs: 20,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Grilled Swordfish Salad',
              desc: '',
              cal: 480,
              protein: 48,
              carbs: 18,
              fat: 20,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Turkey Meatloaf',
              desc: '',
              cal: 520,
              protein: 52,
              carbs: 20,
              fat: 20,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Whey Protein Bar',
              desc: '',
              cal: 210,
              protein: 24,
              carbs: 18,
              fat: 6,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Egg Muffins',
              desc: '',
              cal: 320,
              protein: 28,
              carbs: 8,
              fat: 18,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Duck Rice Bowl',
              desc: '',
              cal: 580,
              protein: 44,
              carbs: 50,
              fat: 18,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Herb Baked Cod',
              desc: '',
              cal: 460,
              protein: 50,
              carbs: 14,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Edamame & Almonds',
              desc: '',
              cal: 230,
              protein: 16,
              carbs: 14,
              fat: 12,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
        ];
      case 'keto':
        return [
          [
            Meal(
              type: 'Breakfast',
              name: 'Avocado Bacon Eggs',
              desc: '',
              cal: 420,
              protein: 22,
              carbs: 4,
              fat: 36,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Zucchini Noodles with Pesto',
              desc: '',
              cal: 460,
              protein: 18,
              carbs: 8,
              fat: 40,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Butter Garlic Steak',
              desc: '',
              cal: 540,
              protein: 44,
              carbs: 2,
              fat: 38,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Cheese & Cucumber Slices',
              desc: '',
              cal: 150,
              protein: 10,
              carbs: 3,
              fat: 11,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Bacon & Cheese Frittata',
              desc: '',
              cal: 450,
              protein: 28,
              carbs: 3,
              fat: 38,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Tuna Stuffed Avocado',
              desc: '',
              cal: 420,
              protein: 24,
              carbs: 6,
              fat: 34,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Creamy Chicken Thighs',
              desc: '',
              cal: 520,
              protein: 40,
              carbs: 4,
              fat: 38,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Pork Rinds',
              desc: '',
              cal: 130,
              protein: 14,
              carbs: 0,
              fat: 8,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Butter Coffee & Eggs',
              desc: '',
              cal: 440,
              protein: 18,
              carbs: 2,
              fat: 40,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Keto Caesar Salad',
              desc: '',
              cal: 430,
              protein: 26,
              carbs: 6,
              fat: 36,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Lamb Chops',
              desc: '',
              cal: 560,
              protein: 46,
              carbs: 0,
              fat: 42,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Macadamia Nuts',
              desc: '',
              cal: 200,
              protein: 2,
              carbs: 4,
              fat: 20,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Smoked Salmon & Cream Cheese',
              desc: '',
              cal: 390,
              protein: 22,
              carbs: 4,
              fat: 32,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Bacon Wrapped Asparagus',
              desc: '',
              cal: 400,
              protein: 24,
              carbs: 6,
              fat: 32,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Pork Belly with Greens',
              desc: '',
              cal: 580,
              protein: 38,
              carbs: 4,
              fat: 46,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Olives & Cheese',
              desc: '',
              cal: 160,
              protein: 6,
              carbs: 2,
              fat: 14,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Keto Pancakes',
              desc: '',
              cal: 380,
              protein: 20,
              carbs: 6,
              fat: 32,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Ground Beef Lettuce Wraps',
              desc: '',
              cal: 450,
              protein: 32,
              carbs: 4,
              fat: 34,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Salmon with Herb Butter',
              desc: '',
              cal: 520,
              protein: 42,
              carbs: 2,
              fat: 38,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Beef Jerky',
              desc: '',
              cal: 140,
              protein: 16,
              carbs: 4,
              fat: 6,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Egg & Chorizo Scramble',
              desc: '',
              cal: 460,
              protein: 30,
              carbs: 2,
              fat: 38,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Shrimp with Garlic Butter',
              desc: '',
              cal: 380,
              protein: 30,
              carbs: 4,
              fat: 26,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Duck Breast',
              desc: '',
              cal: 550,
              protein: 44,
              carbs: 0,
              fat: 40,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Walnut Cluster',
              desc: '',
              cal: 180,
              protein: 4,
              carbs: 4,
              fat: 18,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Coconut Chia Bowl',
              desc: '',
              cal: 350,
              protein: 10,
              carbs: 8,
              fat: 30,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Chicken & Brie Salad',
              desc: '',
              cal: 470,
              protein: 36,
              carbs: 6,
              fat: 34,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Ribeye Steak',
              desc: '',
              cal: 600,
              protein: 50,
              carbs: 0,
              fat: 44,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Dark Chocolate (90%)',
              desc: '',
              cal: 170,
              protein: 3,
              carbs: 6,
              fat: 14,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
        ];
      case 'healthy':
      default:
        return [
          [
            Meal(
              type: 'Breakfast',
              name: 'Oatmeal with Banana',
              desc: '',
              cal: 340,
              protein: 10,
              carbs: 58,
              fat: 7,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Veggie Wrap with Hummus',
              desc: '',
              cal: 430,
              protein: 16,
              carbs: 54,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Grilled Chicken & Veggies',
              desc: '',
              cal: 480,
              protein: 42,
              carbs: 28,
              fat: 18,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Apple with Peanut Butter',
              desc: '',
              cal: 200,
              protein: 6,
              carbs: 24,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Berry Yogurt Parfait',
              desc: '',
              cal: 320,
              protein: 14,
              carbs: 46,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Brown Rice Buddha Bowl',
              desc: '',
              cal: 460,
              protein: 18,
              carbs: 62,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Baked Cod with Salad',
              desc: '',
              cal: 440,
              protein: 38,
              carbs: 22,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Carrot & Celery Sticks',
              desc: '',
              cal: 100,
              protein: 3,
              carbs: 18,
              fat: 2,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Whole Grain Toast & Eggs',
              desc: '',
              cal: 360,
              protein: 20,
              carbs: 36,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Chicken Soup',
              desc: '',
              cal: 380,
              protein: 28,
              carbs: 34,
              fat: 12,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Stir Fried Tofu & Rice',
              desc: '',
              cal: 450,
              protein: 22,
              carbs: 58,
              fat: 12,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Orange & Almonds',
              desc: '',
              cal: 180,
              protein: 5,
              carbs: 22,
              fat: 10,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Mango Overnight Oats',
              desc: '',
              cal: 350,
              protein: 12,
              carbs: 54,
              fat: 8,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Tuna Salad Sandwich',
              desc: '',
              cal: 420,
              protein: 30,
              carbs: 38,
              fat: 14,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Turkey Stuffed Peppers',
              desc: '',
              cal: 470,
              protein: 38,
              carbs: 36,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Banana & Walnuts',
              desc: '',
              cal: 190,
              protein: 4,
              carbs: 28,
              fat: 9,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Spinach Scrambled Eggs',
              desc: '',
              cal: 310,
              protein: 22,
              carbs: 10,
              fat: 18,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Lentil & Veg Soup',
              desc: '',
              cal: 400,
              protein: 20,
              carbs: 52,
              fat: 8,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Baked Salmon Fillet',
              desc: '',
              cal: 490,
              protein: 44,
              carbs: 16,
              fat: 24,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Blueberry Greek Yogurt',
              desc: '',
              cal: 160,
              protein: 10,
              carbs: 22,
              fat: 3,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Coconut Granola Bowl',
              desc: '',
              cal: 380,
              protein: 10,
              carbs: 56,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Grilled Veggie Panini',
              desc: '',
              cal: 440,
              protein: 16,
              carbs: 58,
              fat: 16,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Chicken Fried Rice',
              desc: '',
              cal: 500,
              protein: 34,
              carbs: 52,
              fat: 16,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Peach & Cottage Cheese',
              desc: '',
              cal: 170,
              protein: 10,
              carbs: 20,
              fat: 4,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
          [
            Meal(
              type: 'Breakfast',
              name: 'Peanut Butter Smoothie',
              desc: '',
              cal: 340,
              protein: 16,
              carbs: 38,
              fat: 14,
              cls: 'breakfast',
              icon: '🌅',
            ),
            Meal(
              type: 'Lunch',
              name: 'Greek Salad with Grilled Chicken',
              desc: '',
              cal: 460,
              protein: 38,
              carbs: 20,
              fat: 20,
              cls: 'lunch',
              icon: '☀️',
            ),
            Meal(
              type: 'Dinner',
              name: 'Vegetable Curry & Rice',
              desc: '',
              cal: 480,
              protein: 16,
              carbs: 68,
              fat: 14,
              cls: 'dinner',
              icon: '🌙',
            ),
            Meal(
              type: 'Snack',
              name: 'Mixed Seeds & Raisins',
              desc: '',
              cal: 190,
              protein: 6,
              carbs: 24,
              fat: 9,
              cls: 'snack',
              icon: '🍎',
            ),
          ],
        ];
    }
  }

  List<Meal> _dailyMeals(String diet) => _mealPool(diet)[0];

  List<DayPlan> _weeklyDays(String diet) {
    final pool = _mealPool(diet);
    final days = [
      AppLocalizations.t(context, 'diet_monday'),
      AppLocalizations.t(context, 'diet_tuesday'),
      AppLocalizations.t(context, 'diet_wednesday'),
      AppLocalizations.t(context, 'diet_thursday'),
      AppLocalizations.t(context, 'diet_friday'),
      AppLocalizations.t(context, 'diet_saturday'),
      AppLocalizations.t(context, 'diet_sunday'),
    ];
    return List.generate(
      7,
      (i) => DayPlan(label: days[i], meals: pool[i % pool.length]),
    );
  }

  List<DayPlan> _monthlyWeeks(String diet) {
    final pool = _mealPool(diet);
    return List.generate(4, (i) {
      final base = (i * 2) % pool.length;
      final meals = [
        pool[base % pool.length][0].copyWith(),
        pool[(base + 1) % pool.length][1].copyWith(),
        pool[(base + 2) % pool.length][2].copyWith(),
        pool[(base + 3) % pool.length][3].copyWith(),
      ];
      return DayPlan(
        label: '${AppLocalizations.t(context, "diet_week")} ${i + 1}',
        meals: meals,
      );
    });
  }

  String _responseText(Map<String, dynamic> response) {
    final rawMessage = response['message'];
    return (response['message_text'] ??
            (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
            '')
        .toString()
        .trim();
  }

  void _send() async {
    final t = _msgCtrl.text.trim();
    if (t.isEmpty) return;
    final displayText = t;
    _msgCtrl.clear();
    setState(() {
      _messages.add(ChatMessage(text: displayText, isBot: false));
      _chatHistory.add({'role': 'user', 'content': displayText});
      _isTyping = true;
    });

    final lower = t.toLowerCase();
    final planType = _detectPlanType(lower);
    final planTypeLabel = planType[0].toUpperCase() + planType.substring(1);

    String reply = AppLocalizations.t(
      context,
      'diet_chat_here_plan',
    ).replaceAll('{type}', planTypeLabel);
    MealPlan? plan;
    String diet = 'healthy';
    String planName = AppLocalizations.t(context, 'diet_plan_healthy');

    if (lower.contains('mediterr')) {
      diet = 'mediterranean';
      planName = AppLocalizations.t(context, 'diet_plan_mediterranean');
    } else if (lower.contains('vegan')) {
      diet = 'vegan';
      planName = AppLocalizations.t(context, 'diet_plan_vegan');
    } else if (lower.contains('high protein') ||
        lower.contains('highprotein') ||
        lower.contains('protein')) {
      diet = 'highprotein';
      planName = AppLocalizations.t(context, 'diet_plan_highprotein');
    } else if (lower.contains('keto')) {
      diet = 'keto';
      planName = AppLocalizations.t(context, 'diet_plan_keto');
    } else if (lower.contains('healthy') ||
        lower.contains('balanced') ||
        lower.contains('plan')) {
      diet = 'healthy';
      planName = 'Healthy Balanced Plan';
    } else {
      try {
        final response = await BackendService().sendChatQuery(
          t,
          '',
          List<Map<String, String>>.from(_chatHistory),
          '',
          moduleContext: 'diet',
        );
        reply = _responseText(response);
      } catch (_) {
        reply = '';
      }
      if (reply.isEmpty) {
        reply = 'AHVI is still preparing this. Try again in a moment.';
      }
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(text: reply, isBot: true));
          _chatHistory.add({'role': 'assistant', 'content': reply});
        });
      }
      return;
    }

    try {
      final response = await BackendService().sendChatQuery(
        t,
        '',
        List<Map<String, String>>.from(_chatHistory),
        '',
        moduleContext: 'diet',
      );
      final backendReply = _responseText(response);
      if (backendReply.isNotEmpty) reply = backendReply;
    } catch (_) {}

    if (planType == 'weekly') {
      final days = _weeklyDays(diet);
      plan = MealPlan(
        id: 0,
        name: planName,
        desc: '',
        planType: 'weekly',
        meals: [],
        days: days,
      );
      for (final day in plan.days) {
        for (final meal in day.meals) {
          meal.imagePath = await MealImageProvider.fetchImage(meal.name);
        }
      }
    } else if (planType == 'monthly') {
      final weeks = _monthlyWeeks(diet);
      plan = MealPlan(
        id: 0,
        name: planName,
        desc: '',
        planType: 'monthly',
        meals: [],
        days: weeks,
      );
      for (final week in plan.days) {
        for (final meal in week.meals) {
          meal.imagePath = await MealImageProvider.fetchImage(meal.name);
        }
      }
    } else {
      final meals = _dailyMeals(diet);
      plan = MealPlan(
        id: 0,
        name: planName,
        desc: '',
        planType: 'daily',
        meals: meals,
        days: [],
      );
      for (final meal in plan.meals) {
        meal.imagePath = await MealImageProvider.fetchImage(meal.name);
      }
    }

    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(text: reply, isBot: true));
        _chatHistory.add({'role': 'assistant', 'content': reply});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: context.dBg,
        drawer: _historyDrawer(),
        body: SafeArea(
          child: Column(
            children: [
              // ── AppBar ──────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                color: context.dSurface,
                child: Row(
                  children: [
                    // Back button on left
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: context.dText,
                        ),
                      ),
                    ),
                    AhviHomeText(
                      color: context.dText,
                      fontSize: 30.0,
                      letterSpacing: 3.2,
                      fontWeight: FontWeight.w400,
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: context.dSurface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.dBorder),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: context.dAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              // ── Messages ────────────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _messages.length)
                      return Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          AppLocalizations.t(context, 'diet_thinking'),
                          style: TextStyle(fontSize: 11, color: context.dMuted),
                        ),
                      );
                    final m = _messages[i];
                    return Column(
                      crossAxisAlignment: m.isBot
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: m.isBot ? context.dSurface : context.dAccent,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomLeft: m.isBot
                                  ? const Radius.circular(0)
                                  : const Radius.circular(16),
                              bottomRight: m.isBot
                                  ? const Radius.circular(16)
                                  : const Radius.circular(0),
                            ),
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              color: m.isBot ? context.dText : Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (m.plan != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: PlanCard(
                              plan: m.plan!,
                              onDelete: () {},
                              isSuggestion: true,
                              onSave: widget.onSavePlan,
                              onEdit: () async {
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (bCtx) => EditMealModal(
                                    plan: m.plan!,
                                    messengerKey: _messengerKey,
                                    onSave: (updated) {
                                      setState(() => m.plan = updated);
                                      Navigator.pop(bCtx);
                                      _messengerKey.currentState!.showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(
                                                Icons.edit_note_rounded,
                                                color: Color(0xFFFFD60A),
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  AppLocalizations.t(
                                                    context,
                                                    'diet_plan_updated',
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              100,
                                            ),
                                          ),
                                          backgroundColor: context.dSnackBg,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // ── Input Bar ───────────────────────────────────────────────────
              AhviChatPromptBar(
                controller: _msgCtrl,
                focusNode: _msgFocus,
                hintText: AppLocalizations.t(context, 'diet_chat_hint'),
                surface: context.dSurface,
                border: context.dBorder,
                accent: context.dAccent,
                accentSecondary: context.dAccent2,
                textHeading: context.dText,
                textMuted: context.dMuted,
                shadowMedium: Colors.black.withValues(alpha: 0.06),
                onAccent: Colors.white,
                onSendMessage: (_) => _send(),
                themeTokens: Theme.of(context).extension<AppThemeTokens>()!,
                onVoiceTap: _toggleListening,
                isListening: _isListening,
                onVisualSearch: null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── History Drawer ───────────────────────────────────────────────────────
  Widget _historyDrawer() {
    return Drawer(
      backgroundColor: context.dSurface,
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
                    style: TextStyle(
                      color: context.dText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _messages
                          ..clear()
                          ..add(
                            ChatMessage(
                              text:
                                  "Hey! 😊 Ask me for a meal plan!\n\n🥗 Diets: Mediterranean, Vegan, High Protein, Keto, Healthy\n📅 Plans: Daily, Weekly, Monthly\n\nExample: 'Give me a weekly keto plan'",
                              isBot: true,
                            ),
                          );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [context.dAccent, context.dAccent2],
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
            Divider(color: context.dBorder, height: 1),
            Expanded(
              child: Center(
                child: Text(
                  'Chat history coming soon.\nStart a new conversation!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.dMuted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditMealModal extends StatefulWidget {
  final MealPlan plan;
  final ValueChanged<MealPlan> onSave;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  const EditMealModal({
    super.key,
    required this.plan,
    required this.onSave,
    required this.messengerKey,
  });
  @override
  State<EditMealModal> createState() => _EditMealModalState();
}

class _EditMealModalState extends State<EditMealModal> {
  late final TextEditingController _nameCtrl;
  late final Map<String, TextEditingController> _nameCtrlMap;
  late final Map<String, TextEditingController> _calCtrlMap;
  late final Map<String, String?> _imgMap;
  bool _isSaved = false;
  final _mealTypes = [
    ('Breakfast', 'breakfast', '🌅', kBreakfastFg, kBreakfastBg),
    ('Lunch', 'lunch', '☀️', kLunchFg, kLunchBg),
    ('Dinner', 'dinner', '🌙', kDinnerFg, kDinnerBg),
    ('Snack', 'snack', '🍎', kSnackFg, kSnackBg),
  ];

  // Local messenger key — toasts appear INSIDE the modal
  final _localKey = GlobalKey<ScaffoldMessengerState>();

  void _toast({
    required IconData icon,
    required Color iconColor,
    required String msg,
  }) {
    _localKey.currentState?.clearSnackBars();
    _localKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: context.dSnackBg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.plan.name);
    _nameCtrlMap = {};
    _calCtrlMap = {};
    _imgMap = {};
    for (final mt in _mealTypes) {
      final existing = widget.plan.meals
          .where((m) => m.cls == mt.$2)
          .firstOrNull;
      _nameCtrlMap[mt.$2] = TextEditingController(text: existing?.name ?? '');
      _calCtrlMap[mt.$2] = TextEditingController(
        text: existing != null && existing.cal > 0 ? '${existing.cal}' : '',
      );
      _imgMap[mt.$2] = existing?.imagePath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _nameCtrlMap.values) {
      c.dispose();
    }
    for (final c in _calCtrlMap.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast(
        icon: Icons.warning_amber_rounded,
        iconColor: const Color(0xFFFFD60A),
        msg: AppLocalizations.t(context, 'diet_enter_plan_name'),
      );
      return;
    }
    final meals = <Meal>[];
    for (final mt in _mealTypes) {
      final n = _nameCtrlMap[mt.$2]!.text.trim();
      if (n.isNotEmpty) {
        meals.add(
          Meal(
            type: mt.$1,
            cls: mt.$2,
            icon: mt.$3,
            name: n,
            desc: '',
            cal: int.tryParse(_calCtrlMap[mt.$2]!.text.trim()) ?? 0,
            imagePath: _imgMap[mt.$2],
          ),
        );
      }
    }
    if (meals.isEmpty) {
      _toast(
        icon: Icons.restaurant_outlined,
        iconColor: const Color(0xFFFF9F0A),
        msg: AppLocalizations.t(context, 'diet_add_meal_entry'),
      );
      return;
    }
    setState(() => _isSaved = true);
    widget.onSave(
      MealPlan(
        id: widget.plan.id,
        name: name,
        desc: widget.plan.desc,
        planType: widget.plan.planType,
        meals: meals,
      ),
    );
    _toast(
      icon: Icons.check_circle,
      iconColor: const Color(0xFF30D158),
      msg: '"$name" updated successfully!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _localKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, sc) {
            return Container(
              decoration: BoxDecoration(
                color: context.dSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.dBorder),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.t(context, 'diet_edit_meal_plan'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  // Scrollable body
                  Expanded(
                    child: ListView(
                      controller: sc,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          AppLocalizations.t(context, 'diet_plan_name'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.t(
                              context,
                              'diet_plan_hint',
                            ),
                            filled: true,
                            fillColor: context.dSurface2,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppLocalizations.t(context, 'diet_plan_type'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: context.dAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.dAccent),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.t(context, 'diet_daily'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.dAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          AppLocalizations.t(context, 'diet_meals'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.dMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...(_mealTypes.map(
                          (mt) => StatefulBuilder(
                            builder: (ctx, setSt) => _MealEntry(
                              label: mt.$1,
                              emoji: mt.$3,
                              color: mt.$4,
                              bg: mt.$5,
                              nameCtrl: _nameCtrlMap[mt.$2]!,
                              calCtrl: _calCtrlMap[mt.$2]!,
                              imagePath: _imgMap[mt.$2],
                              onImageChanged: (v) {
                                setSt(() => _imgMap[mt.$2] = v);
                                setState(() {});
                              },
                            ),
                          ),
                        )),
                        const SizedBox(height: 30),
                        GestureDetector(
                          onTap: _isSaved ? null : _save,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: _isSaved
                                  ? const Color(0xFF1A7A35)
                                  : context.dAccent,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_isSaved
                                              ? const Color(0xFF1A7A35)
                                              : context.dAccent)
                                          .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSaved) ...[
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    _isSaved
                                        ? 'Changes Saved!'
                                        : 'Save Changes',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ], // ListView children
                    ), // ListView
                  ), // Expanded
                ], // Column children
              ), // Column
            ); // Container
          }, // builder
        ), // DraggableScrollableSheet
      ), // Scaffold
    ); // ScaffoldMessenger
  }
}

class _MealImage extends StatelessWidget {
  final String? imagePath;
  final String emoji;
  final double size;
  const _MealImage({this.imagePath, required this.emoji, this.size = 28});
  @override
  Widget build(BuildContext context) {
    if (imagePath == null)
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
        ),
      );
    if (!imagePath!.startsWith('http'))
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
        ),
      );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          imagePath!,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              color: context.dSurface2,
              child: Center(
                child: SizedBox(
                  width: size * 0.35,
                  height: size * 0.35,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: context.dAccent,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, _, _) => Container(
            color: context.dSurface2,
            child: Center(
              child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CHATGPT-STYLE PLUS BUTTON FOR DIET ─────────────────────────────────────
class _DietPlusButton extends StatefulWidget {
  final VoidCallback? onCameraSelected;
  const _DietPlusButton({this.onCameraSelected});
  @override
  State<_DietPlusButton> createState() => _DietPlusButtonState();
}

class _DietPlusButtonState extends State<_DietPlusButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotateAnim;
  bool _menuOpen = false;
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rotateAnim = Tween<double>(
      begin: 0.0,
      end: 0.125,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _closeMenu();
    _ctrl.dispose();
    super.dispose();
  }

  void _openMenu() {
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    setState(() => _menuOpen = true);
    _ctrl.forward();
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final actions = [
      (Icons.camera_alt_outlined, 'Camera', const Color(0xFFFF6B6B)),
      (Icons.photo_library_outlined, 'Photos', const Color(0xFF4ECDC4)),
      (Icons.attach_file_rounded, 'Files', const Color(0xFF45B7D1)),
      (Icons.search_rounded, 'Search Food', const Color(0xFF96CEB4)),
    ];

    _overlay = OverlayEntry(
      builder: (_) {
        return GestureDetector(
          onTap: _closeMenu,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned(
                left: offset.dx - 10,
                bottom: MediaQuery.of(context).size.height - offset.dy + 8,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 190,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.dSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.dBorder, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: actions
                            .map(
                              (a) => _DietMenuRow(
                                icon: a.$1,
                                label: a.$2,
                                color: a.$3,
                                onTap: () {
                                  _closeMenu();
                                  if (a.$2 == 'Camera' || a.$2 == 'Search Food')
                                    widget.onCameraSelected?.call();
                                },
                              ),
                            )
                            .toList(),
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
    Overlay.of(context).insert(_overlay!);
  }

  void _closeMenu() {
    _overlay?.remove();
    _overlay = null;
    _ctrl.reverse();
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openMenu,
      child: AnimatedBuilder(
        animation: _rotateAnim,
        builder: (_, child) => Transform.rotate(
          angle: _rotateAnim.value * 2 * 3.14159,
          child: child,
        ),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _menuOpen
                ? context.dAccent.withValues(alpha: 0.15)
                : context.dSurface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _menuOpen
                  ? context.dAccent.withValues(alpha: 0.5)
                  : context.dBorder,
              width: 1.5,
            ),
          ),
          child: Icon(Icons.add_rounded, color: context.dAccent, size: 20),
        ),
      ),
    );
  }
}

class _DietMenuRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DietMenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  State<_DietMenuRow> createState() => _DietMenuRowState();
}

class _DietMenuRowState extends State<_DietMenuRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon, color: widget.color, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: TextStyle(
                color: context.dText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DIET LENS ACTION SHEET ──────────────────────────────────────────────────
class _DietLensActionSheet extends StatelessWidget {
  const _DietLensActionSheet();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.dSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: context.dMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.t(context, 'diet_visual_search'),
                    style: TextStyle(
                      color: context.dText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.dSurface2,
                      border: Border.all(color: context.dBorder),
                    ),
                    child: Icon(Icons.close, color: context.dMuted, size: 14),
                  ),
                ),
              ],
            ),
          ),
          // Info card
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.dSurface2,
              border: Border.all(
                color: context.dAccent.withValues(alpha: 0.15),
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
                      color: context.dAccent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    color: context.dAccent.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: context.dAccent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.t(context, 'diet_visual_ai_search'),
                        style: TextStyle(
                          color: context.dText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        AppLocalizations.t(context, 'diet_visual_ai_desc'),
                        style: TextStyle(
                          color: context.dMuted,
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
          _DietLensOptionTile(
            icon: Icons.search,
            name: 'Identify Food',
            desc: 'Scan food to get calories & nutrition',
            color: context.dAccent,
            onTap: () => Navigator.pop(context),
          ),
          _DietLensOptionTile(
            icon: Icons.add_photo_alternate_outlined,
            name: 'Add to Meal Plan',
            desc: 'Save scanned food to your plan',
            color: const Color(0xFF1A7A35),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _DietLensOptionTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String desc;
  final Color color;
  final VoidCallback onTap;
  const _DietLensOptionTile({
    required this.icon,
    required this.name,
    required this.desc,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.dSurface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.dBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: context.dText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    desc,
                    style: TextStyle(color: context.dMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.dMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── DIET PULSING MIC ICON ───────────────────────────────────────────────────
class _DietPulsingMicIcon extends StatefulWidget {
  const _DietPulsingMicIcon();
  @override
  State<_DietPulsingMicIcon> createState() => _DietPulsingMicIconState();
}

class _DietPulsingMicIconState extends State<_DietPulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
    );
  }
}

// ─── ASK AHVI FAB (matches Skincare style exactly) ───────────────────────────
class _AskAhviFab extends StatefulWidget {
  final VoidCallback onTap;
  const _AskAhviFab({required this.onTap});

  @override
  State<_AskAhviFab> createState() => _AskAhviFabState();
}

class _AskAhviFabState extends State<_AskAhviFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.dAccent;
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
                          color: accent.withValues(alpha: 0.35),
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
              color: accent,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.40),
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
                  child: const Text(
                    '✦',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  AppLocalizations.t(context, 'diet_ask_ahvi'),
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
