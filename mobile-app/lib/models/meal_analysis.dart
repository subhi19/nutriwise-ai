import 'nutrient_totals.dart';

class MealItem {
  final String name;
  final int? foodId;
  final double weightG;
  final NutrientTotals nutrients;
  final String confidence; // "low" | "medium" | "high"
  final bool needsReview;
  final bool userCorrected;

  MealItem({
    required this.name, this.foodId, required this.weightG,
    required this.nutrients, required this.confidence,
    this.needsReview = false, this.userCorrected = false,
  });

  factory MealItem.fromJson(Map<String, dynamic> j) => MealItem(
        name: j['name'],
        foodId: j['food_id'],
        weightG: (j['weight_g'] as num).toDouble(),
        nutrients: NutrientTotals.fromJson(j['nutrients']),
        confidence: j['confidence'],
        needsReview: j['needs_review'] ?? false,
        userCorrected: j['user_corrected'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name, 'food_id': foodId, 'weight_g': weightG,
        'nutrients': nutrients.toJson(), 'confidence': confidence,
        'needs_review': needsReview, 'user_corrected': userCorrected,
      };
}

class MealAnalysis {
  final List<MealItem> items;
  final NutrientTotals total;
  final List<String> missingNutrients;
  final List<String> suggestions;
  final List<String> unmatchedItems;

  MealAnalysis({
    required this.items, required this.total,
    required this.missingNutrients, required this.suggestions,
    this.unmatchedItems = const [],
  });

  factory MealAnalysis.fromJson(Map<String, dynamic> j) => MealAnalysis(
        items: (j['items'] as List).map((e) => MealItem.fromJson(e)).toList(),
        total: NutrientTotals.fromJson(j['total']),
        missingNutrients: List<String>.from(j['missing_nutrients'] ?? []),
        suggestions: List<String>.from(j['suggestions'] ?? []),
        unmatchedItems: List<String>.from(j['unmatched_items'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'total': total.toJson(),
        'missing_nutrients': missingNutrients,
        'suggestions': suggestions,
        'unmatched_items': unmatchedItems,
      };
}

class ItemCorrection {
  final int? itemIndex; // null = add a dish that was missed
  final String name;
  final double? weightG;

  ItemCorrection({this.itemIndex, required this.name, this.weightG});

  Map<String, dynamic> toJson() => {
        'item_index': itemIndex, 'name': name, 'weight_g': weightG,
      };
}