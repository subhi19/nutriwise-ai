import 'package:flutter/material.dart';
import '../core/theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    final showBadge = size >= 64;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              border: Border.all(color: Colors.white, width: size * 0.04),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: size * 0.2,
                  offset: Offset(0, size * 0.08),
                ),
              ],
            ),
            child: Center(child: Text('🥗', style: TextStyle(fontSize: size * 0.5))),
          ),
          if (showBadge)
            Positioned(
              right: -size * 0.04,
              bottom: -size * 0.04,
              child: Container(
                padding: EdgeInsets.all(size * 0.07),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: size * 0.025),
                ),
                child: Text('❤️', style: TextStyle(fontSize: size * 0.16)),
              ),
            ),
        ],
      ),
    );
  }
}