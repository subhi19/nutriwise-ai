import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/auth_session.dart';
import '../models/family_member.dart';
import '../services/api_service.dart';

// Flip to false once ready to hit the real backend
const useMock = true;

final apiProvider = Provider<NutriApi>((ref) => useMock ? MockApi() : RealApi());

// Holds the logged-in session once /auth/login succeeds.
// TODO: persist accessToken via flutter_secure_storage so it survives app restarts.
final authProvider = StateProvider<AuthSession?>((ref) => null);

// Seeded test account's user_id, used as a fallback before real login is exercised.
const demoUserId = 1;

final membersProvider = FutureProvider<List<FamilyMember>>((ref) {
  final auth = ref.watch(authProvider);
  final userId = auth?.userId ?? demoUserId;
  return ref.read(apiProvider).getMembers(userId);
});