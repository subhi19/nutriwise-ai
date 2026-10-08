class PlannedMeal {
  final String name;
  final List<String> ingredients;
  final String? notes;

  PlannedMeal({required this.name, this.ingredients = const [], this.notes});

  factory PlannedMeal.fromJson(Map<String, dynamic> j) => PlannedMeal(
        name: j['name'],
        ingredients: List<String>.from(j['ingredients'] ?? []),
        notes: j['notes'],
      );

  Map<String, dynamic> toJson() => {'name': name, 'ingredients': ingredients, 'notes': notes};
}

class DayPlan {
  final String day;
  final PlannedMeal breakfast;
  final PlannedMeal lunch;
  final PlannedMeal dinner;
  final PlannedMeal? snack;
  final List<String> ingredients;

  DayPlan({
    required this.day,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    this.snack,
    this.ingredients = const [],
  });

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        day: j['day'],
        breakfast: PlannedMeal.fromJson(j['breakfast']),
        lunch: PlannedMeal.fromJson(j['lunch']),
        dinner: PlannedMeal.fromJson(j['dinner']),
        snack: j['snack'] == null ? null : PlannedMeal.fromJson(j['snack']),
        ingredients: List<String>.from(j['ingredients'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'breakfast': breakfast.toJson(),
        'lunch': lunch.toJson(),
        'dinner': dinner.toJson(),
        'snack': snack?.toJson(),
        'ingredients': ingredients,
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