import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_brand_bar.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBrandBar(trailingTagline: AppIdentity.dashboardTagline),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 14.0;
                          final cardSize = (constraints.maxWidth - gap) / 2;

                          return SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: cardSize,
                                      height: cardSize,
                                      child: _FeatureCard(
                                        emoji: '📸',
                                        label: 'Analyze',
                                        bgColor: const Color(0xFFDCF0EC),
                                        accent: AppColors.primary,
                                        title: 'Nutrient Analyzer',
                                        description: 'Snap a meal photo and see nutrients instantly.',
                                        onTap: () => context.push('/meal'),
                                      ),
                                    ),
                                    const SizedBox(width: gap),
                                    SizedBox(
                                      width: cardSize,
                                      height: cardSize,
                                      child: _FeatureCard(
                                        emoji: '📅',
                                        label: 'Plan',
                                        bgColor: const Color(0xFFFCE3DE),
                                        accent: AppColors.secondary,
                                        title: 'Meal Planner',
                                        description: 'Build a 7-day plan and a grocery list in one tap.',
                                        onTap: () => context.push('/plan'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: gap),
                                SizedBox(
                                  width: cardSize,
                                  height: cardSize,
                                  child: _FeatureCard(
                                    emoji: '🧊',
                                    label: 'Reduce Waste',
                                    bgColor: const Color(0xFFFCF0D6),
                                    accent: AppColors.tertiary,
                                    title: 'Home Inventory',
                                    description: 'Upload a fridge photo for a quick meal suggestion.',
                                    onTap: () => context.push('/fridge'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String emoji;
  final String label;
  final Color bgColor;
  final Color accent;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.emoji,
    required this.label,
    required this.bgColor,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -6,
              top: -8,
              child: Opacity(
                opacity: 0.22,
                child: Text(emoji, style: const TextStyle(fontSize: 72)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: accent, letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Explore',
                          style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, color: accent, size: 15),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}