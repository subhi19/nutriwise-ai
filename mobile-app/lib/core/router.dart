import 'package:go_router/go_router.dart';
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

final router = GoRouter(
  initialLocation: '/',
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