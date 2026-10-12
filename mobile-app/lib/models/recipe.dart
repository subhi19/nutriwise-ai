import 'nutrient_totals.dart';

double? _num(dynamic v) => v is num ? v.toDouble() : null;
String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class RecipeIngredient {
  final String name;
  final double? weightG;
  final double? calories;
  final bool aiEstimate; // true when the item wasn't found in the nutrition database

  RecipeIngredient({required this.name, this.weightG, this.calories, this.aiEstimate = false});

  // Accepts a plain string (older contract) or an object (newer output).
  factory RecipeIngredient.fromJson(dynamic j) {
    if (j is String) return RecipeIngredient(name: j);
    final m = Map<String, dynamic>.from(j as Map);
    return RecipeIngredient(
      name: (m['name'] ?? '').toString(),
      weightG: _num(m['weight_g']),
      calories: _num(m['calories'] ?? m['kcal']),
      aiEstimate: (m['ai_estimate'] ?? m['ai_estimated'] ?? false) == true,
    );
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'weight_g': weightG, 'calories': calories, 'ai_estimate': aiEstimate};

  String get label {
    final parts = <String>[];
    if (weightG != null) parts.add('${weightG!.round()} g');
    if (calories != null) parts.add('${calories!.round()} kcal');
    return parts.isEmpty ? name : '$name — ${parts.join(' · ')}';
  }
}

class Recipe {
  final String name;
  final NutrientTotals? nutrition;
  final List<RecipeIngredient> ingredients;
  final List<String> pantryStaples;
  final List<String> steps;

  Recipe({
    required this.name,
    this.nutrition,
    this.ingredients = const [],
    this.pantryStaples = const [],
    this.steps = const [],
  });

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final raw = (j['ingredients'] ?? j['ingredients_from_fridge'] ?? []) as List;
    return Recipe(
      name: j['name'],
      nutrition: j['nutrition'] is Map
          ? NutrientTotals.fromJson(Map<String, dynamic>.from(j['nutrition']))
          : null,
      ingredients: raw.map(RecipeIngredient.fromJson).toList(),
      pantryStaples: List<String>.from(j['pantry_staples'] ?? j['extra_ingredients'] ?? []),
      steps: List<String>.from(j['steps'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'nutrition': nutrition?.toJson(),
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'pantry_staples': pantryStaples,
        'steps': steps,
      };

  String get nutritionLine {
    final n = nutrition;
    if (n == null) return '';
    return '${_fmt(n.calories)} kcal · protein ${_fmt(n.proteinG)} g · carbs ${_fmt(n.carbsG)} g · '
        'fat ${_fmt(n.fatG)} g · fiber ${_fmt(n.fiberG)} g';
  }
}

class RecipeSuggestions {
  final List<Recipe> recipes;
  RecipeSuggestions({required this.recipes});

  factory RecipeSuggestions.fromJson(Map<String, dynamic> j) => RecipeSuggestions(
        recipes: (j['recipes'] as List).map((e) => Recipe.fromJson(Map<String, dynamic>.from(e))).toList(),
      );

  Map<String, dynamic> toJson() => {'recipes': recipes.map((r) => r.toJson()).toList()};
}