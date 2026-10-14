import 'meal_type.dart';

const kMaxMealTypes = 2;
const kMaxCuisines = 2;

/// The meals the server plans for every day.
const kMealSlots = ['breakfast', 'lunch', 'dinner', 'snack'];

class DayPreference {
  final String day;
  final List<String> mealTypeCodes; // dietary types picked in the app (1 to 2), e.g. VLML
  final List<String> cuisinePreferences; // 0 to 2
  final String notes; // the user's note for the week

  DayPreference({
    required this.day,
    required this.mealTypeCodes,
    this.cuisinePreferences = const [],
    this.notes = '',
  });

  /// The server's `meal_types` means "which meals to plan". Our dietary types
  /// (Jain, Halal, Vegan…) have no field of their own, so they travel as
  /// plain-language text at the start of `notes`.
  String get _combinedNotes {
    final dietary = mealTypeCodes.map((c) {
      final m = mealTypeByCode(c);
      return '${m.label} (${m.description})';
    }).join(' + ');
    final parts = <String>[
      if (dietary.isNotEmpty) 'Dietary type for this day: $dietary.',
      if (notes.trim().isNotEmpty) notes.trim(),
    ];
    return parts.join(' ');
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'meal_types': kMealSlots,
        'cuisine_preferences': cuisinePreferences,
        'notes': _combinedNotes,
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