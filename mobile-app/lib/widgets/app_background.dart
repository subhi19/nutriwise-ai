import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'food_doodles.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showDoodles;
  const AppBackground({super.key, required this.child, this.showDoodles = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned(top: -60, left: -60, child: _blob(AppColors.primary, 220)),
          Positioned(top: 100, right: -80, child: _blob(AppColors.tertiary, 200)),
          Positioned(bottom: -70, left: -40, child: _blob(AppColors.secondary, 220)),
          if (showDoodles) const FoodDoodles(),
          child,
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)]),
        ),
      ),
    );
  }
}