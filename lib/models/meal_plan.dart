import 'dart:convert';

// Diet meal-plan models. Extracted from diet_page.dart so the persistence
// lifecycle (parse / payload / controller) is unit-testable without pulling in
// the UI. diet_page.dart re-exports these for existing callers.

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
  String? documentId; // Appwrite $id — authoritative persistence identity.
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
    this.documentId,
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
    String? documentId,
  }) {
    return MealPlan(
      id: id,
      documentId: documentId ?? this.documentId,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      planType: planType ?? this.planType,
      meals: meals ?? this.meals,
      days: days ?? this.days,
    );
  }

  /// Appwrite `meal_plans` write payload — editable schema fields only.
  /// Never includes userId / $id / $createdAt. Meals are serialised with the
  /// same compact JSON shape used at create time.
  Map<String, dynamic> toAppwritePayload() {
    final List<Meal> flat =
        planType == 'daily' ? meals : days.expand((d) => d.meals).toList();
    final mealJson = flat
        .map((m) => jsonEncode({
              'type': m.type,
              'name': m.name,
              'desc': m.desc,
              'cal': m.cal,
              'protein': m.protein,
              'carbs': m.carbs,
              'fat': m.fat,
            }))
        .toList();
    return {
      'name': name,
      'desc': desc.trim().isEmpty ? name : desc,
      'planType': planType,
      'totalCal': totalCal,
      'meals': mealJson,
    };
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? (double.tryParse(t)?.toInt() ?? 0);
  }
  return 0;
}

Meal? _mealFromEntry(dynamic entry) {
  Map<String, dynamic>? map;
  if (entry is Map) {
    map = Map<String, dynamic>.from(entry);
  } else if (entry is String) {
    final t = entry.trim();
    if (t.isEmpty) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map) map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null; // malformed JSON string — skip
    }
  }
  if (map == null) return null;
  final name = (map['name'] ?? '').toString().trim();
  if (name.isEmpty) return null; // malformed/empty entry — skip
  return Meal(
    type: (map['type'] ?? '').toString(),
    name: name,
    desc: (map['desc'] ?? '').toString(),
    cal: _toInt(map['cal']),
    protein: _toInt(map['protein']),
    carbs: _toInt(map['carbs']),
    fat: _toInt(map['fat']),
    cls: (map['cls'] ?? '').toString(),
    icon: (map['icon'] ?? '').toString(),
  );
}

/// Parse an Appwrite meal-plan document (merged `{'$id': ..., ...doc.data}`)
/// into a flattened daily [MealPlan]. Returns null if the document itself is
/// unusable; individual malformed meals are skipped, not fatal.
MealPlan? mealPlanFromDocumentData(Map<String, dynamic> data) {
  try {
    final docId = (data[r'$id'] as Object?)?.toString().trim();
    final name = (data['name'] ?? '').toString();
    final desc = (data['desc'] ?? '').toString();
    final rawType = (data['planType'] ?? '').toString().trim();
    final planType = rawType.isEmpty ? 'daily' : rawType;

    final meals = <Meal>[];
    final rawMeals = data['meals'];
    if (rawMeals is List) {
      for (final e in rawMeals) {
        final m = _mealFromEntry(e);
        if (m != null) meals.add(m);
      }
    }

    return MealPlan(
      id: (docId != null && docId.isNotEmpty ? docId : name).hashCode,
      documentId: (docId != null && docId.isNotEmpty) ? docId : null,
      name: name,
      desc: desc,
      planType: planType,
      meals: meals,
    );
  } catch (_) {
    return null;
  }
}
