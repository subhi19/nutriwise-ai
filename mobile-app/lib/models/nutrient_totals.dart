class NutrientTotals {
  final double calories, proteinG, carbsG, fatG, fiberG,
      ironMg, calciumMg, vitaminAMcg, vitaminCMg;

  NutrientTotals({
    this.calories = 0, this.proteinG = 0, this.carbsG = 0, this.fatG = 0,
    this.fiberG = 0, this.ironMg = 0, this.calciumMg = 0,
    this.vitaminAMcg = 0, this.vitaminCMg = 0,
  });

  factory NutrientTotals.fromJson(Map<String, dynamic> j) => NutrientTotals(
        calories: (j['calories'] ?? 0).toDouble(),
        proteinG: (j['protein_g'] ?? 0).toDouble(),
        carbsG: (j['carbs_g'] ?? 0).toDouble(),
        fatG: (j['fat_g'] ?? 0).toDouble(),
        fiberG: (j['fiber_g'] ?? 0).toDouble(),
        ironMg: (j['iron_mg'] ?? 0).toDouble(),
        calciumMg: (j['calcium_mg'] ?? 0).toDouble(),
        vitaminAMcg: (j['vitamin_a_mcg'] ?? 0).toDouble(),
        vitaminCMg: (j['vitamin_c_mg'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'calories': calories, 'protein_g': proteinG, 'carbs_g': carbsG,
        'fat_g': fatG, 'fiber_g': fiberG, 'iron_mg': ironMg,
        'calcium_mg': calciumMg, 'vitamin_a_mcg': vitaminAMcg, 'vitamin_c_mg': vitaminCMg,
      };
}