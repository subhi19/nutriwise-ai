const kMaxMealTypes = 2;
const kMaxCuisines = 2;

class DayPreference {
  final String day;
  final List<String> mealTypeCodes; // 1 to 2 codes
  final List<String> cuisinePreferences; // 0 to 2
  final String notes;

  DayPreference({
    required this.day,
    required this.mealTypeCodes,
    this.cuisinePreferences = const [],
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'meal_types': mealTypeCodes,
        'cuisine_preferences': cuisinePreferences,
        'notes': notes,
      };

  DayPreference copyWith({
    List<String>? mealTypeCodes,
    List<String>? cuisinePreferences,
    String? notes,
  }) =>
      DayPreference(
        day: day,
        mealTypeCodes: mealTypeCodes ?? this.mealTypeCodes,
        cuisinePreferences: cuisinePreferences ?? this.cuisinePreferences,
        notes: notes ?? this.notes,
      );
}

const kWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

List<DayPreference> defaultWeekPreferences() =>
    kWeekdays.map((d) => DayPreference(day: d, mealTypeCodes: ['VLML'])).toList();