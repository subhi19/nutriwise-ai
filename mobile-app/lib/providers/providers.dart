import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/auth_session.dart';
import '../models/family_member.dart';
import '../models/fridge_inventory.dart';
import '../models/meal_plan.dart';
import '../services/api_service.dart';

// Mock by default, so nobody ships mock data by accident.
// Go live with:  --dart-define=USE_MOCK=false
const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

final apiProvider = Provider<NutriApi>((ref) => useMock
    ? MockApi()
    : RealApi(tokenProvider: () => ref.read(authProvider)?.accessToken));

// The logged-in session. Held in memory only (lost on browser refresh).
final authProvider = StateProvider<AuthSession?>((ref) => null);

// Used only by the mock, when nobody has logged in.
const demoUserId = 1;

final membersProvider = FutureProvider<List<FamilyMember>>((ref) async {
  final auth = ref.watch(authProvider);
  // Live mode with nobody logged in: never fall back to the seed account's data.
  if (auth == null && !useMock) return <FamilyMember>[];
  final userId = auth?.userId ?? demoUserId;
  return ref.read(apiProvider).getMembers(userId);
});

final selectedMemberProvider = StateProvider<FamilyMember?>((ref) => null);

// Carried from the Meal Planner to the Grocery List screen
final fridgeInventoryProvider = StateProvider<FridgeInventory?>((ref) => null);
final currentPlanProvider = StateProvider<WeeklyPlan?>((ref) => null);
final planFamilyProvider = StateProvider<List<FamilyMember>>((ref) => []);

/// Ends the session and clears everything that belongs to the logged-in user.
/// If you add another provider that holds user data, reset it here too.
void performLogout(WidgetRef ref) {
  ref.read(authProvider.notifier).state = null;
  ref.read(selectedMemberProvider.notifier).state = null;
  ref.read(fridgeInventoryProvider.notifier).state = null;
  ref.read(currentPlanProvider.notifier).state = null;
  ref.read(planFamilyProvider.notifier).state = [];
  ref.invalidate(membersProvider);
}