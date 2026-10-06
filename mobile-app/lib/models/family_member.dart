class FamilyMember {
  final String? id;
  final String name;
  final int age;
  final String gender;
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

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        id: j['id']?.toString(),
        name: j['name'],
        age: j['age'],
        gender: j['gender'],
        allergies: List<String>.from(j['allergies'] ?? []),
        otherAllergies: List<String>.from(j['anyother_specific_allergy'] ?? []),
        foodPreference: (j['food_preferences'] as List?)?.isNotEmpty == true
            ? j['food_preferences'][0]
            : 'vegetarian',
        cuisinePreferences: List<String>.from(j['cuisine_preferences'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'gender': gender,
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