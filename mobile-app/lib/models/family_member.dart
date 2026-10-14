String _titleCase(String s) {
  final t = s.trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1).toLowerCase();
}

// "Non vegetarian" / "non-vegetarian" / "Tree Nuts" -> non_vegetarian / tree_nuts
String _snake(dynamic v) => v.toString().trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

class FamilyMember {
  final String? id;
  final String name;
  final int age;
  final String gender; // Male / Female / Other in the app, lowercase on the wire
  final List<String> allergies;
  final List<String> otherAllergies; // maps to anyother_specific_allergy
  final String foodPreference;
  final List<String> cuisinePreferences;

  FamilyMember({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    this.allergies = const [],
    this.otherAllergies = const [],
    required this.foodPreference,
    this.cuisinePreferences = const [],
  });

  factory FamilyMember.fromJson(Map<String, dynamic> j) {
    final diets = (j['food_preferences'] as List?) ?? const [];
    return FamilyMember(
      id: j['id']?.toString(),
      name: j['name'],
      age: (j['age'] as num).toInt(),
      gender: _titleCase((j['gender'] ?? '').toString()),
      allergies: ((j['allergies'] as List?) ?? const []).map(_snake).toList(),
      otherAllergies:
          ((j['anyother_specific_allergy'] as List?) ?? const []).map((e) => e.toString()).toList(),
      foodPreference: diets.isNotEmpty ? _snake(diets.first) : 'vegetarian',
      cuisinePreferences:
          ((j['cuisine_preferences'] as List?) ?? const []).map(_snake).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'gender': gender.toLowerCase(),
        'allergies': allergies,
        'anyother_specific_allergy': otherAllergies,
        'food_preferences': [foodPreference],
        'cuisine_preferences': cuisinePreferences,
      };

  FamilyMember copyWith({String? id}) => FamilyMember(
        id: id ?? this.id,
        name: name,
        age: age,
        gender: gender,
        allergies: allergies,
        otherAllergies: otherAllergies,
        foodPreference: foodPreference,
        cuisinePreferences: cuisinePreferences,
      );
}