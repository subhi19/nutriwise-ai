import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_analysis.dart';

class LocalStorageService {
  static const _key = 'saved_meal_history';

  static Future<void> saveMealRecord(Uint8List image, MealAnalysis analysis) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    final record = {
      'image_base64': base64Encode(image),
      'analysis': analysis.toJson(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    existing.add(jsonEncode(record));
    await prefs.setStringList(_key, existing);
  }

  static Future<List<Map<String, dynamic>>> getSavedMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    return existing.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
}