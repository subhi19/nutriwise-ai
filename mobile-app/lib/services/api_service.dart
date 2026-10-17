import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/auth_session.dart';
import '../models/day_preference.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/grocery_list.dart';
import '../models/meal_analysis.dart';
import '../models/meal_plan.dart';
import '../models/meal_type.dart';
import '../models/nutrient_totals.dart';
import '../models/recipe.dart';

const kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

// Flip to true once AI/backend confirm they accept `day_preferences`.
const kSendDayPreferences = true;

// ---------- Error handling ----------

class ApiException implements Exception {
  final String code;
  final String message;
  final bool retry;
  ApiException({required this.code, required this.message, required this.retry});

  // AI-pipeline envelope: { "error": { "code", "message", "retry" } }
  factory ApiException.fromAiEnvelope(Map<String, dynamic> body) {
    final err = body['error'];
    return ApiException(
      code: err['code'] ?? 'INTERNAL',
      message: err['message'] ?? 'Something went wrong',
      retry: err['retry'] ?? false,
    );
  }

  // Standard FastAPI auth envelope: { "detail": "..." }
  factory ApiException.fromDetail(String detail) =>
      ApiException(code: 'AUTH_ERROR', message: detail, retry: false);

  @override
  String toString() => message;
}

// ---------- Abstract interface ----------

abstract class NutriApi {
  Future<AuthSession> login(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> deleteMember(String memberId);
  Future<String?> forgotPassword(String email); // returns a reset code only if the server includes one
  Future<void> resetPassword({required String token, required String newPassword});
  Future<List<FamilyMember>> getMembers(int userId);
  Future<FamilyMember> createMember(int userId, FamilyMember member);
  Future<FamilyMember> updateMember(String memberId, FamilyMember member);
  Future<MealAnalysis> analyzeMeal(Uint8List image, FamilyMember member);
  Future<MealAnalysis> correctMeal(MealAnalysis previous, List<ItemCorrection> corrections, FamilyMember member);
  Future<FridgeInventory> analyzeFridge(Uint8List image);
  Future<WeeklyPlan> generateMealPlan(
    List<FamilyMember> family, FridgeInventory? inventory, List<DayPreference> dayPreferences);
  Future<GroceryList> generateGroceryList(List<FamilyMember> family, WeeklyPlan plan,
    FridgeInventory? inventory, List<String> userRequirements);
  Future<RecipeSuggestions> suggestRecipes(FridgeInventory inventory, List<FamilyMember> family);
}

// ---------- Mock implementation ----------

class MockApi implements NutriApi {
  final List<FamilyMember> _members = [];
  int _nextId = 1;

