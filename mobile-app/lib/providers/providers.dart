import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/family_member.dart';
import '../services/api_service.dart';

// Flip this to false once your backend is live and reachable
const useMock = true;

final apiProvider = Provider<NutriApi>((ref) => useMock ? MockApi() : RealApi());

// TODO: replace with the real logged-in user's id once auth is wired
const demoUserId = 'demo-user';

final membersProvider = FutureProvider<List<FamilyMember>>(
    (ref) => ref.read(apiProvider).getMembers(demoUserId));