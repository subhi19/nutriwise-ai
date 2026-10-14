class MealTypeOption {
  final String code;
  final String label;
  final String description;
  const MealTypeOption(this.code, this.label, this.description);
}

const kMealTypes = [
  MealTypeOption('MOML', 'Muslim Meal', 'Prepared to Islamic Halal standards'),
  MealTypeOption('HNML', 'Hindu Non-Vegetarian Meal', 'Indian-style, no beef or pork'),
  MealTypeOption('VJML', 'Vegetarian Jain Meal', 'No root vegetables, strictly plant-based'),
  MealTypeOption('VLML', 'Vegetarian Lacto-Ovo Meal', 'Vegetarian with eggs and dairy'),
  MealTypeOption('VGML', 'Vegan Meal', 'Fully plant-based, no animal products'),
  MealTypeOption('KSML', 'Kosher Meal', 'Prepared to Jewish dietary laws'),
  MealTypeOption('FPML', 'Fruit Platter Meal', 'Fresh seasonal fruit only'),
  MealTypeOption('SFML', 'Seafood Meal', 'Seafood-based dishes throughout'),
  MealTypeOption('AVML', 'Asian Vegetarian Meal', 'Indian-style vegetarian'),
  MealTypeOption('RVML', 'Raw Vegetarian Meal', 'Uncooked plant-based ingredients'),
  MealTypeOption('VOML', 'Vegetarian Oriental Meal', 'Asian-style vegetarian'),
];

MealTypeOption mealTypeByCode(String code) =>
    kMealTypes.firstWhere((m) => m.code == code, orElse: () => kMealTypes[3]);