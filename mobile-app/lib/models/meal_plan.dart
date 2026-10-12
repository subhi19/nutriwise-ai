double? _toDouble(dynamic v) => v is num ? v.toDouble() : null;

class PlannedMeal {
  final String name;
  final List<String> ingredients;
  final String? notes;
  final double? calories;

  PlannedMeal({required this.name, this.ingredients = const [], this.notes, this.calories});

  factory PlannedMeal.fromJson(Map<String, dynamic> j) => PlannedMeal(
        name: j['name'],
        ingredients: List<String>.from(j['ingredients'] ?? []),
        notes: j['notes'],
        calories: _toDouble(j['calories']),
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'ingredients': ingredients, 'notes': notes, 'calories': calories};

  /// "—" when unknown or 0 (e.g. a food that didn't match the database)
  String get kcalLabel => (calories == null || calories! <= 0) ? '—' : '${calories!.round()} kcal';
}

class DayPlan {
  final String day;
  final PlannedMeal breakfast;
  final PlannedMeal lunch;
  final PlannedMeal dinner;
  final PlannedMeal? snack;
  final List<String> ingredients;
  final double? declaredTotalCalories;
  final double? totalProteinG;

  DayPlan({
    required this.day,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    this.snack,
    this.ingredients = const [],
    this.declaredTotalCalories,
    this.totalProteinG,
  });

  double get totalCalories =>
      declaredTotalCalories ??
      [breakfast, lunch, dinner, snack]
          .whereType<PlannedMeal>()
          .fold<double>(0, (sum, m) => sum + (m.calories ?? 0));

  String get totalKcalLabel => totalCalories > 0 ? '${totalCalories.round()} kcal' : '—';
  String get totalProteinLabel => totalProteinG == null ? '—' : '${totalProteinG!.round()} g';

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        day: j['day'],
        breakfast: PlannedMeal.fromJson(j['breakfast']),
        lunch: PlannedMeal.fromJson(j['lunch']),
        dinner: PlannedMeal.fromJson(j['dinner']),
        snack: j['snack'] == null ? null : PlannedMeal.fromJson(j['snack']),
        ingredients: List<String>.from(j['ingredients'] ?? []),
        declaredTotalCalories: _toDouble(j['total_calories'] ?? j['calories']),
        totalProteinG: _toDouble(j['total_protein_g'] ?? j['protein_g']),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'breakfast': breakfast.toJson(),
        'lunch': lunch.toJson(),
        'dinner': dinner.toJson(),
        'snack': snack?.toJson(),
        'ingredients': ingredients,
        'total_calories': declaredTotalCalories,
        'total_protein_g': totalProteinG,
      };
}

class WeeklyPlan {
  final List<DayPlan> days;
  final List<String> notes;

  WeeklyPlan({required this.days, this.notes = const []});

  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        days: (j['days'] as List).map((e) => DayPlan.fromJson(e)).toList(),
        notes: List<String>.from(j['notes'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'days': days.map((d) => d.toJson()).toList(),
        'notes': notes,
      };
}