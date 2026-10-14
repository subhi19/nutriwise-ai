import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/family_profile_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/meal_analysis_screen.dart';
import '../screens/meal_plan_screen.dart';
import '../screens/fridge_analysis_screen.dart';
import '../screens/grocery_list_screen.dart';

/// Pages anyone can open without being logged in.
const _publicPaths = {'/', '/login', '/signup', '/forgot-password', '/reset-password'};

final routerProvider = Provider<GoRouter>((ref) {
  // Tells the router to re-check its redirect whenever someone logs in or out.
  final loggedIn = ValueNotifier<bool>(ref.read(authProvider) != null);
  ref.listen(authProvider, (_, next) => loggedIn.value = next != null);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: loggedIn,
    redirect: (context, state) {
      final isLoggedIn = ref.read(authProvider) != null;
      if (!isLoggedIn && !_publicPaths.contains(state.uri.path)) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignUpScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          // Works from the Forgot screen (via extra) and from an emailed link (?email=&token=)
          final Map extra = state.extra is Map ? state.extra as Map : const {};
          return ResetPasswordScreen(
            initialEmail: state.uri.queryParameters['email'] ?? extra['email'] as String?,
            initialToken: state.uri.queryParameters['token'] ?? extra['token'] as String?,
          );
        },
      ),
      GoRoute(path: '/profile', builder: (context, state) => const FamilyProfileScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/meal', builder: (context, state) => const MealAnalysisScreen()),
      GoRoute(path: '/plan', builder: (context, state) => const MealPlanScreen()),
      GoRoute(path: '/fridge', builder: (context, state) => const FridgeAnalysisScreen()),
      GoRoute(path: '/grocery', builder: (context, state) => const GroceryListScreen()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    loggedIn.dispose();
  });
  return router;
});