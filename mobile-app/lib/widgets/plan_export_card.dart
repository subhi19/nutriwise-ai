import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/meal_plan.dart';
import 'app_logo.dart';

class PlanExportCard extends StatelessWidget {
  final WeeklyPlan plan;
  final List<String> familyNames;
  final String title;
  final Uint8List? imageBytes;
  final List<String> ingredients;

  const PlanExportCard({
    super.key,
    required this.plan,
    required this.familyNames,
    this.title = '7-Day Meal Plan',
    this.imageBytes,
    this.ingredients = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppIdentity.name, style: t.titleMedium),
                    Text(title,
                        style: t.bodySmall?.copyWith(
                            color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (familyNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('For: ${familyNames.join(', ')}', style: t.bodySmall),
          ],
          if (imageBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(imageBytes!, height: 140, width: double.infinity, fit: BoxFit.cover),
            ),
          ],
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('From your kitchen: ${ingredients.join(', ')}',
                style: t.bodySmall?.copyWith(color: AppColors.textPrimary)),
          ],
          const Divider(height: 24),
          ...plan.days.map((d) => _ExportDay(day: d)),
          if (plan.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Notes', style: t.titleSmall),
            const SizedBox(height: 4),
            ...plan.notes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('• $n', style: t.bodySmall?.copyWith(fontSize: 11.5)),
                )),
          ],
          const SizedBox(height: 10),
          Text('AI-generated suggestions, not medical advice.',
              style: t.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _ExportDay extends StatelessWidget {
  final DayPlan day;
  const _ExportDay({required this.day});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(day.day, style: t.titleSmall)),
              Text('${day.totalKcalLabel} · protein ${day.totalProteinLabel}',
                  style: t.bodySmall?.copyWith(
                      color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          _line(context, 'Breakfast', day.breakfast),
          _line(context, 'Lunch', day.lunch),
          _line(context, 'Dinner', day.dinner),
          if (day.snack != null) _line(context, 'Snack', day.snack!),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, PlannedMeal meal) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(meal.name, style: t.bodySmall?.copyWith(color: AppColors.textPrimary))),
          const SizedBox(width: 8),
          Text(meal.kcalLabel, style: t.bodySmall),
        ],
      ),
    );
  }
}