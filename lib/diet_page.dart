import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/ahvi_speech_service.dart';
import 'package:http/http.dart' as http;
// theme_tokens.dart — use package import below if in a sub-folder
// Update this path to match your project structure, e.g.:
// import 'package:your_app/theme/theme_tokens.dart';
import 'theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:provider/provider.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/widgets/ahvi_visual_board.dart';

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
  final AhviVisualBoard? visualBoard;
  final AhviModuleCard? moduleCard;
  ChatMessage({
    required this.text,
    required this.isBot,
    this.plan,
    this.visualBoard,
    this.moduleCard,
  });
}

// ─── IMAGE PROVIDER (Diet & Nutrition Based Assets) ──────────────────────────
//
// Asset folder structure:
//   assets/images/meals/
//     mediterranean/  keto/  vegan/  high_protein/  healthy/
//     south_indian/   north_indian/  nutrition/
//
// Resolution order:
//   1. diet folder  (meal name matched to a diet-specific image)
//   2. nutrition folder  (matched by nutrition keyword)
//   3. flat type fallback  (breakfast / lunch / dinner / snack)
// ─────────────────────────────────────────────────────────────────────────────
class MealImageProvider {
  static const String _base = 'assets/meal';

  // ── 1. Diet-specific keyword maps ─────────────────────────────────────────
  // Each entry: (keywords, filename inside diet subfolder)
  static const Map<String, List<(List<String>, String)>> _dietAssets = {
    'mediterranean': [
      (['greek salad', 'salad'],                       'greek_salad.png'),
      (['hummus', 'pita', 'flatbread'],                'hummus_pita.png'),
      (['falafel'],                                    'falafel.png'),
      (['tabbouleh', 'couscous', 'quinoa'],            'tabbouleh.png'),
      (['grilled fish', 'sea bass', 'branzino'],       'grilled_fish.png'),
      (['shakshuka', 'egg'],                           'shakshuka.png'),
      (['yogurt', 'labneh', 'tzatziki'],               'yogurt_bowl.png'),
      (['olive', 'bruschetta'],                        'bruschetta.png'),
      (['lentil', 'legume', 'bean'],                   'lentil_soup.png'),
      (['lamb', 'kebab', 'kofta'],                     'lamb_kebab.png'),
    ],
    'keto': [
      (['bacon', 'egg', 'omelette', 'scramble'],       'bacon_eggs.png'),
      (['avocado'],                                    'avocado.png'),
      (['steak', 'beef', 'ribeye', 'sirloin'],         'steak.png'),
      (['salmon', 'tuna', 'fish'],                     'keto_fish.png'),
      (['chicken', 'poultry'],                         'keto_chicken.png'),
      (['cheese', 'brie', 'gouda', 'cheddar'],         'cheese_board.png'),
      (['cauliflower', 'zucchini', 'broccoli'],        'keto_veggies.png'),
      (['nut', 'almond', 'walnut', 'pecan'],           'keto_nuts.png'),
      (['butter', 'cream'],                            'cheese_board.png'),
      (['lettuce wrap', 'lettuce'],                    'lettuce_wrap.png'),
    ],
    'vegan': [
      (['smoothie', 'shake', 'blend'],                 'smoothie_bowl.png'),
      (['tofu', 'tempeh', 'edamame'],                  'tofu.png'),
      (['lentil', 'dal', 'daal'],                      'dal.png'),
      (['chickpea', 'hummus'],                         'chickpea.png'),
      (['buddha bowl', 'grain bowl', 'bowl'],          'buddha_bowl.png'),
      (['stir fry', 'stir-fry', 'fried rice'],         'vegan_stirfry.png'),
      (['salad', 'greens', 'kale', 'spinach'],         'green_salad.png'),
      (['pasta', 'spaghetti', 'noodle'],               'vegan_pasta.png'),
      (['soup', 'stew', 'broth'],                      'vegan_soup.png'),
      (['fruit', 'berry', 'acai'],                     'fruit_bowl.png'),
    ],
    'high_protein': [
      (['egg', 'omelette', 'scramble', 'white'],       'egg_whites.png'),
      (['greek yogurt', 'yogurt', 'curd'],             'greek_yogurt.png'),
      (['chicken breast', 'chicken', 'poultry'],       'grilled_chicken.png'),
      (['tuna', 'canned tuna'],                        'tuna.png'),
      (['salmon', 'fish', 'seafood'],                  'salmon.png'),
      (['steak', 'beef', 'lean beef'],                 'lean_beef.png'),
      (['cottage cheese', 'paneer'],                   'cottage_cheese.png'),
      (['protein shake', 'whey', 'casein', 'shake'],   'protein_shake.png'),
      (['protein bar', 'bar'],                         'protein_bar.png'),
      (['lentil', 'legume', 'bean', 'edamame'],        'legumes.png'),
    ],
    'healthy': [
      (['oat', 'oatmeal', 'porridge'],                 'oatmeal.png'),
      (['granola'],                                    'granola.png'),
      (['avocado toast', 'toast'],                     'avocado_toast.png'),
      (['salad', 'greens'],                            'salad.png'),
      (['soup', 'vegetable soup'],                     'veggie_soup.png'),
      (['stir fry', 'stir-fry'],                       'stir_fry.png'),
      (['rice', 'brown rice', 'quinoa'],               'brown_rice.png'),
      (['sandwich', 'wrap'],                           'wrap.png'),
      (['fruit salad', 'fruit bowl', 'fruit'],         'fruit_salad.png'),
      (['smoothie'],                                   'smoothie.png'),
    ],
    'south_indian': [
      // Breakfast
      (['idli', 'idly'],                                        'idli.png'),
      (['dosa', 'masala dosa', 'rava dosa', 'set dosa'],        'dosa.png'),
      (['upma', 'rava upma'],                                   'upma.png'),
      (['pongal', 'ven pongal', 'khichdi'],                     'pongal.png'),
      (['pesarattu', 'moong dosa'],                             'pesarattu.png'),
      (['poha', 'aval upma', 'avalakki'],                       'poha.png'),
      (['vada', 'medu vada', 'urad vada'],                      'vada.png'),
      (['uttapam', 'oothappam'],                                'uttapam.png'),
      // Lunch / Dinner
      (['sambar'],                                              'sambar.png'),
      (['rasam'],                                               'rasam.png'),
      (['rice', 'white rice', 'steamed rice'],                  'rice.png'),
      (['biryani', 'hyderabadi biryani', 'thalassery'],         'biryani.png'),
      (['curd rice', 'thayir sadam', 'dahi rice'],              'curd_rice.png'),
      (['tamarind rice', 'pulihora', 'puliyodarai'],            'tamarind_rice.png'),
      (['lemon rice', 'chitranna'],                             'lemon_rice.png'),
      (['kootu', 'aviyal', 'stew'],                             'aviyal.png'),
      (['fish curry', 'meen curry', 'fish'],                    'fish_curry.png'),
      (['chicken curry', 'chettinad chicken', 'chicken'],       'chicken_curry.png'),
      (['egg curry', 'egg'],                                    'egg_curry.png'),
      (['dal', 'pappu', 'lentil'],                              'pappu.png'),
      (['kootu', 'poriyal', 'thoran', 'sabzi', 'ivvi', 'ivy gourd', 'tindora', 'tendli'], 'poriyal.png'),
      (['bisi bele bath', 'bisibelebath'],                      'bisi_bele_bath.png'),
      // Snacks
      (['murukku', 'chakli'],                                   'murukku.png'),
      (['banana chips', 'chips'],                               'banana_chips.png'),
      (['sundal', 'boiled chickpea', 'chana sundal'],           'sundal.png'),
      (['payasam', 'kheer', 'pudding'],                         'payasam.png'),
    ],
    'north_indian': [
      // Breakfast
      (['paratha', 'aloo paratha', 'stuffed paratha'],          'paratha.png'),
      (['poha', 'flattened rice'],                              'poha.png'),
      (['upma'],                                                'upma.png'),
      (['puri', 'bhatura'],                                     'puri.png'),
      (['chole bhature', 'chole'],                              'chole_bhature.png'),
      (['halwa', 'sooji halwa', 'atte ka halwa'],               'halwa.png'),
      // Lunch / Dinner
      (['dal makhani', 'dal tadka', 'dal fry', 'dal'],          'dal_makhani.png'),
      (['paneer butter masala', 'paneer tikka masala'],          'paneer_butter_masala.png'),
      (['paneer', 'cottage cheese'],                            'paneer.png'),
      (['butter chicken', 'murgh makhani'],                     'butter_chicken.png'),
      (['biryani', 'dum biryani', 'lucknowi biryani'],          'biryani.png'),
      (['roti', 'chapati', 'phulka'],                           'roti.png'),
      (['naan', 'garlic naan'],                                 'naan.png'),
      (['rajma', 'kidney bean'],                                'rajma.png'),
      (['palak paneer', 'palak', 'spinach curry'],              'palak_paneer.png'),
      (['aloo', 'potato curry', 'dum aloo'],                    'aloo_curry.png'),
      (['kadai chicken', 'chicken masala', 'chicken'],          'kadai_chicken.png'),
      (['mutton curry', 'mutton', 'lamb'],                      'mutton_curry.png'),
      (['saag', 'makki di roti', 'sarson'],                     'saag.png'),
      (['mixed veg', 'sabzi', 'bhaji'],                         'mixed_veg.png'),
      (['rice', 'jeera rice', 'pulao'],                         'pulao.png'),
      // Snacks / Sides
      (['samosa'],                                              'samosa.png'),
      (['pakora', 'bhajji', 'fritter'],                         'pakora.png'),
      (['lassi', 'sweet lassi', 'mango lassi'],                 'lassi.png'),
      (['raita', 'cucumber raita', 'boondi raita'],             'raita.png'),
      (['chaat', 'pani puri', 'bhel puri', 'sev puri'],         'chaat.png'),
      (['gulab jamun', 'jalebi', 'barfi', 'ladoo', 'halwa'],    'sweets.png'),
    ],
  };

