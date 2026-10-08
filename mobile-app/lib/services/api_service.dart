import 'package:dio/dio.dart';
import '../models/auth_session.dart';
import '../models/family_member.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../models/meal_analysis.dart';
import '../models/nutrient_totals.dart';
import '../models/day_preference.dart';
import '../models/fridge_inventory.dart';
import '../models/meal_plan.dart';
import '../models/meal_type.dart';

// Flip to true once AI/backend confirm they accept `day_preferences`.
const kSendDayPreferences = false;

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
  Future<void> forgotPassword(String email);
  Future<List<FamilyMember>> getMembers(int userId);
  Future<FamilyMember> createMember(int userId, FamilyMember member);
  Future<FamilyMember> updateMember(String memberId, FamilyMember member);
  Future<MealAnalysis> analyzeMeal(Uint8List image, FamilyMember member);
  Future<MealAnalysis> correctMeal(MealAnalysis previous, List<ItemCorrection> corrections, FamilyMember member);
  Future<FridgeInventory> analyzeFridge(Uint8List image);
  Future<WeeklyPlan> generateMealPlan(
    List<FamilyMember> family, FridgeInventory? inventory, List<DayPreference> dayPreferences);
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
  Future<void> forgotPassword(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
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

    PlannedMeal m(String n, List<String> i, [String? note]) =>
        PlannedMeal(name: n, ingredients: i, notes: note);

    final breakfasts = [
      m('Oats with banana', ['Oats', 'Banana', 'Milk']),
      m('Vegetable upma', ['Semolina', 'Carrot', 'Peas']),
      m('Egg bhurji with toast', ['Eggs', 'Onion', 'Bread']),
      m('Idli with sambar', ['Idli batter', 'Lentils', 'Mixed vegetables']),
    ];
    final lunches = [
      m('Brown rice with dal', ['Brown rice', 'Yellow dal']),
      m('Chapati with mixed veg curry', ['Wheat flour', 'Beans', 'Carrot']),
      m('Veg pulao with raita', ['Basmati rice', 'Peas', 'Yogurt']),
      m('Rajma with rice', ['Kidney beans', 'Rice', 'Onion']),
    ];
    final dinners = [
      m('Vegetable soup with toast', ['Carrot', 'Beans', 'Tomato', 'Bread']),
      m('Paneer bhurji with roti', ['Paneer', 'Onion', 'Wheat flour']),
      m('Khichdi with curd', ['Rice', 'Moong dal', 'Yogurt']),
      m('Palak dal with chapati', ['Spinach', 'Toor dal', 'Wheat flour']),
    ];
    final pantry = inventory?.items.map((i) => i.name).toList() ?? <String>[];

    final days = <DayPlan>[];
    for (var i = 0; i < 7; i++) {
      final pref = i < dayPreferences.length ? dayPreferences[i] : null;
      final typeLabel = pref == null ? null : mealTypeByCode(pref.mealTypeCode).label;
      final b = breakfasts[i % breakfasts.length];
      final l = lunches[i % lunches.length];
      var d = dinners[i % dinners.length];
      // Make the pantry visible in the mock: weave inventory items into a couple of dinners
      if (pantry.isNotEmpty && (i == 0 || i == 3)) {
        d = m(d.name, [...d.ingredients, ...pantry.take(2)], 'Uses items from your fridge');
      }
      days.add(DayPlan(
        day: kWeekdays[i],
        breakfast: b,
        lunch: m(l.name, l.ingredients, typeLabel),
        dinner: d,
        ingredients: {...b.ingredients, ...l.ingredients, ...d.ingredients}.toList(),
      ));
    }
    return WeeklyPlan(days: days, notes: ['Mock plan for UI testing only.']);
  }
}

// ---------- Real implementation ----------

class RealApi implements NutriApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8000', // 10.0.2.2:8000 for Android emulator
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Never _handleError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      if (data.containsKey('error')) throw ApiException.fromAiEnvelope(data);
      if (data.containsKey('detail')) throw ApiException.fromDetail(data['detail'].toString());
    }
    throw ApiException(
      code: 'INTERNAL',
      message: 'Network error. Please check your connection and try again.',
      retry: true,
    );
  }

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
  Future<List<FamilyMember>> getMembers(int userId) async {
    try {
      final res = await _dio.get('/api/family/members', queryParameters: {'user_id': userId});
      return (res.data as List).map((e) => FamilyMember.fromJson(e)).toList();
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> createMember(int userId, FamilyMember member) async {
    try {
      final res = await _dio.post('/api/family/members',
          queryParameters: {'user_id': userId}, data: member.toJson());
      return FamilyMember.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FamilyMember> updateMember(String memberId, FamilyMember member) async {
    try {
      final res = await _dio.put('/api/family/members/$memberId', data: member.toJson());
      return FamilyMember.fromJson(res.data);
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

  @override
  Future<void> forgotPassword(String email) async {
    try {
      // TODO: confirm this endpoint with backend — not yet documented in v2.0 contract.
      await _dio.post('/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<MealAnalysis> analyzeMeal(Uint8List image, FamilyMember member) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(image, filename: 'meal.jpg'),
      'member_data': jsonEncode(member.toJson()),
    });
    try {
      final res = await _dio.post('/api/meal/analyze', data: form,
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return MealAnalysis.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<MealAnalysis> correctMeal(MealAnalysis previous, List<ItemCorrection> corrections, FamilyMember member) async {
    try {
      final res = await _dio.post('/api/meal/correct', data: {
        'request_data': {
          'previous': previous.toJson(),
          'corrections': corrections.map((c) => c.toJson()).toList(),
        },
        'member': member.toJson(),
      });
      return MealAnalysis.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<FridgeInventory> analyzeFridge(Uint8List image) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(image, filename: 'fridge.jpg'),
    });
    try {
      final res = await _dio.post('/api/fridge/analyze', data: form,
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return FridgeInventory.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<WeeklyPlan> generateMealPlan(
      List<FamilyMember> family, FridgeInventory? inventory, List<DayPreference> dayPreferences) async {
    final body = <String, dynamic>{
      'family': family.map((m) => m.toJson()).toList(),
      'inventory': inventory?.toJson(),
      if (kSendDayPreferences)
        'day_preferences': {for (final dp in dayPreferences) dp.day: dp.toJson()},
    };
    try {
      final res = await _dio.post('/api/meal-plan/generate', data: body,
          options: Options(receiveTimeout: const Duration(seconds: 90)));
      return WeeklyPlan.fromJson(res.data);
    } on DioException catch (e) {
      _handleError(e);
    }
  }
}