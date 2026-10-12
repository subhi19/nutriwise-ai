import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/recipe.dart';

String _f(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class RecipeCards extends StatelessWidget {
  final RecipeSuggestions suggestions;
  final List<String> allergiesAvoided;
  final Widget actions;

  const RecipeCards({
    super.key,
    required this.suggestions,
    required this.allergiesAvoided,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🍳 Recipe Ideas', style: t.titleLarge),
        const SizedBox(height: 4),
        Text('Made only from what\'s in your kitchen', style: t.bodySmall),
        if (allergiesAvoided.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Avoiding: ${allergiesAvoided.join(', ')}',
                      style: t.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (suggestions.recipes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('We couldn\'t find a recipe for these ingredients. Try adding a few more items.',
                  style: t.bodyMedium),
            ),
          )
        else
          ...suggestions.recipes.map((r) => _RecipeCard(recipe: r)),
        const SizedBox(height: 4),
        Text('"AI estimate" means we couldn\'t find that item in our nutrition database, so its values are approximate.',
            style: t.bodySmall?.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text('AI-generated suggestions, not medical advice.',
              style: t.bodySmall, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 14),
        actions,
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  const _RecipeCard({required this.recipe});

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = recipe.nutrition;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(recipe.name, style: t.titleMedium),
            if (n != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _pill('${_f(n.calories)} kcal', AppColors.secondary),
                  _pill('${_f(n.proteinG)} g protein', AppColors.primary),
                  _pill('${_f(n.carbsG)} g carbs', AppColors.tertiary),
                  _pill('${_f(n.fatG)} g fat', AppColors.child),
                  _pill('${_f(n.fiberG)} g fiber', AppColors.success),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('Ingredients', style: t.titleSmall),
            const SizedBox(height: 6),
            ...recipe.ingredients.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(Icons.circle, size: 6, color: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(i.label, style: t.bodySmall?.copyWith(color: AppColors.textPrimary)),
                      ),
                      if (i.aiEstimate)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.tertiary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('AI estimate',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                )),
            if (recipe.pantryStaples.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Pantry staples: ${recipe.pantryStaples.join(', ')}',
                    style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ),
            if (recipe.steps.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text('How to make it (${recipe.steps.length} steps)', style: t.titleSmall),
                children: [
                  for (var k = 0; k < recipe.steps.length; k++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: AppColors.primary,
                            child: Text('${k + 1}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(recipe.steps[k],
                                style: t.bodySmall?.copyWith(color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}