  @override
  Future<AuthSession> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return AuthSession(
      accessToken: 'mock-token',
      userId: 1,
      name: 'Mock User',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  @override
  Future<void> register(String name, String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<List<FamilyMember>> getMembers(int userId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.of(_members);
  }

  @override
  Future<FamilyMember> createMember(int userId, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final saved = member.copyWith(id: 'mock-${_nextId++}');
    _members.add(saved);
    return saved;
  }

  @override
  Future<FamilyMember> updateMember(String memberId, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final index = _members.indexWhere((m) => m.id == memberId);
    final updated = member.copyWith(id: memberId);
    if (index != -1) _members[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMember(String memberId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _members.removeWhere((m) => m.id == memberId);
  }

  @override
  Future<String?> forgotPassword(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return 'MOCK-1234'; // mock only: pretend the server returned a code
  }

  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (token.trim().toUpperCase() != 'MOCK-1234') {
      throw ApiException(code: 'AUTH_ERROR', message: 'That reset code is invalid or has expired.', retry: false);
    }
  }

  @override
  Future<MealAnalysis> analyzeMeal(Uint8List image, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    return MealAnalysis(
      items: [
        MealItem(
          name: 'Cooked basmati rice', foodId: 12, weightG: 150,
          nutrients: NutrientTotals(calories: 195, proteinG: 4, carbsG: 42, fatG: 0.4,
              fiberG: 0.6, ironMg: 0.5, calciumMg: 15, vitaminAMcg: 0, vitaminCMg: 0),
          confidence: 'high',
        ),
        MealItem(
          name: 'Yellow dal', foodId: 48, weightG: 100,
          nutrients: NutrientTotals(calories: 110, proteinG: 6, carbsG: 15, fatG: 3,
              fiberG: 3, ironMg: 1.6, calciumMg: 25, vitaminAMcg: 5, vitaminCMg: 1),
          confidence: 'medium',
        ),
      ],
      total: NutrientTotals(calories: 305, proteinG: 10, carbsG: 57, fatG: 3.4,
          fiberG: 3.6, ironMg: 2.1, calciumMg: 40, vitaminAMcg: 5, vitaminCMg: 1),
      missingNutrients: ['Vitamin C', 'Fiber'],
      suggestions: ['Add a cucumber and tomato salad to increase fiber and vitamin C.'],
    );
  }

  @override
  Future<MealAnalysis> correctMeal(MealAnalysis previous, List<ItemCorrection> corrections, FamilyMember member) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final items = List<MealItem>.from(previous.items);
    for (final c in corrections) {
      final corrected = MealItem(
        name: c.name,
        weightG: c.weightG ?? 100,
        nutrients: NutrientTotals(calories: 120, proteinG: 5, carbsG: 20, fatG: 2),
        confidence: 'medium',
        userCorrected: true,
      );
      if (c.itemIndex != null && c.itemIndex! < items.length) {
        items[c.itemIndex!] = corrected;
      } else {
        items.add(corrected);
      }
    }
    return MealAnalysis(
      items: items,
      total: previous.total,
      missingNutrients: previous.missingNutrients,
      suggestions: previous.suggestions,
    );
  }

  @override
  Future<FridgeInventory> analyzeFridge(Uint8List image) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return FridgeInventory(items: [
      InventoryItem(name: 'Spinach', quantity: '1 bunch', useSoon: true),
      InventoryItem(name: 'Tomato', quantity: '4', useSoon: true),
      InventoryItem(name: 'Eggs', quantity: '6'),
      InventoryItem(name: 'Milk'),
      InventoryItem(name: 'Paneer', quantity: '200 g'),
    ]);
  }

  @override
  Future<WeeklyPlan> generateMealPlan(
      List<FamilyMember> family, FridgeInventory? inventory, List<DayPreference> dayPreferences) async {
    await Future.delayed(const Duration(milliseconds: 1800));

    PlannedMeal m(String n, List<String> i, double kcal, [String? note]) =>
        PlannedMeal(name: n, ingredients: i, calories: kcal, notes: note);

    final breakfasts = [
      m('Indian Masala Omelette', ['Eggs', 'Onion', 'Tomato'], 216),
      m('Banana and Kiwi Fruit Bowl', ['Banana', 'Kiwi'], 261),
      m('Indian Veggie Poha', ['Poha', 'Peas', 'Carrot'], 248),
      m('Dairy-Free Banana Pancakes', ['Wheat flour', 'Banana'], 360),
    ];
    final lunches = [
      m('Chinese Chicken and Cabbage Stir-Fry', ['Chicken', 'Cabbage', 'Garlic'], 557),
      m('Indian Chana Masala with Rice', ['Chickpeas', 'Rice', 'Spices'], 283),
      m('Chinese Veggie Fried Rice', ['Rice', 'Mixed vegetables', 'Soy sauce'], 490),
      m('Indian Dal Tadka with Roti', ['Toor dal', 'Wheat flour', 'Cumin'], 330),
    ];
    final dinners = [
      m('Indian Egg Curry with Roti', ['Eggs', 'Onion', 'Wheat flour'], 353),
      m('Chinese Egg Drop Soup', ['Eggs', 'Cabbage'], 280),
      m('Indian Chicken Curry with Rice', ['Chicken', 'Basmati rice', 'Spices'], 794),
      m('Indian Aloo Gobi with Roti', ['Potato', 'Cauliflower', 'Wheat flour'], 429),
    ];
    final snacks = [
      m('Fresh Fruit Salad', ['Apple', 'Orange', 'Grapes'], 74),
      m('Cucumber Slices with Pepper', ['Cucumber', 'Pepper'], 23),
      m('Sweet Grape and Mandarin Mix', ['Grapes', 'Mandarin'], 89),
    ];
    final pantry = inventory?.items.map((i) => i.name).toList() ?? <String>[];

    final days = <DayPlan>[];
    for (var i = 0; i < 7; i++) {
      final pref = i < dayPreferences.length ? dayPreferences[i] : null;
      final typeLabels =
          pref?.mealTypeCodes.map((c) => mealTypeByCode(c).label).join(' + ');
      final userNote = (pref?.notes ?? '').trim();

      final b = breakfasts[i % breakfasts.length];
      final l0 = lunches[i % lunches.length];
      final d0 = dinners[i % dinners.length];
      final s = snacks[i % snacks.length];

      final l = m(l0.name, l0.ingredients, l0.calories!, typeLabels);
      final d = (pantry.isNotEmpty && (i == 0 || i == 3))
          ? m(d0.name, [...d0.ingredients, ...pantry.take(2)], d0.calories!, 'Uses items from your fridge')
          : m(d0.name, d0.ingredients, d0.calories!, userNote.isEmpty ? null : 'Your note: $userNote');

      final total = b.calories! + l.calories! + d.calories! + s.calories!;
      days.add(DayPlan(
        day: kWeekdays[i],
        breakfast: b,
        lunch: l,
        dinner: d,
        snack: s,
        ingredients: {...b.ingredients, ...l.ingredients, ...d.ingredients, ...s.ingredients}.toList(),
        declaredTotalCalories: total,
        totalProteinG: total * 0.055,
      ));
    }
    return WeeklyPlan(days: days, notes: ['Mock plan for UI testing only.']);
  }

  @override
  Future<GroceryList> generateGroceryList(List<FamilyMember> family, WeeklyPlan plan,
      FridgeInventory? inventory, List<String> userRequirements) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final have = inventory?.items.map((i) => i.name.toLowerCase()).toList() ?? <String>[];
    bool atHome(String ing) {
      final s = ing.toLowerCase();
      return have.any((h) => s.contains(h) || h.contains(s));
    }

    String categoryOf(String name) {
      final s = name.toLowerCase();
      if (RegExp(r'milk|yogurt|paneer|cheese|curd|butter').hasMatch(s)) return 'Dairy';
      if (RegExp(r'chicken|fish|egg|meat|tofu').hasMatch(s)) return 'Protein';
      if (RegExp(r'rice|flour|oats|bread|poha|semolina|noodle').hasMatch(s)) return 'Grains';
      if (RegExp(r'dal|chickpea|lentil|kidney').hasMatch(s)) return 'Pulses';
      if (RegExp(r'apple|banana|orange|kiwi|grape|mango|mandarin').hasMatch(s)) return 'Fruits';
      if (RegExp(r'spice|cumin|salt|pepper|masala|sauce|oil').hasMatch(s)) return 'Spices & Pantry';
      return 'Vegetables';
    }

    final counts = <String, int>{};
    for (final d in plan.days) {
      for (final ing in d.ingredients) {
        if (!atHome(ing)) counts[ing] = (counts[ing] ?? 0) + 1;
      }
    }
    final items = counts.entries.map((e) {
      final cat = categoryOf(e.key);
      return GroceryItem(
        name: e.key,
        quantity: cat == 'Spices & Pantry' ? '1 pack' : '${e.value * 200} g',
        category: cat,
        source: 'missing_ingredient',
      );
    }).toList()
      ..sort((a, b) => a.category.compareTo(b.category));

    for (final r in userRequirements) {
      items.add(GroceryItem(name: r, quantity: '1 pack', category: 'Other', source: 'user_added'));
    }
    // Mock only: pretend the last typed item isn't in the catalog, so that UI section can be tested.
    return GroceryList(
      items: items,
      notInDatabase: userRequirements.isEmpty ? [] : [userRequirements.last],
    );
  }

