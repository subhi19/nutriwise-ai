import 'package:flutter/material.dart';
import 'theme.dart';

class AppIdentity {
  static const name = 'NutriWise AI';
  static const tagline = "Knows what's on your plate — what's handy and what's not";
  static const subTagline = 'Eat Healthy. Waste Less.';
  static const dashboardTagline = 'Stay Healthy, Feel Light';
}

class AppVocab {
  static const allergies = [
    'milk', 'peanut', 'egg', 'tree_nuts', 'soy', 'wheat', 'shellfish', 'fish',
  ];

  static const foodPreferences = [
    'vegetarian', 'non_vegetarian', 'eggetarian', 'vegan',
  ];

  static const cuisinePreferences = [
  'indian', 'chinese', 'italian', 'continental', 'mexican', 'malaysian',
  ];

  // UI-only: "any" maps to an empty list when sent to the backend,
  // per the AI contract ("empty cuisine_preferences = any cuisine").
  // Letting the user explicitly pick "Any" lets the field be mandatory
  // in the form while preserving that contract behavior.
  static const cuisineOptionsForUI = [
  'any', 'indian', 'chinese', 'italian', 'continental', 'mexican', 'malaysian',
  ];

  static String cuisineLabel(String value) =>
      value == 'any' ? 'Any Cuisine' : displayLabel(value);

  static String displayLabel(String value) {
    return value
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class AgeGroupStyle {
  final Color color;
  final String emoji;
  const AgeGroupStyle(this.color, this.emoji);

  static AgeGroupStyle forAge(int age) {
    if (age < 13) return const AgeGroupStyle(AppColors.child, '🧒');
    if (age < 60) return const AgeGroupStyle(AppColors.adult, '🧑');
    return const AgeGroupStyle(AppColors.senior, '👴');
  }
}

class FoodPrefStyle {
  static Color colorFor(String pref) {
    switch (pref) {
      case 'vegetarian':
        return AppColors.primary;
      case 'vegan':
        return const Color(0xFF00897B);
      case 'eggetarian':
        return AppColors.tertiary;
      case 'non_vegetarian':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  static String emojiFor(String pref) {
    switch (pref) {
      case 'vegetarian':
        return '🥦';
      case 'vegan':
        return '🌱';
      case 'eggetarian':
        return '🥚';
      case 'non_vegetarian':
        return '🍗';
      default:
        return '🍽️';
    }
  }
}

