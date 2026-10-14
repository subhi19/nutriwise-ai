import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/meal_plan.dart';
import 'selectable_chip.dart';

class PlanView extends StatelessWidget {
  final WeeklyPlan plan;
  final int selectedDay;
  final List<String> pantry;
  final ValueChanged<int> onDayChanged;
  final Widget actions;
  final String title;

  const PlanView({
    super.key,
    required this.plan,
    required this.selectedDay,
    required this.pantry,
    required this.onDayChanged,
    required this.actions,
    this.title = 'Your 7-Day Plan',
  });

  bool _inPantry(List<String> ingredients) {
    final p = pantry.map((e) => e.toLowerCase()).toList();
    return ingredients.any((ing) {
      final i = ing.toLowerCase();
      return p.any((x) => i.contains(x) || x.contains(i));
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = plan.days[selectedDay.clamp(0, plan.days.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(plan.days.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SelectableChip(
                  label: plan.days[i].day.substring(0, 3),
                  selected: i == selectedDay,
                  color: AppColors.secondary,
                  onSelected: (_) => onDayChanged(i),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        _MealRow(emoji: '🌅', label: 'Breakfast', meal: day.breakfast, have: _inPantry(day.breakfast.ingredients)),
        _MealRow(emoji: '☀️', label: 'Lunch', meal: day.lunch, have: _inPantry(day.lunch.ingredients)),
        _MealRow(emoji: '🌙', label: 'Dinner', meal: day.dinner, have: _inPantry(day.dinner.ingredients)),
        if (day.snack != null)
          _MealRow(emoji: '🍎', label: 'Snack', meal: day.snack!, have: _inPantry(day.snack!.ingredients)),
        const SizedBox(height: 4),
        _DayTotalBar(day: day),
        if (plan.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...plan.notes.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $n', style: Theme.of(context).textTheme.bodySmall),
              )),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text('AI-generated suggestions, not medical advice.',
              style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 14),
        actions,
      ],
    );
  }
}

class _DayTotalBar extends StatelessWidget {
  final DayPlan day;
  const _DayTotalBar({required this.day});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          stat('${day.day.toUpperCase()} TOTAL', day.totalKcalLabel),
          stat('PROTEIN', day.totalProteinLabel),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final String emoji;
  final String label;
  final PlannedMeal meal;
  final bool have;
  const _MealRow({required this.emoji, required this.label, required this.meal, required this.have});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(label.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5)),
                      if (have)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('✓ you have some of this',
                              style: TextStyle(
                                  fontSize: 10.5, color: AppColors.success, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meal.name, style: Theme.of(context).textTheme.titleSmall),
                  if (meal.ingredients.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meal.ingredients.join(', '), style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (meal.notes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meal.notes!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic, color: AppColors.primaryDark)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(meal.kcalLabel,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary)),
            ),
          ],
        ),
      ),
    );
  }
}