  int _recipeCalls = 0;

  @override
  Future<RecipeSuggestions> suggestRecipes(FridgeInventory inventory, List<FamilyMember> family) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    RecipeIngredient ing(String n, double g, double kcal, [bool est = false]) =>
        RecipeIngredient(name: n, weightG: g, calories: kcal, aiEstimate: est);
    NutrientTotals nut(double k, double p, double c, double f, double fi) =>
        NutrientTotals(calories: k, proteinG: p, carbsG: c, fatG: f, fiberG: fi);

    final setA = [
      Recipe(
        name: 'Cabbage, Beetroot, and Carrot Slaw',
        nutrition: nut(169, 5.8, 39.7, 0.7, 12.3),
        ingredients: [ing('Cabbage', 200, 50, true), ing('Beetroot', 100, 43, true),
          ing('Carrot (raw)', 100, 33), ing('Orange', 50, 43)],
        pantryStaples: ['oil', 'salt', 'black pepper'],
        steps: ['Finely shred the cabbage, beetroot, and carrot.',
          'Squeeze the citrus juice into a small bowl.',
          'Whisk the juice with oil, salt, and pepper.',
          'Toss everything together and rest for 10 minutes.'],
      ),
      Recipe(
        name: 'Simple Tomato Cucumber Salad',
        nutrition: nut(66, 3.2, 15, 0.6, 3.4),
        ingredients: [ing('Tomato (raw)', 200, 36), ing('Cucumber (raw)', 200, 30)],
        pantryStaples: ['oil', 'salt', 'black pepper'],
        steps: ['Dice the tomatoes and cucumbers.', 'Combine in a bowl.',
          'Drizzle with oil and season.', 'Toss gently and serve.'],
      ),
      Recipe(
        name: 'Fresh Mixed Fruit Bowl',
        nutrition: nut(209.5, 4.8, 43.2, 3.7, 9.8),
        ingredients: [ing('Apple', 150, 78), ing('Kiwi', 100, 61, true), ing('Orange', 100, 86)],
        steps: ['Core and chop the apples.', 'Peel and slice the kiwis and orange.',
          'Mix everything in a bowl and serve immediately.'],
      ),
    ];
    final setB = [
      Recipe(
        name: 'Apple Carrot Crunch Salad',
        nutrition: nut(150, 2.1, 35, 0.5, 7.5),
        ingredients: [ing('Apple', 150, 78), ing('Carrot (raw)', 120, 40), ing('Orange', 60, 28)],
        pantryStaples: ['salt'],
        steps: ['Grate the carrot and apple.', 'Add orange juice and a pinch of salt.', 'Mix and serve cold.'],
      ),
      Recipe(
        name: 'Cucumber Orange Cooler',
        nutrition: nut(95, 2.0, 22, 0.3, 4.1),
        ingredients: [ing('Cucumber (raw)', 250, 38), ing('Orange', 120, 57)],
        steps: ['Slice the cucumber thinly.', 'Add orange segments.', 'Chill for 10 minutes and serve.'],
      ),
    ];
    return RecipeSuggestions(recipes: (_recipeCalls++ % 2 == 0) ? setA : setB);
  }
}

