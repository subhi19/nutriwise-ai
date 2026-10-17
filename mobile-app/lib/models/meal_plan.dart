import 'nutrient_totals.dart';

double? _toDouble(dynamic v) => v is num ? v.toDouble() : null;

NutrientTotals? _nutrients(dynamic v) =>
    v is Map ? NutrientTotals.fromJson(Map<String, dynamic>.from(v)) : null;

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

/// One ingredient inside a meal. The server sends full details
/// ({name, food_id, weight_g, nutrients}); simple data may be just a name.
class PlannedIngredient {
  final String name;
  final int? foodId;
  final double? weightG;
  final NutrientTotals? nutrients;

  const PlannedIngredient({required this.name, this.foodId, this.weightG, this.nutrients});

  factory PlannedIngredient.fromJson(dynamic j) {
    if (j is String) return PlannedIngredient(name: j);
    final m = Map<String, dynamic>.from(j as Map);
    return PlannedIngredient(
      name: (m['name'] ?? '').toString(),
      foodId: (m['food_id'] as num?)?.toInt(),
      weightG: _toDouble(m['weight_g']),
      nutrients: _nutrients(m['nutrients']),
    );
  }

  /// Not in our nutrition database, so its numbers are AI estimates.
  bool get isEstimated => foodId == null && nutrients != null;

  double? get calories => nutrients?.calories;

  Map<String, dynamic> toJson() => {
        'name': name,
        'food_id': foodId,
        'weight_g': weightG,
        'nutrients': nutrients?.toJson(),
      };
}

class PlannedMeal {
  final String name;
  final List<PlannedIngredient> items; // full detail, as sent by the server
  final String? notes;
  final NutrientTotals? nutrients;
  final double? calories;

  PlannedMeal({
    required this.name,
    List<String> ingredients = const [], // simple form (names only), used by the mock
    List<PlannedIngredient>? items,
    this.notes,
    this.nutrients,
    double? calories,
  })  : items = items ?? ingredients.map((n) => PlannedIngredient(name: n)).toList(),
        calories = calories ?? nutrients?.calories;

  /// Ingredient names only.
  List<String> get ingredients => items.map((i) => i.name).toList();

  factory PlannedMeal.fromJson(Map<String, dynamic> j) {
    final n = _nutrients(j['nutrients']);
    return PlannedMeal(
      name: (j['name'] ?? '').toString(),
      items: ((j['ingredients'] as List?) ?? const []).map(PlannedIngredient.fromJson).toList(),
      notes: j['notes']?.toString(),
      nutrients: n,
      calories: n?.calories ?? _toDouble(j['calories']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'ingredients': items.map((i) => i.toJson()).toList(),
        'notes': notes,
        'nutrients': nutrients?.toJson(),
      };

  /// "—" when unknown or 0
  String get kcalLabel => (calories == null || calories! <= 0) ? '—' : '${calories!.round()} kcal';
}

class DayPlan {
  final String day;
  final PlannedMeal breakfast;
  final PlannedMeal lunch;
  final PlannedMeal dinner;
  final PlannedMeal? snack;
  final List<String> ingredients; // names for the whole day
  final NutrientTotals? nutrients; // day totals from the server
  final List<String> unmatchedIngredients; // AI-estimated, not in our database
  final double? declaredTotalCalories; // mock data only
  final double? totalProteinG; // mock data only

  DayPlan({
    required this.day,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    this.snack,
    this.ingredients = const [],
    this.nutrients,
    this.unmatchedIngredients = const [],
    this.declaredTotalCalories,
    this.totalProteinG,
  });

  Iterable<PlannedMeal> get meals => [breakfast, lunch, dinner, ?snack];

  double get totalCalories =>
      nutrients?.calories ??
      declaredTotalCalories ??
      meals.fold<double>(0, (sum, m) => sum + (m.calories ?? 0));

  double? get totalProtein => nutrients?.proteinG ?? totalProteinG;

  String get totalKcalLabel => totalCalories > 0 ? '${totalCalories.round()} kcal' : '—';
  String get totalProteinLabel => totalProtein == null ? '—' : '${totalProtein!.round()} g';
  String get totalCarbsLabel => nutrients == null ? '—' : '${nutrients!.carbsG.round()} g';
  String get totalFatLabel => nutrients == null ? '—' : '${nutrients!.fatG.round()} g';

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        day: j['day'].toString(),
        breakfast: PlannedMeal.fromJson(Map<String, dynamic>.from(j['breakfast'] as Map)),
        lunch: PlannedMeal.fromJson(Map<String, dynamic>.from(j['lunch'] as Map)),
        dinner: PlannedMeal.fromJson(Map<String, dynamic>.from(j['dinner'] as Map)),
        snack: j['snack'] == null
            ? null
            : PlannedMeal.fromJson(Map<String, dynamic>.from(j['snack'] as Map)),
        ingredients: _strings(j['ingredients']),
        nutrients: _nutrients(j['nutrients']),
        unmatchedIngredients: _strings(j['unmatched_ingredients']),
        declaredTotalCalories: _toDouble(j['total_calories']),
        totalProteinG: _toDouble(j['total_protein_g']),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'breakfast': breakfast.toJson(),
        'lunch': lunch.toJson(),
        'dinner': dinner.toJson(),
        'snack': snack?.toJson(),
        'ingredients': ingredients,
        'nutrients': nutrients?.toJson(),
        'unmatched_ingredients': unmatchedIngredients,
        if (declaredTotalCalories != null) 'total_calories': declaredTotalCalories,
        if (totalProteinG != null) 'total_protein_g': totalProteinG,
      };
}

class WeeklyPlan {
  final List<DayPlan> days;
  final List<String> notes;

  WeeklyPlan({required this.days, this.notes = const []});

  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        days: (j['days'] as List)
            .map((e) => DayPlan.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notes: _strings(j['notes']),
      );

  Map<String, dynamic> toJson() => {
        'days': days.map((d) => d.toJson()).toList(),
        'notes': notes,
      };
}