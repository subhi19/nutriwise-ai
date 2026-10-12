import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/recipe.dart';
import 'app_logo.dart';

class RecipeExportCard extends StatelessWidget {
  final RecipeSuggestions suggestions;
  final Uint8List? imageBytes;
  final List<String> ingredients;
  final List<String> allergiesAvoided;

  const RecipeExportCard({
    super.key,
    required this.suggestions,
    required this.imageBytes,
    required this.ingredients,
    required this.allergiesAvoided,
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
                    Text('Home Inventory Recipes',
                        style: t.bodySmall?.copyWith(
                            color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
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
          if (allergiesAvoided.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Avoiding: ${allergiesAvoided.join(', ')}',
                style: t.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
          ],
          const Divider(height: 24),
          ...suggestions.recipes.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: t.titleSmall),
                    if (r.nutritionLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 6),
                        child: Text(r.nutritionLine,
                            style: t.bodySmall?.copyWith(
                                color: AppColors.primaryDark, fontWeight: FontWeight.w700, fontSize: 11.5)),
                      ),
                    ...r.ingredients.map((i) => Text('• ${i.label}${i.aiEstimate ? '  (AI estimate)' : ''}',
                        style: t.bodySmall?.copyWith(color: AppColors.textPrimary))),
                    if (r.pantryStaples.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Pantry staples: ${r.pantryStaples.join(', ')}',
                            style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                      ),
                    const SizedBox(height: 6),
                    for (var k = 0; k < r.steps.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('${k + 1}. ${r.steps[k]}', style: t.bodySmall?.copyWith(fontSize: 11.5)),
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          Text('AI-generated suggestions, not medical advice.',
              style: t.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}