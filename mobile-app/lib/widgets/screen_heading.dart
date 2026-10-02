import 'package:flutter/material.dart';
import '../core/theme.dart';

class ScreenHeading extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  const ScreenHeading({super.key, required this.emoji, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji $title', style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}