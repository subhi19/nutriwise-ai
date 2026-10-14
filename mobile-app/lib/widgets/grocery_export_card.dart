import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/grocery_list.dart';
import 'app_logo.dart';

class GroceryExportCard extends StatelessWidget {
  final GroceryList list;
  final Set<String> checked;
  final String Function(GroceryItem) keyOf;

  const GroceryExportCard({
    super.key,
    required this.list,
    required this.checked,
    required this.keyOf,
  });

  static const _emoji = {
    'Vegetables': '🥦',
    'Fruits': '🍎',
    'Dairy': '🥛',
    'Grains': '🌾',
    'Protein': '🍗',
    'Pulses': '🌱',
    'Spices & Pantry': '🧂',
    'Other': '🛒',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final groups = <String, List<GroceryItem>>{};
    for (final item in list.items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final done = list.items.where((i) => checked.contains(keyOf(i))).length;

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
                    Text('Grocery List',
                        style: t.bodySmall?.copyWith(
                            color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text('$done / ${list.items.length} done',
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const Divider(height: 24),
          if (list.items.isEmpty)
            Text('🎉 You already have everything you need!', style: t.bodyMedium)
          else
            ...groups.entries.map((entry) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_emoji[entry.key] ?? '🛒'} ${entry.key}', style: t.titleSmall),
                      const SizedBox(height: 6),
                      ...entry.value.map((item) {
                        final isDone = checked.contains(keyOf(item));
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                isDone ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 18,
                                color: isDone ? AppColors.primary : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: t.bodySmall?.copyWith(
                                    color: AppColors.textPrimary,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              Text(item.quantity, style: t.bodySmall),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                )),
          if (list.notInDatabase.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'No nutrition details found for: ${list.notInDatabase.join(', ')}',
              style: t.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}