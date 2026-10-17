import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/meal_plan.dart';
import 'selectable_chip.dart';

// "Tomato (raw)" -> "tomato", "Green apples" -> "green apple"
String _singular(String w) {
  if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.length > 4 && w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map(_singular)
    .join(' ');

/// Whole-word match, so "Egg" doesn't match "Eggplant".
bool _matches(String ingredient, String pantryItem) {
  final a = _norm(ingredient);
  final b = _norm(pantryItem);
  if (a.length < 3 || b.length < 3) return false;
  return a == b || ' $a '.contains(' $b ') || ' $b '.contains(' $a ');
}

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

  bool _inPantry(List<String> ingredients) =>
      pantry.isNotEmpty && ingredients.any((ing) => pantry.any((p) => _matches(ing, p)));

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
    final t = Theme.of(context).textTheme;

    Widget stat(String label, String value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(value, style: t.titleSmall),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${day.day} total',
              style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 20,
            runSpacing: 12,
            children: [
              stat('CALORIES', day.totalKcalLabel),
              stat('PROTEIN', day.totalProteinLabel),
              if (day.nutrients != null) ...[
                stat('CARBS', day.totalCarbsLabel),
                stat('FAT', day.totalFatLabel),
              ],
            ],
          ),
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
    final t = Theme.of(context).textTheme;
    final hasNotes = meal.notes != null && meal.notes!.trim().isNotEmpty;

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
                  Text(meal.name, style: t.titleSmall),
                  if (meal.items.isNotEmpty) _IngredientList(items: meal.items),
                  if (hasNotes)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meal.notes!,
                          style: t.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic, color: AppColors.primaryDark)),
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

class _IngredientList extends StatelessWidget {
  final List<PlannedIngredient> items;
  const _IngredientList({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasDetail = items.any((i) => i.weightG != null || i.nutrients != null);

    // Names only (simple data): one tidy line
    if (!hasDetail) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(items.map((i) => i.name).join(', '), style: t.bodySmall),
      );
    }

    final anyEstimated = items.any((i) => i.isEstimated);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('Ingredients (${items.length})',
          style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
      children: [
        ...items.map((i) => _IngredientLine(item: i)),
        if (anyEstimated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('* Not in our nutrition database, so these values are AI estimates.',
                style: t.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}

class _IngredientLine extends StatelessWidget {
  final PlannedIngredient item;
  const _IngredientLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final parts = <String>[
      if (item.weightG != null) '${item.weightG!.round()} g',
      if (item.calories != null) '${item.calories!.round()} kcal',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(item.isEstimated ? '${item.name} *' : item.name,
                style: t.bodySmall?.copyWith(color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 8),
          Text(parts.join(' · '), style: t.bodySmall),
        ],
      ),
    );
  }
}