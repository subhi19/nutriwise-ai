import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/auth_session.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/meal_plan.dart';
import '../services/api_service.dart';

// Mock by default, so nobody ships mock data by accident.
// Go live with:  --dart-define=USE_MOCK=false
const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);

final apiProvider = Provider<NutriApi>((ref) => useMock
    ? MockApi()
    : RealApi(tokenProvider: () => ref.read(authProvider)?.accessToken));

// The logged-in session. Held in memory only (lost on browser refresh).
final authProvider = StateProvider<AuthSession?>((ref) => null);

// Falls back to the seeded test account when nobody has logged in.
const demoUserId = 1;

final membersProvider = FutureProvider<List<FamilyMember>>((ref) {
  final auth = ref.watch(authProvider);
  final userId = auth?.userId ?? demoUserId;
  return ref.read(apiProvider).getMembers(userId);
});

final selectedMemberProvider = StateProvider<FamilyMember?>((ref) => null);

// Carried from the Meal Planner to the Grocery List screen
final fridgeInventoryProvider = StateProvider<FridgeInventory?>((ref) => null);
final currentPlanProvider = StateProvider<WeeklyPlan?>((ref) => null);
final planFamilyProvider = StateProvider<List<FamilyMember>>((ref) => []);