  // ── 2. Nutrition-category keyword map ────────────────────────────────────
  // folder: assets/images/meals/nutrition/
  static const List<(List<String>, String)> _nutritionAssets = [
    // High Protein
    (['egg white', 'egg'],                            'protein_eggs.png'),
    (['chicken breast', 'chicken'],                   'protein_chicken.png'),
    (['salmon', 'tuna', 'fish', 'seafood'],           'protein_fish.png'),
    (['protein shake', 'whey', 'casein'],             'protein_shake.png'),
    (['cottage cheese', 'greek yogurt', 'yogurt'],    'protein_dairy.png'),
    // Low Carb
    (['lettuce', 'spinach', 'kale', 'greens'],        'lowcarb_greens.png'),
    (['cauliflower', 'zucchini', 'broccoli', 'ivvi', 'ivy gourd', 'tindora', 'tendli'], 'lowcarb_veggies.png'),
    (['avocado'],                                     'lowcarb_avocado.png'),
    // Healthy Fats
    (['nut', 'almond', 'walnut', 'cashew', 'pecan'],  'fat_nuts.png'),
    (['olive oil', 'olive'],                          'fat_olive.png'),
    (['avocado'],                                     'fat_avocado.png'),
    // Fiber / Carbs
    (['oat', 'oatmeal', 'granola'],                   'fiber_oats.png'),
    (['rice', 'brown rice', 'quinoa', 'couscous'],    'fiber_grains.png'),
    (['lentil', 'legume', 'bean', 'chickpea'],        'fiber_legumes.png'),
    (['fruit', 'apple', 'banana', 'berry', 'mango'],  'fiber_fruit.png'),
    // Vitamins / Antioxidants
    (['smoothie', 'smoothie bowl', 'acai'],           'vitamin_smoothie.png'),
    (['salad', 'greens', 'mixed greens'],              'vitamin_salad.png'),
    (['soup', 'stew', 'broth'],                       'vitamin_soup.png'),
  ];