// ---------- Live-contract switch ----------

/// /api/meal/correct: our AI contract says `corrections` is a list of
/// {item_index, name, weight_g}. The backend's example showed a plain sentence.
/// Check MealCorrectionPayload in Swagger (/docs). If it says "string", set this to true.
/// Which form of `corrections` to try FIRST for /api/meal/correct.
/// true  = a sentence (what the backend team's example showed)
/// false = a list of {item_index, name, weight_g} (what the AI contract says)
const kCorrectionsAsText = false;

String _correctionsToText(MealAnalysis prev, List<ItemCorrection> cs) {
  return cs.map((c) {
    final w = c.weightG == null ? '' : ' (${c.weightG!.round()} g)';
    final i = c.itemIndex;
    if (i != null && i >= 0 && i < prev.items.length) {
      final old = prev.items[i];
      if (old.name.trim().toLowerCase() == c.name.trim().toLowerCase()) {
        return 'Changed the amount of "${old.name}" to ${c.weightG?.round()} g';
      }
      return 'Replaced "${old.name}" with "${c.name}"$w';
    }
    return 'Added "${c.name}"$w';
  }).join('; ');
}

// ---------- Real implementation ----------

class RealApi implements NutriApi {
  final String? Function()? tokenProvider;

  RealApi({this.tokenProvider}) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenProvider?.call();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(minutes: 10),
    receiveTimeout: const Duration(minutes: 10),
  ));

  Never _handleError(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    if (status == 429) {
      throw ApiException(
        code: 'RATE_LIMITED',
        message: 'You\'re going a little fast! Please wait a minute and try again.',
        retry: true,
      );
    }

    if (data is Map<String, dynamic>) {
      if (data['error'] is Map) throw ApiException.fromAiEnvelope(data);
      final detail = data['detail'];
      if (detail is String) throw ApiException.fromDetail(detail);
      if (detail is List) {
        // FastAPI validation errors. The technical detail goes to the console for you.
        debugPrint('Validation error from server: $detail');
        throw ApiException(
          code: 'INVALID_INPUT',
          message: 'Some details look invalid. Please check your entries and try again.',
          retry: false,
        );
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      throw ApiException(
        code: 'TIMEOUT',
        message: 'This is taking longer than expected. Please try again.',
        retry: true,
      );
    }

    throw ApiException(
      code: 'INTERNAL',
      message: 'Network error. Please check your connection and try again.',
      retry: true,
    );
  }

  // ---- Auth ----

  @override
  Future<AuthSession> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
      return AuthSession.fromLoginResponse(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> register(String name, String email, String password) async {
    try {
      await _dio.post('/auth/register', data: {'name': name, 'email': email, 'password': password});
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<String?> forgotPassword(String email) async {
    try {
      final res = await _dio.post('/auth/forgot-password', data: {'email': email});
      final data = res.data;
      if (data is Map) {
        final t = data['reset_token'] ?? data['token'];
        if (t is String && t.isNotEmpty) return t;
      }
      return null;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {
    try {
      await _dio.post('/auth/reset-password', data: {'token': token, 'new_password': newPassword});
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  // ---- Family ----

  @override
  Future<List<FamilyMember>> getMembers(int userId) async {
    try {
      final res = await _dio.get('/api/family/members', queryParameters: {'user_id': userId});
      return (res.data as List).map((e) => FamilyMember.fromJson(Map<String, dynamic>.from(e))).toList();
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> createMember(int userId, FamilyMember member) async {
    try {
      final res = await _dio.post('/api/family/members',
          queryParameters: {'user_id': userId}, data: member.toJson());
      return FamilyMember.fromJson(Map<String, dynamic>.from(res.data));
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> updateMember(String memberId, FamilyMember member) async {
    try {
      final res = await _dio.put('/api/family/members/$memberId', data: member.toJson());
      return FamilyMember.fromJson(Map<String, dynamic>.from(res.data));
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<void> deleteMember(String memberId) async {
    try {
      await _dio.delete('/api/family/members/$memberId');
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  // ---- AI features ----

  @override
  Future<MealAnalysis> analyzeMeal(Uint8List image, FamilyMember member) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(image, filename: 'meal.jpg'),
      'member_data': jsonEncode(member.toJson()),
    });
    try {
      final res = await _dio.post('/api/meal/analyze',
          data: form, options: Options(receiveTimeout: const Duration(seconds: 90)));
      return MealAnalysis.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<MealAnalysis> correctMeal(
      MealAnalysis previous, List<ItemCorrection> corrections, FamilyMember member) async {
    Future<MealAnalysis> send(Object correctionsPayload) async {
      final res = await _dio.post('/api/meal/correct',
          data: {
            'request_data': {'previous': previous.toJson(), 'corrections': correctionsPayload},
            'member': member.toJson(),
          },
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return MealAnalysis.fromJson(res.data);
    }

    final asText = _correctionsToText(previous, corrections);
    final asList = corrections.map((c) => c.toJson()).toList();

    try {
      return await send(kCorrectionsAsText ? asText : asList);
    } on DioException catch (e) {
      // Our two documents disagree about the type of `corrections` (sentence vs list).
      // If the server rejects the first form (422), try the other one.
      if (e.response?.statusCode == 422) {
        debugPrint('meal/correct rejected the first format (422): ${e.response?.data}');
        try {
          return await send(kCorrectionsAsText ? asList : asText);
        } on DioException catch (e2) {
          _handleError(e2);
        }
      }
      _handleError(e);
    }
  }

  @override
  Future<FridgeInventory> analyzeFridge(Uint8List image) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(image, filename: 'fridge.jpg'),
    });
    try {
      final res = await _dio.post('/api/fridge/analyze',
          data: form, options: Options(receiveTimeout: const Duration(seconds: 90)));
      return FridgeInventory.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<RecipeSuggestions> suggestRecipes(FridgeInventory inventory, List<FamilyMember> family) async {
    try {
      final res = await _dio.post('/api/recipes/suggest',
          data: {
            'inventory': inventory.toRequestJson(),
            'family': family.map((m) => m.toJson()).toList(),
          },
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return RecipeSuggestions.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<WeeklyPlan> generateMealPlan(
      List<FamilyMember> family, FridgeInventory? inventory, List<DayPreference> dayPreferences) async {
    try {
      final res = await _dio.post('/api/meal-plan/generate',
          data: {
            'family': family.map((m) => m.toJson()).toList(),
            'inventory': inventory?.toRequestJson(),
            'day_preferences': dayPreferences.map((d) => d.toJson()).toList(),
          },
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return WeeklyPlan.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<GroceryList> generateGroceryList(List<FamilyMember> family, WeeklyPlan plan,
      FridgeInventory? inventory, List<String> userRequirements) async {
    try {
      final res = await _dio.post('/api/grocery-list/generate',
          data: {
            'family': family.map((m) => m.toJson()).toList(),
            'plan': plan.toJson(),
            'inventory': inventory?.toRequestJson(),
            'user_requirements': userRequirements,
          },
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return GroceryList.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }
}