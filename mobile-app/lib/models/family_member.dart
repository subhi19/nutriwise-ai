class FamilyMember {
  final String? id;
  final String name;
  final int age;
  final String gender;
  final List<String> allergies;
  final List<String> healthConditions; // always empty for MVP, kept for schema compatibility
  final String foodPreference; // single value: vegetarian | non_vegetarian | eggetarian | vegan
  final List<String> cuisinePreferences;

  FamilyMember({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    this.allergies = const [],
    this.healthConditions = const [],
    required this.foodPreference,
    this.cuisinePreferences = const [],
  });

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        id: j['id']?.toString(),
        name: j['name'],
        age: j['age'],
        gender: j['gender'],
        allergies: List<String>.from(j['allergies'] ?? []),
        healthConditions: List<String>.from(j['health_conditions'] ?? []),
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
        'health_conditions': healthConditions,
        'food_preferences': [foodPreference], // backend schema expects a list
        'cuisine_preferences': cuisinePreferences,
      };

  FamilyMember copyWith({String? id}) => FamilyMember(
        id: id ?? this.id,
        name: name,
        age: age,
        gender: gender,
        allergies: allergies,
        healthConditions: healthConditions,
        foodPreference: foodPreference,
        cuisinePreferences: cuisinePreferences,
      );
}