  // ── 3. Flat fallback by meal type ─────────────────────────────────────────
  static const Map<String, String> _typeAssets = {
    'breakfast': 'breakfast.png',
    'lunch':     'lunch.png',
    'dinner':    'dinner.png',
    'snack':     'snack.png',
  };

  // ── Diet keyword detector ─────────────────────────────────────────────────
  static String? _detectDiet(String mealName) {
    final n = mealName.toLowerCase();
    // South Indian — check before north Indian (more specific keywords)
    if (n.contains('idli') || n.contains('dosa') || n.contains('sambar') ||
        n.contains('rasam') || n.contains('upma') || n.contains('pongal') ||
        n.contains('vada') || n.contains('uttapam') || n.contains('pesarattu') ||
        n.contains('pulihora') || n.contains('aviyal') || n.contains('kootu') ||
        n.contains('poriyal') || n.contains('thoran') || n.contains('pappu') ||
        n.contains('meen') || n.contains('chettinad') || n.contains('payasam') ||
        n.contains('murukku') || n.contains('sundal') || n.contains('bisi bele') ||
        n.contains('tamarind rice') || n.contains('lemon rice') ||
        n.contains('curd rice') || n.contains('south indian')) return 'south_indian';
    // North Indian
    if (n.contains('paratha') || n.contains('naan') || n.contains('roti') ||
        n.contains('chapati') || n.contains('dal makhani') || n.contains('rajma') ||
        n.contains('paneer') || n.contains('butter chicken') || n.contains('chole') ||
        n.contains('bhature') || n.contains('puri') || n.contains('palak') ||
        n.contains('saag') || n.contains('makki') || n.contains('sarson') ||
        n.contains('lassi') || n.contains('samosa') || n.contains('pakora') ||
        n.contains('chaat') || n.contains('halwa') || n.contains('gulab jamun') ||
        n.contains('jalebi') || n.contains('ladoo') || n.contains('mutton') ||
        n.contains('dum aloo') || n.contains('pulao') || n.contains('north indian')) return 'north_indian';
    // Other diets
    if (n.contains('mediterr') || n.contains('greek') ||
        n.contains('falafel') || n.contains('hummus') ||
        n.contains('tabbouleh') || n.contains('shakshuka')) return 'mediterranean';
    if (n.contains('keto') || n.contains('low carb') ||
        n.contains('bacon')) return 'keto';
    if (n.contains('vegan') || n.contains('plant') ||
        n.contains('tofu') || n.contains('tempeh') ||
        n.contains('buddha bowl')) return 'vegan';
    if (n.contains('high protein') || n.contains('protein') ||
        n.contains('whey') || n.contains('casein')) return 'high_protein';
    return null;
  }

