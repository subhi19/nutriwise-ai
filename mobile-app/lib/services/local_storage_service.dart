import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grocery_list.dart';
import '../models/meal_analysis.dart';
import '../models/meal_plan.dart';
import '../models/recipe.dart'; 

class LocalStorageService {
  static const _mealKey = 'saved_meal_history';
  static const _planKey = 'saved_meal_plans';
  static const _groceryKey = 'saved_grocery_lists';
  static const _recipeKey = 'saved_recipes';

  static Future<void> _append(String key, Map<String, dynamic> record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(key) ?? [];
    existing.add(jsonEncode(record));
    await prefs.setStringList(key, existing);
  }

  static Future<void> saveMealRecord(Uint8List image, MealAnalysis analysis) =>
      _append(_mealKey, {
        'image_base64': base64Encode(image),
        'analysis': analysis.toJson(),
        'saved_at': DateTime.now().toIso8601String(),
      });

  static Future<void> savePlan(WeeklyPlan plan) => _append(_planKey, {
        'plan': plan.toJson(),
        'saved_at': DateTime.now().toIso8601String(),
      });

  static Future<void> saveGroceryList(GroceryList list, Set<String> checkedKeys) =>
      _append(_groceryKey, {
        'list': list.toJson(),
        'checked': checkedKeys.toList(),
        'saved_at': DateTime.now().toIso8601String(),
      });

  static Future<List<Map<String, dynamic>>> getSavedMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_mealKey) ?? [];
    return existing.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> saveRecipes(RecipeSuggestions s) => _append(_recipeKey, {
      'recipes': s.toJson(),
      'saved_at': DateTime.now().toIso8601String(),
    });
}