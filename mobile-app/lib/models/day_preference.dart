class DayPreference {
  final String day;
  final String mealTypeCode;
  final List<String> cuisinePreferences;

  DayPreference({
    required this.day,
    required this.mealTypeCode,
    this.cuisinePreferences = const [],
  });

  Map<String, dynamic> toJson() => {
        'meal_type': mealTypeCode,
        'cuisine_preferences': cuisinePreferences,
      };

  DayPreference copyWith({String? mealTypeCode, List<String>? cuisinePreferences}) => DayPreference(
        day: day,
        mealTypeCode: mealTypeCode ?? this.mealTypeCode,
        cuisinePreferences: cuisinePreferences ?? this.cuisinePreferences,
      );
}

const kWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

List<DayPreference> defaultWeekPreferences() =>
    kWeekdays.map((d) => DayPreference(day: d, mealTypeCode: 'VLML')).toList();