  /// Main resolver: name + type → asset path.
  static String? assetFor(String name, String type) {
    final lower = name.toLowerCase();

    // 1. Try diet-specific folder
    final diet = _detectDiet(lower);
    if (diet != null && _dietAssets.containsKey(diet)) {
      for (final (keywords, file) in _dietAssets[diet]!) {
        if (keywords.any((k) => lower.contains(k))) {
          return '$_base/$diet/$file';
        }
      }
      // Diet matched but no keyword hit → use diet folder's type fallback
      final tf = _typeAssets[type.toLowerCase().trim()];
      if (tf != null) return '$_base/$diet/$tf';
    }

    // 2. Nutrition folder
    for (final (keywords, file) in _nutritionAssets) {
      if (keywords.any((k) => lower.contains(k))) {
        return '$_base/nutrition/$file';
      }
    }

    // 3. Flat type fallback
    final tf = _typeAssets[type.toLowerCase().trim()];
    return tf != null ? '$_base/$tf' : null;
  }

  /// Type-only lookup (used where name isn't available).
  static String? assetForType(String mealType) {
    final f = _typeAssets[mealType.toLowerCase().trim()];
    return f != null ? '$_base/$f' : null;
  }

  /// Kept for call-site compatibility (_MealEntry._autoFetch).
  static Future<String?> fetchImage(String mealName, {String type = ''}) async =>
      assetFor(mealName, type);
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
    _persistMealPlan(p);
  }

  /// Persist a saved meal plan as one Appwrite `meal_plans` doc so it
  /// survives reloads and feeds the chat "Today's meals" card. Schema
  /// is per-plan with `meals` as an array of JSON-encoded meal strings
  /// (size 1000 each), so we serialize only the small core fields and
  /// drop heavy ones like imagePath.
  Future<void> _persistMealPlan(MealPlan plan) async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);

      // Flatten weekly/monthly into a single list so the plan card still
      // gets something to show.
      final List<Meal> flatMeals = plan.planType == 'daily'
          ? List.of(plan.meals)
          : plan.days.expand((d) => d.meals).toList();

      final mealJsonList = flatMeals.map((m) {
        return jsonEncode({
          'type': m.type,
          'name': m.name,
          'desc': m.desc,
          'cal': m.cal,
          'protein': m.protein,
          'carbs': m.carbs,
          'fat': m.fat,
        });
      }).toList();

      final totalCal = flatMeals.fold<int>(0, (sum, m) => sum + m.cal);
      final desc = plan.desc.trim().isEmpty ? plan.name : plan.desc;

      await appwrite.createMealPlan({
        'name': plan.name,
        'desc': desc,
        'planType': plan.planType,
        'totalCal': totalCal,
        'meals': mealJsonList,
      });
    } catch (e) {
      debugPrint('Persist meal plan failed: $e');
    }
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
    _persistMealPlan(plan);
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
            child: ChatScreen(
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
  final bool compact;
  const _MealRow({required this.m, this.compact = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.dBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MealImage(
            imagePath: m.imagePath ?? MealImageProvider.assetFor(m.name, m.type),
            emoji: m.icon,
            height: compact ? 44 : 56,
          ),
          SizedBox(width: compact ? 8 : 10),
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
                if (m.protein > 0 || m.carbs > 0 || m.fat > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _MacroChip(
                        label: 'P ${m.protein}g',
                        bg: const Color(0xFFE8F5E9),
                        fg: const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 4),
                      _MacroChip(
                        label: 'C ${m.carbs}g',
                        bg: const Color(0xFFFFF8E1),
                        fg: const Color(0xFFF57F17),
                      ),
                      const SizedBox(width: 4),
                      _MacroChip(
                        label: 'F ${m.fat}g',
                        bg: const Color(0xFFFBE9E7),
                        fg: const Color(0xFFBF360C),
                      ),
                    ],
                  ),
                ],
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

class _MacroChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _MacroChip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: fg),
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
            ...plan.meals.map((m) => _MealRow(m: m, compact: isSuggestion))
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
                  ...day.meals.map((m) => _MealRow(m: m, compact: isSuggestion)),
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
                          height: 90,
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

