import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_logo.dart';
import '../widgets/food_doodles.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            const FoodDoodles(),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  children: [
                    const AppLogo(size: 96),
                    const SizedBox(height: 18),
                    Text(AppIdentity.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 30)),
                    const SizedBox(height: 10),
                    Text(
                      AppIdentity.tagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 4),
                    Text(AppIdentity.subTagline,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.secondary, fontStyle: FontStyle.italic,
                            )),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Text(
                        'NutriWise AI looks at your family\'s meals and what\'s in your kitchen, '
                        'then builds personalized, healthy plans for every age — so everyone eats well '
                        'and less food goes to waste.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _FeatureRow(
                      emoji: '📸', color: AppColors.primary,
                      title: 'Analyze Any Meal',
                      description: 'Snap a photo, instantly see nutrients and what\'s missing',
                    ),
                    const SizedBox(height: 12),
                    const _FeatureRow(
                      emoji: '📅', color: AppColors.secondary,
                      title: '7-Day Family Meal Plans',
                      description: 'Personalized for every family member, age, and preference',
                    ),
                    const SizedBox(height: 12),
                    const _FeatureRow(
                      emoji: '🛒', color: AppColors.tertiary,
                      title: 'Smart Grocery Lists',
                      description: 'Only buy what you don\'t already have at home',
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [AppColors.secondary, AppColors.tertiary]),
                          boxShadow: [
                            BoxShadow(color: AppColors.secondary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => context.go('/profile'),
                            child: const Center(
                              child: Text('Explore Now!',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final Color color;
  final String title;
  final String description;

  const _FeatureRow({required this.emoji, required this.color, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}