class ChatScreen extends StatefulWidget {
  final ValueChanged<MealPlan> onSavePlan;
  final VoidCallback onClose;
  const ChatScreen({
    super.key,
    required this.onSavePlan,
    required this.onClose,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _toggleListening() async {
    if (_isListening) {
      await AhviSpeechService.instance.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (mounted) setState(() => _isListening = true);
    await AhviSpeechService.instance.start(
      onText: (text) {
        if (!mounted) return;
        setState(() {
          _msgCtrl.text = text;
          _msgCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _msgCtrl.text.length),
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted && !AhviSpeechService.instance.isListening) {
      setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    if (_isListening) {
      AhviSpeechService.instance.cancel();
    }
    _msgCtrl.dispose();
    _msgFocus.dispose();
    _removeOverlay();
    super.dispose();
  }


  String _responseText(Map<String, dynamic> response) {
    final rawMessage = response['message'];
    return (response['message_text'] ??
            (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
            '')
        .toString()
        .trim();
  }

  void _send([String? incoming]) async {
    // AhviChatPromptBar's _trySend clears the controller BEFORE calling
    // onSendMessage, so we MUST use the text it passes us. Reading
    // _msgCtrl.text here always returned empty, so every Diet message
    // silently bailed out at the `if (t.isEmpty) return` guard.
    final t = (incoming ?? _msgCtrl.text).trim();
    if (t.isEmpty) return;
    final displayText = t;
    if (_msgCtrl.text.isNotEmpty) _msgCtrl.clear();
    setState(() {
      _messages.add(ChatMessage(text: displayText, isBot: false));
      _chatHistory.add({'role': 'user', 'content': displayText});
      _isTyping = true;
    });

    // Single backend call. Backend returns a structured visual_board for
    // diet/meal prompts, or plain text otherwise.
    Map<String, dynamic> response;
    try {
      response = await BackendService().sendModuleChat(
        domain: 'diet',
        message: t,
        chatHistory: List<Map<String, String>>.from(_chatHistory),
      );
    } catch (err) {
      response = {'message_text': 'AHVI diet request failed: $err'};
    }

    // Module summary card (medicines/bills/events/etc) — render and return.
    if (AhviModuleCard.isModuleCard(response)) {
      final card = AhviModuleCard.fromResponse(response);
      if (card != null) {
        if (mounted) {
          setState(() {
            _isTyping = false;
            _messages.add(
              ChatMessage(
                text: card.summary.isEmpty ? card.title : card.summary,
                isBot: true,
                moduleCard: card,
              ),
            );
            _chatHistory.add({
              'role': 'assistant',
              'content': card.summary.isEmpty ? card.title : card.summary,
            });
          });
        }
        return;
      }
    }

    // Visual board response — render the structured meal board.
    if (AhviVisualBoard.isVisualBoard(response)) {
      final board = AhviVisualBoard.fromJson(response);
      final boardText = _responseText(response);
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(
            ChatMessage(
              text: boardText.isEmpty ? board.title : boardText,
              isBot: true,
              visualBoard: board,
            ),
          );
          _chatHistory.add({'role': 'assistant', 'content': board.title});
        });
      }
      return;
    }

    final String reply = _responseText(response);
    final String fallback = reply.isEmpty
        ? 'AHVI returned an empty response. Please try again.'
        : reply;
    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(text: fallback, isBot: true));
        _chatHistory.add({'role': 'assistant', 'content': fallback});
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
                        if (m.visualBoard != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AhviVisualBoardView(
                              board: m.visualBoard!,
                              surfaceColor: context.dSurface,
                              textColor: context.dText,
                              mutedColor: context.dMuted,
                              accentColor: context.dAccent,
                              borderColor: context.dBorder,
                            ),
                          ),
                        if (m.moduleCard != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AhviModuleCardView(
                              card: m.moduleCard!,
                              surfaceColor: context.dSurface,
                              textColor: context.dText,
                              mutedColor: context.dMuted,
                              accentColor: context.dAccent,
                              borderColor: context.dBorder,
                            ),
                          ),
                        if (m.plan != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            constraints: const BoxConstraints(maxWidth: 320),
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
                onSendMessage: _send,
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
  // height is the single control; width = height * (4/3) for 4:3 landscape
  final double height;
  const _MealImage({this.imagePath, required this.emoji, this.height = 56});

  double get _width => height; // 1:1 square

  Widget _fallback(BuildContext context) => Container(
        width: _width,
        height: height,
        decoration: BoxDecoration(
          color: context.dSurface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: height * 0.45)),
        ),
      );

  Widget _clip(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: _width, height: height, child: child),
      );

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) return _fallback(context);

    // Local asset — assets/images/meals/…
    if (imagePath!.startsWith('assets/')) {
      return _clip(
        Image.asset(
          imagePath!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(context),
        ),
      );
    }

    // Network URL (backend override)
    if (imagePath!.startsWith('http')) {
      return _clip(
        Image.network(
          imagePath!,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              color: context.dSurface2,
              child: Center(
                child: SizedBox(
                  width: height * 0.3,
                  height: height * 0.3,
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
          errorBuilder: (_, _, _) => _fallback(context),
        ),
      );
    }

    return _fallback(context);
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
